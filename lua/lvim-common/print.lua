-- lvim-common.print: print a buffer — to a printer or to a PDF (:LvimPrint).
--
-- Neovim removed `:hardcopy` in 0.9, together with 'printexpr', 'printdevice', 'printfont' and the
-- rest of the print options, and pointed at `:TOhtml` plus a browser instead. This module is that
-- road, walked for you:
--
--   buffer ─ tohtml ─▶ HTML ─ headless Chromium ─▶ PDF ─ lp ─▶ printer
--
-- `tohtml` (bundled with Neovim as the optional package `nvim.tohtml`) renders the buffer the way a
-- window shows it — the live colorscheme, treesitter and syntax highlighting, the line numbers — so
-- the page looks like the editor, not like a plain-text dump. Chromium lays it out on paper: it is the
-- only browser whose command line prints to PDF, and it understands the paged-media CSS used here for
-- the running header and the page counter. `lp` hands the PDF to CUPS.
--
-- `:LvimPrint` opens a dialog in the middle of the screen: the target (a PDF, or one of the CUPS
-- printers), the paper, the colours, the copies and the duplexing. Each printer starts from its own
-- settings (`print.printers`); `:LvimPrint pdf …` / `:LvimPrint printer …` skip the dialog.
--
---@module "lvim-common.print"

local config = require("lvim-common.config")

local M = {}

---@alias LvimPrintColors "theme"|"mono"
---@alias LvimPrintDuplex "long"|"short"|false  false = one-sided; nil = leave it to the printer

---@class LvimPrintPrinter
---@field colors?  LvimPrintColors         "mono" (black on white) or "theme" (the colorscheme, background included)
---@field copies?  integer
---@field duplex?  LvimPrintDuplex
---@field paper?   string                   paper size for this printer; nil = `page.size`
---@field options? table<string, string>   raw CUPS options, sent as `lp -o key=value`

---@class LvimPrintPage
---@field size        string                    "A4", "A5", "A3", "Letter", "Legal"
---@field orientation "portrait"|"landscape"
---@field margin      string                    CSS page margin

---@class LvimPrintConfig
---@field browser?     string|string[]                     Chromium-family executable(s) to try; nil = the built-in list
---@field printer?     string                              the dialog's initial printer; nil = the CUPS default
---@field number_lines boolean                             print line numbers (always absolute)
---@field font_size    string                              CSS font size of the code
---@field header       boolean                             file name on top of every page, "page / pages" at the bottom
---@field page         LvimPrintPage
---@field pdf          { colors: LvimPrintColors }
---@field printers     table<string, LvimPrintPrinter>     per CUPS destination; ["*"] = the base for every printer

---@class LvimPrintJob
---@field kind        "pdf"|"printer"
---@field dest?       string              printer: the CUPS destination (nil = the default one)
---@field path?       string              pdf: where the file goes
---@field range?      integer[]           { first, last }, 1-based inclusive; nil = the whole buffer
---@field colors      LvimPrintColors
---@field numbers     boolean
---@field paper       string
---@field orientation "portrait"|"landscape"
---@field copies      integer
---@field duplex?     LvimPrintDuplex
---@field options     table<string, string>

--- Chromium-family browsers, in the order they are tried. Firefox is not here on purpose: it has no
--- command-line print-to-PDF.
local BROWSERS = {
    "chromium",
    "chromium-browser",
    "google-chrome",
    "google-chrome-stable",
    "brave",
    "brave-browser",
    "microsoft-edge",
}

--- Paper sizes the dialog offers — names both CSS `@page size` and CUPS `media` understand.
local PAPERS = { "A4", "A5", "A3", "Letter", "Legal" }

--- `lp -o sides=` for each duplex setting.
local SIDES = { long = "two-sided-long-edge", short = "two-sided-short-edge" }

---@param msg string
---@param level? integer
local function notify(msg, level)
    vim.notify("lvim-common: " .. msg, level or vim.log.levels.INFO, { title = "LvimPrint" })
end

-- ─── the environment: browser, printers, settings ──────────────────────────────

