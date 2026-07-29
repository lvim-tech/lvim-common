-- lvim-common.lua_table: sort a Lua table's bracket-key lines alphabetically.
--
-- For the tables that are really registries — `["owner/plugin"] = { … }`, a filetype map, an icon
-- set — where the reader wants to FIND an entry rather than read the file top to bottom. Lines
-- matching `["…"]` are sorted and moved to the top; everything else keeps its order below them.
--
---@module "lvim-common.lua_table"

local M = {}

function M.sort()
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local sorted_lines = {}
    local inner_lines = {}
    for _, line in ipairs(lines) do
        if line:match('%[".*"%]') then
            table.insert(sorted_lines, line)
        else
            table.insert(inner_lines, line)
        end
    end
    table.sort(sorted_lines)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, sorted_lines)
    vim.api.nvim_buf_set_lines(0, #sorted_lines, -1, false, inner_lines)
end

return M
