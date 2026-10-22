-- lvim-common.lua_table: sort a Lua table's bracket-key lines alphabetically.
--
-- For the tables that are really registries — `["owner/plugin"] = { … }`, a filetype map, an icon
-- set — where the reader wants to FIND an entry rather than read the file top to bottom.
--
-- Each contiguous RUN of `["…"]` lines is sorted WITHIN ITSELF and written back over the same
-- lines: nothing crosses a line that is not an entry, so the `local M = {` that opens the table,
-- the closing brace, a comment and a blank line all stay exactly where they are. (The first
-- version collected every matching line in the whole buffer, sorted them, and wrote them at the
-- TOP — which hoisted the entries above the table's own opening line and left broken Lua behind.)
--
---@module "lvim-common.lua_table"

local M = {}

--- Is this line one of the table's bracket-key entries?
---@param line string
---@return boolean
local function is_entry(line)
    return line:match('%[".*"%]') ~= nil
end

--- Sort the bracket-key lines of the current buffer in place, run by run.
--- With no arguments the whole buffer is considered; `first`/`last` (1-based, inclusive) limit it
--- to a range, which is how `:LvimLuaTable sort` passes a visual selection.
---@param first? integer
---@param last? integer
---@return nil
function M.sort(first, last)
    local total = vim.api.nvim_buf_line_count(0)
    local lo = math.max(first or 1, 1)
    local hi = math.min(last or total, total)
    if lo > hi then
        return
    end
    local lines = vim.api.nvim_buf_get_lines(0, lo - 1, hi, false)
    local i = 1
    while i <= #lines do
        if is_entry(lines[i]) then
            local last_of_run = i
            while last_of_run < #lines and is_entry(lines[last_of_run + 1]) do
                last_of_run = last_of_run + 1
            end
            if last_of_run > i then
                local run = {}
                for k = i, last_of_run do
                    run[#run + 1] = lines[k]
                end
                table.sort(run)
                for k = i, last_of_run do
                    lines[k] = run[k - i + 1]
                end
            end
            i = last_of_run + 1
        else
            i = i + 1
        end
    end
    vim.api.nvim_buf_set_lines(0, lo - 1, hi, false, lines)
end

return M
