-- lvim-common.health: `:checkhealth lvim-common` — reports that the bundled modules load, their deps
-- (lvim-utils base; lvim-ui for the quit dialog) are present, which pieces are active (the gx commands), and
-- whether the print chain (tohtml → a Chromium-family browser → CUPS `lp`) is complete.
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
    for _, mod in ipairs({ "colorcolumn", "gx", "quit", "print" }) do
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

    -- print: each link of buffer → tohtml → browser → PDF → lp → printer.
    health.start("lvim-common · print")
    local print_ok, print_mod = pcall(require, "lvim-common.print")
    if not print_ok then
        return
    end
    pcall(vim.cmd.packadd, "nvim.tohtml")
    if has("tohtml") then
        health.ok("tohtml is available (renders the buffer to HTML)")
    else
        health.error("tohtml not found — it ships with Neovim as the optional package nvim.tohtml")
    end
    local exe, tried = print_mod.browser()
    if exe then
        health.ok("PDF renderer: " .. exe)
    else
        health.error(
            "no Chromium-family browser found (tried: " .. table.concat(tried, ", ") .. ")",
            { "install chromium or google-chrome, or set print.browser to the one you have" }
        )
    end
    if vim.fn.executable("lp") == 1 then
        local names, default, disabled = print_mod.printers()
        if #names == 0 then
            health.warn("CUPS has no printer that accepts jobs — :LvimPrint pdf still works")
        else
            local cfg = require("lvim-common.config").print
            health.ok(("printers: %s (default: %s)"):format(table.concat(names, ", "), default or "none"))
            if cfg.printer and not vim.tbl_contains(names, cfg.printer) then
                health.warn("print.printer = " .. cfg.printer .. " is not one of the accepting printers")
            end
            for _, name in ipairs(names) do
                if disabled[name] then
                    health.warn(
                        "the CUPS queue of " .. name .. " is stopped — jobs wait in it",
                        {
                            "a job that met the printer asleep or unplugged paused it; the printer itself may be fine",
                            "`cupsenable " .. name .. "` resumes it (the waiting jobs print right away)",
                            "`lpadmin -p " .. name .. " -o printer-error-policy=retry-job` retries instead of stopping",
                        }
                    )
                end
            end
            -- A settings entry under a name CUPS does not know is never used — usually a typo.
            for name in pairs(cfg.printers or {}) do
                if name ~= "*" and not vim.tbl_contains(names, name) then
                    health.warn("print.printers[" .. vim.inspect(name) .. "] matches no accepting printer")
                end
            end
        end
    else
        health.warn("`lp` not found — printing needs CUPS; :LvimPrint pdf still works")
    end
end

return M
