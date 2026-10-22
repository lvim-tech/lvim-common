-- setup() is the only seam a host uses: it must register the commands, honour the one option that
-- changes global state (the `gx` keymap), merge what it is given, and survive being called twice.

local common = require("lvim-common")

--- Run `fn` with the global `gx` mapping restored afterwards.
---@param fn fun()
local function with_gx_map(fn)
    local saved = vim.fn.maparg("gx", "n", false, true)
    pcall(vim.keymap.del, "n", "gx")
    local ok, err = pcall(fn)
    pcall(vim.keymap.del, "n", "gx")
    if saved and saved.rhs then
        pcall(vim.keymap.set, "n", "gx", saved.rhs, { silent = true })
    end
    if not ok then
        error(err, 0)
    end
end

describe("lvim-common.setup")

it("registers its on-demand commands", function()
    common.setup({})
    for _, cmd in ipairs({ "LvimQuit", "LvimComments", "LvimLuaTable", "LvimEval", "LvimPrint" }) do
        eq(2, vim.fn.exists(":" .. cmd), ":" .. cmd .. " should exist after setup")
    end
end)

it("gives :LvimLuaTable a range, so one table in a file can be sorted on its own", function()
    common.setup({})
    local info = vim.api.nvim_get_commands({})["LvimLuaTable"]
    truthy(info, "the command is not registered")
    truthy(info.range ~= nil and info.range ~= "", "the command takes no range: " .. vim.inspect(info.range))
end)

it("binds gx by default and not when the option says no", function()
    with_gx_map(function()
        common.setup({ gx = { map = false } })
        eq("", vim.fn.maparg("gx", "n"), "map = false must leave gx alone")
        common.setup({ gx = { map = true } })
        truthy(vim.fn.maparg("gx", "n") ~= "", "map = true must bind gx")
    end)
end)

it("merges the print options into the live config", function()
    local before = vim.deepcopy(common.config.print)
    common.setup({ print = { lp_command = "lvim-test-printer" } })
    eq("lvim-test-printer", common.config.print.lp_command)
    for k, v in pairs(before) do
        if k ~= "lp_command" and type(v) ~= "table" then
            eq(v, common.config.print[k], "sibling key " .. k .. " survived")
        end
    end
end)

it("runs twice without stacking anything", function()
    with_gx_map(function()
        common.setup({})
        local commands = vim.tbl_count(vim.api.nvim_get_commands({}))
        local maps = #vim.api.nvim_get_keymap("n")
        common.setup({})
        eq(commands, vim.tbl_count(vim.api.nvim_get_commands({})), "command count")
        eq(maps, #vim.api.nvim_get_keymap("n"), "normal-mode keymap count")
    end)
end)

describe("lvim-common.path.in_project")

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp .. "/myproject/src", "p")
vim.fn.mkdir(tmp .. "/myproject/.git", "p")
vim.fn.writefile({ "" }, tmp .. "/myproject/src/main.lua")

it("names a file inside a project by <project>/<path>", function()
    eq("myproject/src/main.lua", require("lvim-common.path").in_project(tmp .. "/myproject/src/main.lua"))
end)

it("falls back to a home- or cwd-relative name outside a project", function()
    local outside = tmp .. "/loose.txt"
    vim.fn.writefile({ "" }, outside)
    local got = require("lvim-common.path").in_project(outside)
    truthy(got ~= "" and not got:match("^myproject/"), "got " .. got)
end)

describe("lvim-common: health")

it("the health check runs to completion", function()
    local health = require("lvim-common.health")
    truthy(type(health.check) == "function", "no check() to run")
    local ok, err = pcall(health.check)
    truthy(ok, tostring(err))
end)