--- The first configured (or known) Chromium-family browser on $PATH.
---@return string|nil exe
---@return string[] tried  the names that were looked for, for the error message
function M.browser()
    local want = config.print.browser
    local list = type(want) == "string" and { want } or want or BROWSERS
    for _, exe in ipairs(list) do
        if vim.fn.executable(exe) == 1 then
            return exe, list
        end
    end
    return nil, list
end

---@class LvimPrintPrinters
---@field names    string[]                 the CUPS queues, the system default first
---@field default? string
---@field disabled table<string, boolean>   queues CUPS has STOPPED — the queue, not the printer: a job that
---                                          hit a sleeping or unplugged printer pauses it, and the jobs behind
---                                          wait until `cupsenable`, however awake the printer is again

--- Listing the queues is SLOW on the client side: every `lpstat` that enumerates them (-p, -a, -e,
--- -v) waits about a second while libcups browses the network for printers (DNS-SD), however few
--- there are; only `lpstat -d` (the default) answers at once. So the list is kept here, refreshed
--- in the background, and the dialog opens on whatever is already known.
---@type LvimPrintPrinters|nil
local printer_cache = nil

--- lpstat's messages are translated; the parsing below reads the untranslated ones.
local LPSTAT = { text = true, env = { LC_ALL = "C" } }

