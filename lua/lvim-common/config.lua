-- lvim-common.config: the live config for the lvim-common bundle. It holds the defaults of the gx and print
-- modules — the colorcolumn and quit modules are opts-driven (configured through their own setup() / open()
-- calls, not through a shared config table). `setup()` merges the user's `gx = {…}` / `print = {…}` into
-- `M.gx` / `M.print` in place, and each module reads its table live. Field docs live on `GxConfig` in
-- lua/lvim-common/gx.lua and `LvimPrintConfig` in lua/lvim-common/print.lua.
--
---@module "lvim-common.config"

local M = {}

---@type GxConfig
M.gx = {
    map = true, -- bind `gx` (normal mode) to :GxOpen on setup; false = register only the command, no keymap
    highlight_match = true,
    highlight_duration_ms = 300,
    system_open_cmd = nil, -- nil = auto-detect (xdg-open / open / start)
    force_system_open_local = true, -- use system opener for local files too
    allow_bare_domains = true, -- treat "domain.tld/path" as HTTPS URLs
    icon_guard = true, -- skip tokens that look like Nerd Font glyphs
    dir_open_strategy = "system", -- "system" | "edit"
    search_forward_if_none = true,
    search_backward_if_none = true,
    search_max_lines = 60,
    max_sequential_candidates = 200,
    pattern = "[%w%._~/#%-%+%%%?=&@:%d]+",

    -- File-manager adapters: each teaches gx to read the ENTRY UNDER THE CURSOR from one file manager's
    -- tree/panel (so `gx` on a tree row opens that entry's real path), and activates only if that manager is
    -- actually present. Register your own with `extra_adapters`.
    adapters = {
        neo_tree = true,
        nvim_tree = true,
        oil = true,
        mini_files = true,
        netrw = true,
    },

    extra_adapters = {},
}

---@type LvimPrintConfig
M.print = {
    browser = nil, -- nil = the first Chromium-family browser on $PATH; a name or a list to choose
    printer = nil, -- the dialog's initial printer; nil = the CUPS default destination (`lpstat -d`)
    number_lines = true, -- always ABSOLUTE numbers, whatever 'relativenumber' / 'statuscolumn' the window has
    font_size = "9pt",
    header = true, -- the file's path in its project on top of each page, "page / pages" at the bottom
    page = {
        size = "A4", -- "A4" | "A5" | "A3" | "Letter" | "Legal"
        orientation = "portrait", -- "portrait" | "landscape"
        margin = "14mm 12mm",
    },
    pdf = {
        colors = "theme", -- the page looks like the screen, background included
    },
    -- Per CUPS destination. ["*"] is the base every printer starts from; an entry named after a printer
    -- (as `lpstat -e` lists it) is laid over it. These are the dialog's starting values for that printer.
    printers = {
        ["*"] = {
            colors = "mono", -- black on white: a dark background from a laser printer is a page of toner
            copies = 1,
            -- duplex: unset = the printer's own default; false = one-sided; "long" | "short" = the edge to flip on
            -- paper: unset = page.size; the sheet the printer feeds (sent as `-o media=`)
            options = {}, -- raw CUPS options, e.g. { KCEcoprint = "On" } → `lp -o KCEcoprint=On`
        },
    },
}

return M
