-- lvim-common.config: the live config for the lvim-common bundle. It currently holds the gx module's defaults
-- only — the colorcolumn and quit modules are opts-driven (configured through their own setup() / open()
-- calls, not through a shared config table). `setup()` merges the user's `gx = {…}` into `M.gx` in place;
-- gx reads `require("lvim-common.config").gx`. Field docs live on `GxConfig` in lua/lvim-common/gx.lua.
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

    -- Reveal-in-file-manager adapters: each toggles the built-in "reveal this path in your file manager"
    -- support for one file manager, and activates only if that manager is actually present. Register your own
    -- with `extra_adapters`.
    adapters = {
        neo_tree = true,
        nvim_tree = true,
        oil = true,
        mini_files = true,
        netrw = true,
    },

    extra_adapters = {},
}

return M
