-- lvim-common: a bundle of small editor quality-of-life modules from the lvim-tech set:
--   colorcolumn — keeps 'colorcolumn' meaningful under 'wrap' (drops entries that would otherwise wrap to a
--                 stray cell on a continuation row), with a per-filetype/buffer exclusion list;
--   gx          — "open under cursor": URLs / local files / directories opened via the system opener or a
--                 reveal-in-file-manager adapter (:GxOpen, or map `gx`);
--   quit        — a quit dialog that lets you choose which unsaved buffers to save before quitting;
--   comments    — strip every comment from the buffer, through treesitter (:LvimComments strip);
--   lua_table   — sort a Lua table's bracket-key lines alphabetically (:LvimLuaTable sort);
--   eval        — run an Ex command or Lua expression and show the output (:LvimEval);
--   print       — print the buffer or a range of it, to a printer or to a PDF (:LvimPrint).
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
M.comments = require("lvim-common.comments")
M.lua_table = require("lvim-common.lua_table")
M.eval = require("lvim-common.eval")
M.print = require("lvim-common.print")

---@class LvimCommonOpts
---@field colorcolumn? table    colorcolumn opts (enabled / exclude_ft)
---@field gx? GxConfig|false     gx opts (merged into lvim-common.config.gx); false / nil = leave gx inactive
---@field print? LvimPrintConfig  print opts (merged into lvim-common.config.print); :LvimPrint exists either way

--- Activate the opt-in modules. `colorcolumn` is set up only when its opts are given; `gx` is set up when its
--- opts are given (pass `gx = {}` to activate it with defaults). The `:LvimQuit` command (the save-selected
--- quit dialog) is always registered here, so a consumer just calls setup and gets it — no manual command.
---@param opts? LvimCommonOpts
function M.setup(opts)
    opts = opts or {}
    if opts.colorcolumn then
        M.colorcolumn.setup(opts.colorcolumn)
    end
    if opts.gx then
        M.gx.setup(opts.gx)
    end
    if opts.print then
        require("lvim-utils.utils").merge(M.config.print, opts.print)
    end
    -- The quit dialog is opened on demand; register its command so setup() gives it (like the other plugins'
    -- :Lvim* commands). `:LvimQuit` lists the unsaved buffers to choose which to save before quitting.
    pcall(vim.api.nvim_create_user_command, "LvimQuit", function()
        M.quit.open()
    end, { desc = "lvim-common: quit dialog (choose which unsaved buffers to save before quitting)" })
    -- The on-demand editor utilities get their commands here too, for the same reason: a consumer
    -- calls setup() and has them, instead of re-declaring a command per host config.
    pcall(vim.api.nvim_create_user_command, "LvimComments", function(cmd)
        if cmd.args == "" or cmd.args == "strip" then
            M.comments.strip()
        else
            vim.notify("lvim-common: unknown :LvimComments subcommand '" .. cmd.args .. "'", vim.log.levels.WARN)
        end
    end, {
        nargs = "?",
        complete = function()
            return { "strip" }
        end,
        desc = "lvim-common: strip every comment from the buffer (treesitter)",
    })
    pcall(vim.api.nvim_create_user_command, "LvimLuaTable", function(cmd)
        if cmd.args == "" or cmd.args == "sort" then
            M.lua_table.sort()
        else
            vim.notify("lvim-common: unknown :LvimLuaTable subcommand '" .. cmd.args .. "'", vim.log.levels.WARN)
        end
    end, {
        nargs = "?",
        complete = function()
            return { "sort" }
        end,
        desc = "lvim-common: sort a Lua table's bracket-key lines",
    })
    pcall(vim.api.nvim_create_user_command, "LvimEval", function()
        M.eval.open()
    end, { desc = "lvim-common: run an Ex command or Lua expression and show the output" })
    pcall(vim.api.nvim_create_user_command, "LvimPrint", M.print.command, {
        nargs = "*",
        range = true,
        complete = M.print.complete,
        desc = "lvim-common: print the buffer (or a range) — :LvimPrint [pdf [file] | printer [dest]]",
    })
end

return M
