-- lvim-common: a bundle of small editor quality-of-life modules from the lvim-tech set:
--   colorcolumn — keeps 'colorcolumn' meaningful under 'wrap' (drops entries that would otherwise wrap to a
--                 stray cell on a continuation row), with a per-filetype/buffer exclusion list;
--   gx          — "open under cursor": URLs / local files / directories opened via the system opener or a
--                 reveal-in-file-manager adapter (:GxOpen, or map `gx`);
--   quit        — a quit dialog that lets you choose which unsaved buffers to save before quitting.
--
-- Each module is independent and reachable through the aggregate (`require("lvim-common").gx`, `.quit`,
-- `.colorcolumn`). setup() merges the `colorcolumn` / `gx` opts and activates those two; the quit dialog is
-- opened on demand (`require("lvim-common").quit.open()`), so it has no setup step.
--
---@module "lvim-common"

local M = {}

M.config = require("lvim-common.config")
M.colorcolumn = require("lvim-common.colorcolumn")
M.gx = require("lvim-common.gx")
M.quit = require("lvim-common.quit")

---@class LvimCommonOpts
---@field colorcolumn? table    colorcolumn opts (enabled / exclude_ft)
---@field gx? GxConfig|false     gx opts (merged into lvim-common.config.gx); false / nil = leave gx inactive

--- Activate the opt-in modules. `colorcolumn` is set up only when its opts are given; `gx` is set up when its
--- opts are given (pass `gx = {}` to activate it with defaults). The quit dialog needs no setup.
---@param opts? LvimCommonOpts
function M.setup(opts)
    opts = opts or {}
    if opts.colorcolumn then
        M.colorcolumn.setup(opts.colorcolumn)
    end
    if opts.gx then
        M.gx.setup(opts.gx)
    end
end

return M
