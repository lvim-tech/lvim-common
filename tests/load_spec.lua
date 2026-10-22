-- Every module of the bundle loads on its own. The modules are reachable individually
-- (`require("lvim-common.gx")`, `.quit`, `.colorcolumn`), so one that only loads as a side effect
-- of the aggregate is a break waiting for the first caller that reaches for it directly.

local root = PLUGIN_ROOT .. "/lua/lvim-common"

---@return string[]
local function modules()
    local out = {}
    local function walk(dir, prefix)
        for name, kind in vim.fs.dir(dir) do
            if kind == "directory" then
                walk(dir .. "/" .. name, prefix .. name .. ".")
            elseif name:match("%.lua$") then
                local stem = name:sub(1, -5)
                out[#out + 1] = stem == "init" and prefix:sub(1, -2) or (prefix .. stem)
            end
        end
    end
    walk(root, "lvim-common.")
    table.sort(out)
    return out
end

describe("lvim-common: every module loads")

local mods = modules()

it("there are modules to load at all", function()
    truthy(#mods > 5, "found only " .. #mods)
end)

for _, mod in ipairs(mods) do
    it(mod, function()
        local ok, err = pcall(require, mod)
        truthy(ok, tostring(err))
    end)
end
