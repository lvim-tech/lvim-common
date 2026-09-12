# lvim-common

A small bundle of editor quality-of-life modules from the **lvim-tech** set — independent pieces under
one plugin:

- **colorcolumn** — keeps `'colorcolumn'` meaningful under `'wrap'`: it drops any colorcolumn entry that would
  otherwise wrap to a stray cell on a continuation row, with a per-filetype exclusion list for side panels.
- **gx** — "open under cursor": URLs, local files and directories under the cursor are opened via the system
  opener (or revealed in your file manager). `:GxOpen` / `:GxOpenDiag`, or map `gx`. Built-in file-manager
  adapters resolve the real path of the entry under the cursor (neo-tree, nvim-tree, oil, mini.files, netrw);
  the suite's own tree, **lvim-files**, self-registers its adapter from its own `setup()` via
  `require("lvim-common.gx").register_adapter(...)`, so no wiring is needed on either side.
- **quit** — a quit dialog that lists the unsaved buffers as toggle rows so you can choose which to save before
  quitting (or quit immediately when nothing is dirty).
- **comments** — strip every comment from the buffer, judged by the **grammar** rather than a regex, so a `#`
  inside a string or a URL in a `//` link is never mistaken for one. Whole-line comments take their line;
  inline ones are excised in place. `:LvimComments strip`.
- **lua_table** — sort a Lua table's `["key"]` lines alphabetically, for the tables that are really registries
  and are read by lookup rather than top to bottom. `:LvimLuaTable sort`.
- **eval** — run an Ex command (`:version`) or a Lua expression (`1+1`) and show what it produced in the shared
  read-only viewer. `print` output during the call is captured too. `:LvimEval`.
- **print** — print the buffer, or a range of it, to a printer or to a PDF — what `:hardcopy` did before
  Neovim 0.9 removed it. `:LvimPrint` opens a dialog in the middle of the screen: the target (a PDF or any
  CUPS printer), the lines, colours, line numbers, paper, orientation, copies and two-sided printing — each
  printer starting from its own settings. The page is the editor's own rendering (Neovim's bundled `tohtml`:
  the colorscheme, treesitter and syntax highlighting), always with ABSOLUTE line numbers and every fold open,
  whatever `'relativenumber'` / `'statuscolumn'` your window uses; a headless Chromium lays it out, with the
  file's path in its project (`lvim-common/lua/lvim-common/print.lua`) on every page and a page counter.

## Requirements

