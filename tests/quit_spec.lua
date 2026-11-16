-- lvim-common.quit: the dialog lists exactly the buffers `:qa` refuses over.

local quit = require("lvim-common.quit")

--- A scratch buffer of `buftype`, modified.
---@param buftype string
---@return integer
local function dirty(buftype)
    local b = vim.api.nvim_create_buf(true, false)
    vim.bo[b].buftype = buftype
    vim.api.nvim_buf_set_lines(b, 0, -1, false, { "changed" })
    vim.bo[b].modified = true
    return b
end

describe("lvim-common.quit: what counts as unsaved")

it("a plain, an acwrite and a help buffer count; nofile, nowrite, terminal, prompt do not", function()
    eq(true, quit.is_unsaved(dirty("")))
    eq(true, quit.is_unsaved(dirty("acwrite")), "an acwrite buffer blocks :qa (E37)")
    eq(false, quit.is_unsaved(dirty("nofile")))
    eq(false, quit.is_unsaved(dirty("nowrite")))
    local clean = vim.api.nvim_create_buf(true, false)
    eq(false, quit.is_unsaved(clean))
end)

it("a refused :qa is reported, not thrown", function()
    dirty("acwrite")
    local seen
    local notify = vim.notify
    vim.notify = function(msg)
        seen = msg
    end
    local ok, err = pcall(quit.quit_all, false)
    vim.notify = notify
    truthy(ok, tostring(err))
    truthy(seen and seen:find("E37", 1, true), "expected an E37 notice, got " .. tostring(seen))
end)
