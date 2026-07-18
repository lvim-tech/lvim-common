# lvim-common

A small bundle of editor quality-of-life modules from the **lvim-tech** set — three independent pieces under
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

## Requirements

Requires **Neovim >= 0.12.x**, [lvim-utils](https://github.com/lvim-tech/lvim-utils) (base — gx uses it) and
[lvim-ui](https://github.com/lvim-tech/lvim-ui) (the quit dialog builds on its float toolkit).

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
```

```lua
local common = require("lvim-common")
common.gx.map_default() -- bind `gx` in normal mode to :GxOpen
common.gx.open_current() -- trigger GxOpen at the cursor programmatically
common.quit.open() -- open the quit dialog (quits immediately if nothing is unsaved)
common.quit.open({ confirm = false }) -- skip the dialog, force :qa!
```

## Configuration

`setup()` merges your options in place. The `gx` opts merge into the live `lvim-common.config.gx`; the
`colorcolumn` opts are read directly by its setup. The full default config:

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
})
```

The quit dialog is not configured through `setup()` — pass its options per call:
`require("lvim-common").quit.open({ confirm = false })`.

## License

BSD-3-Clause.