Requires **Neovim >= 0.12.x**, [lvim-utils](https://github.com/lvim-tech/lvim-utils) (base — gx uses it) and
[lvim-ui](https://github.com/lvim-tech/lvim-ui) (the quit dialog builds on its float toolkit).

`:LvimPrint` also needs a Chromium-family browser (chromium, google-chrome, brave or edge — Firefox has no
command-line print-to-PDF) and, for paper, CUPS (`lp`). `:checkhealth lvim-common` reports each link.

## Installation

### lvim-installer (recommended)

```vim
:LvimInstaller plugins
```

### Native (vim.pack)

```lua
vim.pack.add({
    { src = "https://github.com/lvim-tech/lvim-utils" },
    { src = "https://github.com/lvim-tech/lvim-ui" },
    { src = "https://github.com/lvim-tech/lvim-common" },
})
require("lvim-common").setup({ colorcolumn = { enabled = true }, gx = {} })
```

## Usage

`setup()` activates the opt-in modules: `colorcolumn` (when its opts are given) and `gx` (pass `gx = {}` to
activate it with defaults). The quit dialog needs no setup — open it on demand.

```vim
:GxOpen        " open the URL / file / directory under the cursor
:GxOpenDiag    " open with diagnostics about what was detected
:LvimQuit      " the quit dialog
:LvimComments  " strip every comment from the buffer (`strip` is the default subcommand)
:LvimLuaTable  " sort the buffer's Lua bracket-key lines (`sort`)
:LvimEval      " run an Ex command or Lua expression, show the output
:LvimPrint                 " the print dialog (target, lines, colours, paper, copies, two-sided)
:LvimPrint pdf [file]      " straight to a PDF — without a file, asks (default: the buffer's name, .pdf)
:LvimPrint printer [dest]  " straight to a printer, with its settings — without a destination, the default
:'<,'>LvimPrint …          " any of them, for the selected lines only
```

```lua
local common = require("lvim-common")
common.gx.map_default() -- bind `gx` in normal mode to :GxOpen
common.gx.open_current() -- trigger GxOpen at the cursor programmatically
common.quit.open() -- open the quit dialog (quits immediately if nothing is unsaved)
common.quit.open({ confirm = false }) -- skip the dialog, force :qa!
common.print.open() -- the print dialog
common.print.to_pdf("~/out.pdf") -- the current buffer to a PDF
common.print.to_printer(nil, { 10, 40 }) -- lines 10-40 to the default printer, with its settings
```

## Configuration

`setup()` merges your options in place. The `gx` and `print` opts merge into the live
`lvim-common.config.gx` / `.print`; the `colorcolumn` opts are read directly by its setup. The full default
config:

```lua
require("lvim-common").setup({
    -- colorcolumn — activated only when this key is present.
    colorcolumn = {
        enabled = true, -- master toggle
        exclude_ft = {}, -- filetypes whose windows are forced to no colorcolumn (side panels)
    },

    -- gx — activated only when this key is present (pass `gx = {}` for defaults).
    gx = {
        map = true, -- bind `gx` (normal mode) to :GxOpen on setup; false = command only, no keymap
        highlight_match = true, -- flash the matched token when opening
        highlight_duration_ms = 300,
        system_open_cmd = nil, -- nil = auto-detect (xdg-open / open / start)
        force_system_open_local = true, -- use the system opener for local files too
        allow_bare_domains = true, -- treat "domain.tld/path" as an HTTPS URL
        icon_guard = true, -- skip tokens that look like Nerd Font glyphs
        dir_open_strategy = "system", -- "system" | "edit"
        search_forward_if_none = true, -- scan forward for a token when none is under the cursor
        search_backward_if_none = true, -- and backward
        search_max_lines = 60, -- proximity scan bound
        max_sequential_candidates = 200,
        pattern = "[%w%._~/#%-%+%%%?=&@:%d]+", -- the token pattern
        -- File-manager adapters: each resolves the real path of the entry under the cursor in that
        -- manager's buffer, and activates only if that manager is actually present.
        adapters = {
            neo_tree = true,
            nvim_tree = true,
            oil = true,
            mini_files = true,
            netrw = true, -- Neovim's built-in file explorer
        },
        -- Register your own file-manager adapter: a flat def
        -- `{ name = "id", detect = function(ctx) … end, get = function(ctx) return { path, type } end }`.
        extra_adapters = {},
    },

    -- print — :LvimPrint is registered either way; these are its defaults.
    print = {
        browser = nil, -- nil = the first Chromium-family browser on $PATH; a name or a list to choose
        printer = nil, -- the dialog's initial printer; nil = the CUPS default destination (`lpstat -d`)
        number_lines = true, -- always ABSOLUTE numbers, whatever 'relativenumber' / 'statuscolumn' say
        font_size = "9pt",
        header = true, -- the file's path in its project on top of each page, "page / pages" at the bottom
        page = {
            size = "A4", -- "A4" | "A5" | "A3" | "Letter" | "Legal"
            orientation = "portrait", -- "portrait" | "landscape"
            margin = "14mm 12mm",
        },
        pdf = {
            colors = "theme", -- "theme": the colorscheme, background included | "mono": black on white
        },
        -- Per CUPS destination (as `lpstat -e` names it); ["*"] is the base every printer starts from.
        -- These are the dialog's starting values, and what `:LvimPrint printer` uses as is.
        printers = {
            ["*"] = {
                colors = "mono", -- a dark background from a laser printer is a page of toner
                copies = 1,
                -- duplex = "long", -- unset = the printer's default | false = one-sided | "long" | "short"
                -- paper = "A4", -- unset = page.size; sent as `lp -o media=`
                options = {}, -- raw CUPS options: { KCEcoprint = "On" } → `lp -o KCEcoprint=On`
            },
            -- ["ECOSYS-P2135dn"] = { duplex = "long", options = { KCEcoprint = "On" } },
        },
    },
})
```

The quit dialog is not configured through `setup()` — pass its options per call:
`require("lvim-common").quit.open({ confirm = false })`.

## License

BSD-3-Clause.