---@param p_out string  `lpstat -p`
---@param d_out string  `lpstat -d`
---@return LvimPrintPrinters
local function parse_printers(p_out, d_out)
    local list = { names = {}, disabled = {} }
    list.default = d_out:match("destination:%s*(%S+)")
    for line in p_out:gmatch("[^\n]+") do
        local name, state = line:match("^printer%s+(%S+)%s+(.*)$")
        if name then
            list.names[#list.names + 1] = name
            list.disabled[name] = state:find("disabled", 1, true) ~= nil
        end
    end
    table.sort(list.names, function(a, b)
        if (a == list.default) ~= (b == list.default) then
            return a == list.default
        end
        return a < b
    end)
    return list
end

--- Re-read the queues in the background; `on_done` gets the fresh list (the cache holds it too).
---@param on_done? fun(list: LvimPrintPrinters)
function M.refresh_printers(on_done)
    if vim.fn.executable("lpstat") ~= 1 then
        printer_cache = { names = {}, disabled = {} }
        if on_done then
            on_done(printer_cache)
        end
        return
    end
    local out, pending = {}, 2
    local function collect(key)
        return function(res)
            out[key] = res.stdout or ""
            pending = pending - 1
            if pending == 0 then
                vim.schedule(function()
                    printer_cache = parse_printers(out.p, out.d)
                    if on_done then
                        on_done(printer_cache)
                    end
                end)
            end
        end
    end
    vim.system({ "lpstat", "-p" }, LPSTAT, collect("p"))
    vim.system({ "lpstat", "-d" }, LPSTAT, collect("d"))
end

--- The CUPS queues — the system default first — and the default itself. Answers from the cache;
--- the first call without one blocks for the listing (about a second, see `printer_cache`).
---@return string[] names
---@return string|nil default
---@return table<string, boolean> disabled
function M.printers()
    if not printer_cache then
        if vim.fn.executable("lpstat") ~= 1 then
            return {}, nil, {}
        end
        local p_out = vim.system({ "lpstat", "-p" }, LPSTAT):wait().stdout or ""
        local d_out = vim.system({ "lpstat", "-d" }, LPSTAT):wait().stdout or ""
        printer_cache = parse_printers(p_out, d_out)
    end
    return printer_cache.names, printer_cache.default, printer_cache.disabled
end

--- What the dialog can open on RIGHT NOW: the cache, or else just the default printer, which
--- `lpstat -d` names without the slow listing.
---@return LvimPrintPrinters
local function printers_now()
    if printer_cache then
        return printer_cache
    end
    if vim.fn.executable("lpstat") ~= 1 then
        return { names = {}, disabled = {} }
    end
    local default = (vim.system({ "lpstat", "-d" }, LPSTAT):wait().stdout or ""):match("destination:%s*(%S+)")
    return { names = default and { default } or {}, default = default, disabled = {} }
end

--- A printer's settings: `printers["*"]` with `printers[dest]` laid over it.
---@param dest? string
---@return LvimPrintPrinter
function M.settings(dest)
    local all = config.print.printers or {}
    local base = { colors = "mono", copies = 1, options = {} }
    return vim.tbl_deep_extend("force", base, all["*"] or {}, dest and all[dest] or {})
end

--- A job from the configuration alone — what `:LvimPrint pdf` / `printer` run, and where the dialog starts.
---@param kind "pdf"|"printer"
---@param target? string  the PDF path or the printer
---@param range? integer[]
---@return LvimPrintJob
function M.job(kind, target, range)
    local cfg = config.print
    local job = {
        kind = kind,
        range = range,
        numbers = cfg.number_lines,
        paper = cfg.page.size,
        orientation = cfg.page.orientation,
        copies = 1,
        options = {},
    }
    if kind == "pdf" then
        job.path = target
        job.colors = cfg.pdf.colors
    else
        -- Resolved to a NAME even for the default printer, so its own `printers[<name>]` entry applies.
        job.dest = target or cfg.printer or printers_now().default
        local s = M.settings(job.dest)
        job.colors = s.colors
        job.copies = s.copies
        job.duplex = s.duplex
        job.paper = s.paper or job.paper
        job.options = s.options
    end
    return job
end

-- ─── buffer → HTML ─────────────────────────────────────────────────────────────

--- `tohtml` ships as an optional package since Neovim 0.12; it has to be added before it can be
--- required.
---@return table|nil tohtml
---@return string|nil err
local function load_tohtml()
    local ok, mod = pcall(require, "tohtml")
    if ok then
        return mod
    end
    pcall(vim.cmd.packadd, "nvim.tohtml")
    ok, mod = pcall(require, "tohtml")
    if ok then
        return mod
    end
    return nil, "tohtml is not available (the nvim.tohtml package ships with Neovim >= 0.10)"
end

--- The window options a PRINT is rendered with, whatever the user's window looks like. tohtml draws
--- the window's own number column: 'relativenumber' would print distances instead of line numbers,
--- a custom 'statuscolumn' would print its git bar and signs, closed folds would print as fold lines.
local CLEAN_WINDOW = {
    number = true,
    relativenumber = false,
    statuscolumn = "",
    signcolumn = "no",
    foldcolumn = "0",
    foldenable = false,
    cursorline = false,
    cursorcolumn = false,
    colorcolumn = "",
    list = false,
    spell = false,
}

--- Run `fn` with a hidden window on the current buffer, set up with `CLEAN_WINDOW`. The user's own
--- window is never touched: nothing flickers, and nothing has to be put back if `fn` fails.
---@generic T
---@param fn fun(win: integer): T
---@return boolean ok
---@return T|string result_or_err
local function in_clean_window(fn)
    local src = vim.api.nvim_get_current_win()
    local win = vim.api.nvim_open_win(vim.api.nvim_win_get_buf(src), false, {
        relative = "editor",
        row = 0,
        col = 0,
        width = vim.api.nvim_win_get_width(src),
        height = math.max(1, vim.api.nvim_win_get_height(src)),
        hide = true,
        focusable = false,
        noautocmd = true,
    })
    for name, value in pairs(CLEAN_WINDOW) do
        pcall(vim.api.nvim_set_option_value, name, value, { win = win })
    end
    local ok, res = pcall(fn, win)
    pcall(vim.api.nvim_win_close, win, true)
    return ok, res
end

---@param s string
---@return string
local function css_string(s)
    return '"' .. s:gsub("\\", "\\\\"):gsub('"', '\\"') .. '"'
end

--- Give every source line its own block, so a line that wraps continues AFTER the number column
--- instead of under it.
---
--- tohtml writes the code as one <pre> with a line of text per source line, and a span that
--- covers several lines (a long string, a block comment) opens on one line and closes on a later
--- one. A line cannot become a block around that, so the spans are re-balanced first: whatever is
--- still open at the end of a line is closed there and opened again at the start of the next.
--- The lines are then joined with NO newline — inside a pre-wrap container a newline between two
--- blocks would render as an empty line.
---
--- The range is cut HERE, not by tohtml: its own `range` option offsets the line numbers a second
--- time (line 30 of a 30-70 range is numbered 59) and stops numbering at the range's last line
--- number, so most of the range comes out unnumbered. The whole buffer is rendered with numbers
--- instead, and each row is placed by the number tohtml wrote on it; a row without one (a virtual
--- line) belongs to the line above it.
---@param body     string[]    the lines between <pre> and </pre>
---@param range?   integer[]   { first, last } to keep; nil = every line
---@param numbers  boolean     keep the line numbers
---@return string
local function blocks(body, range, numbers)
    local out = {}
    local open = {} ---@type string[]  opening tags still unclosed, outermost first
    local lnum = 0
    for _, line in ipairs(body) do
        local n = line:match('^<span class="LineNr">%s*(%d+)')
        if n then
            lnum = tonumber(n) --[[@as integer]]
        end
        local reopened = table.concat(open)
        for tag in line:gmatch("</?span[^>]*>") do
            if tag:sub(2, 2) == "/" then
                open[#open] = nil
            else
                open[#open + 1] = tag
            end
        end
        if not range or (lnum >= range[1] and lnum <= range[2]) then
            local row = numbers and line or line:gsub('^<span class="LineNr">[^<]*</span>', "", 1)
            out[#out + 1] = '<div class="lvim-print-line">'
                .. reopened
                .. row
                .. string.rep("</span>", #open)
                .. "</div>"
        end
    end
    return table.concat(out)
end

--- The stylesheet laid over tohtml's own: paper, wrapping, the running header, the colour mode.
--- `!important` because tohtml's class rules would otherwise win.
---@param job LvimPrintJob
---@param title string
---@param numwidth integer  width of the line-number column, in characters
---@return string[]  one line per entry: `writefile` stores a "\n" INSIDE an entry as a NUL byte,
---                  and a NUL in the stylesheet makes the browser drop all of it
local function stylesheet(job, title, numwidth)
    local cfg = config.print
    local size = job.paper .. (job.orientation == "landscape" and " landscape" or "")
    local page = { "size: " .. size .. ";", "margin: " .. cfg.page.margin .. ";" }
    if cfg.header then
        local box = "font: 8pt monospace; color: #888;"
        page[#page + 1] = "@top-left { content: " .. css_string(title) .. "; " .. box .. " }"
        page[#page + 1] = '@bottom-right { content: counter(page) " / " counter(pages); ' .. box .. " }"
    end
    local css = {
        "<style>",
        "@page { " .. table.concat(page, " ") .. " }",
        -- tohtml centres the code with a flex body, which keeps the <pre> at its natural width, so
        -- a long line ran off the page instead of wrapping.
        "body { display: block !important; margin: 0; }",
        ("pre { margin: 0; white-space: pre-wrap; overflow-wrap: anywhere; font-size: %s; }"):format(cfg.font_size),
        -- Hanging indent: the continuation of a wrapped line lines up after the numbers.
        (".lvim-print-line { padding-left: %dch; text-indent: -%dch; }"):format(numwidth, numwidth),
    }
    if job.colors == "mono" then
        css[#css + 1] = "* { color: #000 !important; background: #fff !important; }"
        css[#css + 1] = ".LineNr { color: #888 !important; }"
    else
        -- Backgrounds are left off a print by default; "theme" means the page looks like the screen.
        css[#css + 1] = "* { -webkit-print-color-adjust: exact; print-color-adjust: exact; }"
    end
    css[#css + 1] = "</style>"
    return css
end

--- The page title: the file name, and the lines when only some of them are printed.
---@param range? integer[]
---@return string
local function title_of(range)
    local name = vim.api.nvim_buf_get_name(0)
    local title = name ~= "" and vim.fn.fnamemodify(name, ":t") or "[No Name]"
    if range then
        title = ("%s  %d–%d"):format(title, range[1], range[2])
    end
    return title
end

--- Render the current buffer (or the job's range of it) as print-ready HTML.
---@param job LvimPrintJob
---@return string[]|nil lines
---@return string title_or_err
function M.html(job)
    local tohtml, err = load_tohtml()
    if not tohtml then
        return nil, err --[[@as string]]
    end
    local title = title_of(job.range)
    -- Always numbered, never ranged: the numbers are how blocks() finds the range (see there).
    local ok, lines = in_clean_window(function(win)
        return tohtml.tohtml(win, { title = title, number_lines = true })
    end)
    if not ok then
        return nil, "tohtml failed: " .. tostring(lines)
    end
    ---@cast lines string[]

    local pre_open, pre_close
    for i, line in ipairs(lines) do
        if not pre_open and line == "<pre>" then
            pre_open = i
        elseif line == "</pre>" then
            pre_close = i
        end
    end
    -- The number column is as wide as tohtml drew it (it pads to 'numberwidth' and the widest number).
    local numwidth = 0
    if job.numbers and pre_open then
        local first = (lines[pre_open + 1] or ""):match('^<span class="LineNr">([^<]*)</span>')
        numwidth = first and vim.fn.strdisplaywidth(first) or 0
    end

    local out = {}
    for i, line in ipairs(lines) do
        if line == "</head>" then
            vim.list_extend(out, stylesheet(job, title, numwidth))
        end
        if pre_open and pre_close and i > pre_open and i < pre_close then
            if i == pre_open + 1 then
                out[#out + 1] = blocks(vim.list_slice(lines, pre_open + 1, pre_close - 1), job.range, job.numbers)
            end
        else
            out[#out + 1] = line
        end
    end
    return out, title
end

-- ─── HTML → PDF → printer ──────────────────────────────────────────────────────

--- Turn HTML into a PDF with a headless Chromium. Runs in the background; `on_done` gets the PDF
--- path, or nil and the reason. A throwaway profile keeps it clear of a browser the user has open
--- (the default profile would be locked, or would hand the job to the running instance).
---@param html string[]
---@param pdf string
---@param on_done fun(pdf: string|nil, err: string|nil)
local function render_pdf(html, pdf, on_done)
    local exe, tried = M.browser()
    if not exe then
        on_done(nil, "no Chromium-family browser found (tried: " .. table.concat(tried, ", ") .. ")")
        return
    end
    local work = vim.fn.tempname()
    vim.fn.mkdir(work, "p")
    local src = work .. "/print.html"
    vim.fn.writefile(html, src)
    vim.fn.delete(pdf)
    vim.system({
        exe,
        "--headless=new",
        "--disable-gpu",
        "--no-first-run",
        "--no-default-browser-check",
        "--user-data-dir=" .. work .. "/profile",
        "--no-pdf-header-footer",
        "--print-to-pdf=" .. pdf,
        "file://" .. src,
    }, { text = true }, function(res)
        vim.schedule(function()
            vim.fn.delete(work, "rf")
            if res.code == 0 and vim.fn.filereadable(pdf) == 1 then
                on_done(pdf, nil)
            else
                local why = vim.trim(res.stderr or "")
                on_done(nil, exe .. " exited " .. res.code .. (why ~= "" and (": " .. why) or ""))
            end
        end)
    end)
end

--- The `lp` command line for a job.
---@param job LvimPrintJob
---@param title string
---@param pdf string
---@return string[]
function M.lp_command(job, title, pdf)
    local cmd = { "lp", "-t", title }
    if job.dest then
        vim.list_extend(cmd, { "-d", job.dest })
    end
    if job.copies and job.copies > 1 then
        vim.list_extend(cmd, { "-n", tostring(job.copies) })
    end
    -- The PDF is laid out on `paper`; the printer must feed the same sheet, or CUPS scales one onto
    -- the other (a printer left at its factory Letter shrinks every A4 page).
    vim.list_extend(cmd, { "-o", "media=" .. job.paper })
    if job.duplex ~= nil then
        vim.list_extend(cmd, { "-o", "sides=" .. (SIDES[job.duplex] or "one-sided") })
    end
    local keys = vim.tbl_keys(job.options or {})
    table.sort(keys)
    for _, key in ipairs(keys) do
        vim.list_extend(cmd, { "-o", key .. "=" .. tostring(job.options[key]) })
    end
    cmd[#cmd + 1] = pdf
    return cmd
end

--- Carry out a job: render, then write the PDF or send it to the printer.
---@param job LvimPrintJob
function M.run(job)
    if job.kind == "printer" and vim.fn.executable("lp") ~= 1 then
        notify("`lp` not found — printing needs CUPS", vim.log.levels.ERROR)
        return
    end
    local html, title = M.html(job)
    if not html then
        notify(title, vim.log.levels.ERROR)
        return
    end
    notify("rendering " .. title .. " …")

    if job.kind == "pdf" then
        local path = vim.fn.fnamemodify(vim.fn.expand(job.path), ":p")
        render_pdf(html, path, function(pdf, err)
            if pdf then
                notify("PDF written: " .. vim.fn.fnamemodify(pdf, ":~"))
            else
                notify("PDF failed — " .. err, vim.log.levels.ERROR)
            end
        end)
        return
    end

    render_pdf(html, vim.fn.tempname() .. ".pdf", function(file, err)
        if not file then
            notify("print failed — " .. err, vim.log.levels.ERROR)
            return
        end
        vim.system(M.lp_command(job, title, file), { text = true }, function(res)
            vim.schedule(function()
                vim.fn.delete(file)
                if res.code == 0 then
                    -- lp answers "request id is <dest>-<n> (1 file(s))"
                    local id = (res.stdout or ""):match("request id is (%S+)")
                    local where = job.dest or "the default printer"
                    notify(("sent to %s%s"):format(where, id and (" — job " .. id) or ""))
                    -- A stopped queue still ACCEPTS the job; it just holds it. Say so, or the page
                    -- silently never comes out.
                    if job.dest and printer_cache and printer_cache.disabled[job.dest] then
                        notify(
                            ("the CUPS queue of %s is stopped — the job waits until `cupsenable %s`"):format(
                                job.dest,
                                job.dest
                            ),
                            vim.log.levels.WARN
                        )
                    end
                else
                    notify("lp failed: " .. vim.trim(res.stderr or ""), vim.log.levels.ERROR)
                end
            end)
        end)
    end)
end

--- The current buffer (or `range` of it) to a PDF file, with the configured settings.
---@param path string
---@param range? integer[]
function M.to_pdf(path, range)
    M.run(M.job("pdf", path, range))
end

--- The current buffer (or `range` of it) to a printer, with that printer's settings.
---@param dest? string  nil = `print.printer`, else the CUPS default
---@param range? integer[]
function M.to_printer(dest, range)
    M.run(M.job("printer", dest, range))
end

--- Where a PDF of the current buffer goes by default: its own name with a .pdf extension.
---@return string
local function default_pdf_path()
    local name = vim.api.nvim_buf_get_name(0)
    local path = name ~= "" and (vim.fn.fnamemodify(name, ":r") .. ".pdf") or (vim.fn.getcwd() .. "/print.pdf")
    return vim.fn.fnamemodify(path, ":~")
end

--- Ask where the PDF goes, then write it.
---@param range? integer[]
function M.ask_pdf(range)
    vim.ui.input({ prompt = "PDF file: ", default = default_pdf_path(), completion = "file" }, function(path)
        if path and path ~= "" then
            M.to_pdf(path, range)
        end
    end)
end

-- ─── the dialog ────────────────────────────────────────────────────────────────

local DUPLEX_LABELS = { "Printer default", "Off", "Long edge", "Short edge" }
local DUPLEX_VALUES = { ["Off"] = false, ["Long edge"] = "long", ["Short edge"] = "short" }

---@param duplex? LvimPrintDuplex
---@return string
local function duplex_label(duplex)
    if duplex == nil then
        return "Printer default"
    end
    for label, value in pairs(DUPLEX_VALUES) do
        if value == duplex then
            return label
        end
    end
    return "Printer default"
end

---@param colors LvimPrintColors
---@return string
local function colors_label(colors)
    return colors == "theme" and "Theme colours" or "Black on white"
end

--- The print dialog: a popup in the middle of the screen with the target and its settings, and a
--- Print button. Switching the target to another printer loads THAT printer's settings.
---@param range? integer[]
function M.open(range)
    local ok_ui, ui = pcall(require, "lvim-ui")
    if not ok_ui then
        local msg = "lvim-ui not found — the print dialog needs it (:LvimPrint pdf / printer still work)"
        notify(msg, vim.log.levels.ERROR)
        return
    end
    -- Open at once on what is known; the full list arrives in the background (see `printer_cache`).
    local known = printers_now()
    local dest_of = {} ---@type table<string, string>  target label → CUPS destination
    ---@param list LvimPrintPrinters
    ---@return string[]
    local function target_labels(list)
        for label in pairs(dest_of) do
            dest_of[label] = nil
        end
        local labels = { "PDF file" }
        for _, name in ipairs(list.names) do
            local tags = {}
            if name == list.default then
                tags[#tags + 1] = "default"
            end
            if list.disabled[name] then
                tags[#tags + 1] = "queue stopped"
            end
            local label = name .. (#tags > 0 and ("  (" .. table.concat(tags, " · ") .. ")") or "")
            labels[#labels + 1] = label
            dest_of[label] = name
        end
        return labels
    end
    local targets = target_labels(known)

    local initial = config.print.printer or known.default
    local job = initial and #known.names > 0 and M.job("printer", initial, range)
        or M.job("pdf", default_pdf_path(), range)
    job.path = job.path or default_pdf_path()
    local whole = false -- the dialog can widen a range back to the whole buffer

    local function is_pdf()
        return job.kind == "pdf"
    end

    local rows = {}
    local row = {} ---@type table<string, table>  the rows a target switch refreshes, by name

    ---@return string  the target row's label for the job as it stands
    local function target_label()
        if job.kind == "printer" then
            for label, dest in pairs(dest_of) do
                if dest == job.dest then
                    return label
                end
            end
        end
        return "PDF file"
    end

    row.target = {
        type = "select",
        name = "target",
        label = "Print to",
        value = target_label(),
        options = targets,
        run = function(val)
            local path, numbers, orientation = job.path, job.numbers, job.orientation
            local fresh = dest_of[val] and M.job("printer", dest_of[val], range) or M.job("pdf", path, range)
            fresh.path, fresh.numbers, fresh.orientation = path, numbers, orientation
            job = fresh
            row.colors.value = colors_label(job.colors)
            row.paper.value = job.paper
            row.copies.value = job.copies
            row.duplex.value = duplex_label(job.duplex)
        end,
    }
    rows[#rows + 1] = row.target
    if range then
        rows[#rows + 1] = {
            type = "select",
            name = "range",
            label = "Lines",
            value = ("%d–%d"):format(range[1], range[2]),
            options = { ("%d–%d"):format(range[1], range[2]), "Whole buffer" },
            run = function(val)
                whole = val == "Whole buffer"
            end,
        }
    end
    rows[#rows + 1] = { type = "spacer_line" }
    row.colors = {
        type = "select",
        name = "colors",
        label = "Colours",
        value = colors_label(job.colors),
        options = { "Black on white", "Theme colours" },
        run = function(val)
            job.colors = val == "Theme colours" and "theme" or "mono"
        end,
    }
    rows[#rows + 1] = row.colors
    rows[#rows + 1] = {
        type = "bool",
        name = "numbers",
        label = "Line numbers",
        value = job.numbers,
        run = function(val)
            job.numbers = val
        end,
    }
    row.paper = {
        type = "select",
        name = "paper",
        label = "Paper",
        value = job.paper,
        options = vim.tbl_contains(PAPERS, job.paper) and PAPERS or vim.list_extend({ job.paper }, PAPERS),
        run = function(val)
            job.paper = val
        end,
    }
    rows[#rows + 1] = row.paper
    rows[#rows + 1] = {
        type = "select",
        name = "orientation",
        label = "Orientation",
        value = job.orientation == "landscape" and "Landscape" or "Portrait",
        options = { "Portrait", "Landscape" },
        run = function(val)
            job.orientation = val == "Landscape" and "landscape" or "portrait"
        end,
    }
    rows[#rows + 1] = { type = "spacer_line" }
    row.copies = {
        type = "int",
        name = "copies",
        label = "Copies",
        value = job.copies,
        disabled = is_pdf,
        run = function(val)
            job.copies = math.max(1, math.floor(tonumber(val) or 1))
        end,
    }
    rows[#rows + 1] = row.copies
    row.duplex = {
        type = "select",
        name = "duplex",
        label = "Two-sided",
        value = duplex_label(job.duplex),
        options = DUPLEX_LABELS,
        disabled = is_pdf,
        run = function(val)
            job.duplex = DUPLEX_VALUES[val] -- nil for "Printer default"
        end,
    }
    rows[#rows + 1] = row.duplex
    rows[#rows + 1] = {
        type = "string",
        name = "path",
        label = "PDF file",
        value = job.path,
        disabled = function()
            return not is_pdf()
        end,
        run = function(val)
            job.path = val
        end,
    }
    rows[#rows + 1] = { type = "spacer_line" }
    rows[#rows + 1] = {
        type = "action",
        label = "Print",
        run = function(_, close)
            if is_pdf() and (not job.path or job.path == "") then
                notify("no PDF file given", vim.log.levels.WARN)
                return
            end
            local final = vim.deepcopy(job)
            if whole then
                final.range = nil
            end
            close(true, nil)
            vim.schedule(function()
                M.run(final)
            end)
        end,
    }
    rows[#rows + 1] = {
        type = "action",
        label = "Cancel",
        run = function(_, close)
            close(false, nil)
        end,
    }

    local lines = range and (range[2] - range[1] + 1) or vim.api.nvim_buf_line_count(0)
    local handle = ui.tabs({
        title = "Print",
        title_pos = "center",
        -- A popup fits what it says, on both axes (see the quit dialog for why both are given).
        width = { auto = true, max = 0.8 },
        height = { auto = true, max = 0.8 },
        footer_fill = false,
        subtitle = {
            text = ("%s · %d line%s"):format(title_of(nil), lines, lines == 1 and "" or "s"),
            blank_below = true,
        },
        close_keys = { "<Esc>", "q" },
        tabs = { { label = "Print", rows = rows } },
        callback = function() end,
    })

    -- The full, current list: printers plugged in or stopped since the last look, and on the very
    -- first open every queue besides the default.
    M.refresh_printers(function(list)
        if not (handle and handle.valid and handle.valid()) then
            return
        end
        row.target.options = target_labels(list)
        row.target.value = target_label()
        handle.render()
    end)
end

-- ─── the command ───────────────────────────────────────────────────────────────

--- The :LvimPrint command: `:LvimPrint` (the dialog), `:LvimPrint pdf [file]`, `:LvimPrint printer
--- [dest]`, each with an optional range (`:'<,'>LvimPrint …` prints the selected lines).
---@param cmd table  the user-command callback table
function M.command(cmd)
    local range = cmd.range > 0 and { cmd.line1, cmd.line2 } or nil
    local sub, arg = cmd.fargs[1], cmd.fargs[2]
    if not sub then
        M.open(range)
    elseif sub == "pdf" then
        if arg then
            M.to_pdf(arg, range)
        else
            M.ask_pdf(range)
        end
    elseif sub == "printer" then
        M.to_printer(arg, range)
    else
        notify("unknown :LvimPrint subcommand '" .. sub .. "' (pdf | printer)", vim.log.levels.WARN)
    end
end

--- Completion: the subcommand, then a file for `pdf` or a printer for `printer`.
---@param arglead string
---@param line string
---@return string[]
function M.complete(arglead, line)
    local rest = line:gsub("^%S*%s*", "", 1)
    local words = vim.tbl_filter(function(w)
        return w ~= ""
    end, vim.split(rest, "%s+"))
    local done = #words - (arglead ~= "" and 1 or 0)
    local pick = function(list)
        return vim.tbl_filter(function(c)
            return c:find(arglead, 1, true) == 1
        end, list)
    end
    if done <= 0 then
        return pick({ "pdf", "printer" })
    elseif done == 1 and words[1] == "pdf" then
        return vim.fn.getcompletion(arglead, "file")
    elseif done == 1 and words[1] == "printer" then
        return pick((M.printers()))
    end
    return {}
end

return M
