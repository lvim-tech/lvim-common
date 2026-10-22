-- Sorting a Lua table's entries must not rewrite the file around them.
--
-- The first version collected every `["…"]` line in the WHOLE buffer, sorted them, and wrote them
-- at the top — so on any real file the entries were hoisted above the `local M = {` that opens the
-- table, and what was left was broken Lua. Each contiguous RUN of entry lines is now sorted within
-- itself, in place, and nothing crosses a line that is not an entry.

local lua_table = require("lvim-common.lua_table")

--- Put `lines` in a scratch buffer, make it current, run `fn`, and return the buffer's lines.
---@param lines string[]
---@param fn fun()
---@return string[]
local function on_buffer(lines, fn)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_set_current_buf(buf)
    fn()
    local out = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    vim.api.nvim_buf_delete(buf, { force = true })
    return out
end

describe("lvim-common.lua_table.sort")

it("sorts the entries where they are and leaves the code around them", function()
    local out = on_buffer({
        "local M = {}",
        "",
        "M.map = {",
        '    ["b/two"] = 2,',
        '    ["a/one"] = 1,',
        '    ["c/three"] = 3,',
        "}",
        "",
        "return M",
    }, function()
        lua_table.sort()
    end)
    eq({
        "local M = {}",
        "",
        "M.map = {",
        '    ["a/one"] = 1,',
        '    ["b/two"] = 2,',
        '    ["c/three"] = 3,',
        "}",
        "",
        "return M",
    }, out)
end)

it("sorts each run on its own", function()
    local out = on_buffer({
        "M.first = {",
        '    ["z"] = 1,',
        '    ["y"] = 2,',
        "}",
        "M.second = {",
        '    ["b"] = 3,',
        '    ["a"] = 4,',
        "}",
    }, function()
        lua_table.sort()
    end)
    eq({
        "M.first = {",
        '    ["y"] = 2,',
        '    ["z"] = 1,',
        "}",
        "M.second = {",
        '    ["a"] = 4,',
        '    ["b"] = 3,',
        "}",
    }, out)
end)

it("never moves an entry past a line that is not one", function()
    local out = on_buffer({
        '    ["b"] = 1,',
        "    -- a comment between them",
        '    ["a"] = 2,',
    }, function()
        lua_table.sort()
    end)
    eq({
        '    ["b"] = 1,',
        "    -- a comment between them",
        '    ["a"] = 2,',
    }, out, "two runs of one line each: nothing to reorder")
end)

it("sorts only the given range", function()
    local out = on_buffer({
        '["b"] = 1,',
        '["a"] = 2,',
        '["d"] = 3,',
        '["c"] = 4,',
    }, function()
        lua_table.sort(3, 4)
    end)
    eq({ '["b"] = 1,', '["a"] = 2,', '["c"] = 4,', '["d"] = 3,' }, out)
end)

it("leaves a buffer with no entries alone", function()
    local lines = { "local M = {}", "return M" }
    eq(lines, on_buffer(lines, function()
        lua_table.sort()
    end))
end)
