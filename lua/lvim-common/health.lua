-- lvim-common.health: `:checkhealth lvim-common` — reports that the three bundled modules load, their deps
-- (lvim-utils base; lvim-ui for the quit dialog) are present, and which pieces are active (the gx commands).
--
---@module "lvim-common.health"

local M = {}

local health = vim.health
local start = health.start or health.report_start
local ok = health.ok or health.report_ok
local info = health.info or health.report_info
local err = health.error or health.report_error

---@param mod string
---@return boolean
local function has(mod)
    return (pcall(require, mod))
end

function M.check()
    start("lvim-common")

    if vim.fn.has("nvim-0.12") == 1 then
        ok("Neovim >= 0.12")
    else
        err("Neovim >= 0.12 required")
    end
    if has("lvim-utils.utils") then
        ok("lvim-utils (base) is available")
    else
        err("lvim-utils not found — lvim-common's gx module requires it")
    end
    if has("lvim-ui") then
        ok("lvim-ui is available (the quit dialog builds on it)")
    else
        err("lvim-ui not found — the quit dialog requires it")
    end

    -- Modules load.
    for _, mod in ipairs({ "colorcolumn", "gx", "quit" }) do
        if has("lvim-common." .. mod) then
            ok(mod .. " module loaded")
        else
            err(mod .. " module failed to load")
        end
    end

    -- gx state.
    start("lvim-common · gx")
    if vim.fn.exists(":GxOpen") == 2 then
        ok(":GxOpen registered (gx is active)")
    else
        info(":GxOpen not registered — gx inactive (activate with setup({ gx = {} }))")
    end
end

return M
