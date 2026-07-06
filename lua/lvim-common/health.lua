-- lvim-common.health: `:checkhealth lvim-common` — reports that the three bundled modules load, their deps
-- (lvim-utils base; lvim-ui for the quit dialog) are present, and which pieces are active (the gx commands).
--
---@module "lvim-common.health"

local M = {}

local health = vim.health

---@param mod string
---@return boolean
local function has(mod)
    return (pcall(require, mod))
end

function M.check()
    health.start("lvim-common")

    if vim.fn.has("nvim-0.12") == 1 then
        health.ok("Neovim >= 0.12")
    else
        health.error("Neovim >= 0.12 required")
    end
    if has("lvim-utils.utils") then
        health.ok("lvim-utils (base) is available")
    else
        health.error("lvim-utils not found — lvim-common's gx module requires it")
    end
    if has("lvim-ui") then
        health.ok("lvim-ui is available (the quit dialog builds on it)")
    else
        health.error("lvim-ui not found — the quit dialog requires it")
    end

    -- Modules load.
    for _, mod in ipairs({ "colorcolumn", "gx", "quit" }) do
        if has("lvim-common." .. mod) then
            health.ok(mod .. " module loaded")
        else
            health.error(mod .. " module failed to load")
        end
    end

    -- gx state.
    health.start("lvim-common · gx")
    if vim.fn.exists(":GxOpen") == 2 then
        health.ok(":GxOpen registered (gx is active)")
    else
        health.info(":GxOpen not registered — gx inactive (activate with setup({ gx = {} }))")
    end
end

return M
