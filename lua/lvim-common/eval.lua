-- lvim-common.eval: run an Ex command or a Lua expression and show what it produced.
--
-- `:` first means an Ex command, captured with `nvim_exec2`; anything else is Lua, tried first as
-- an EXPRESSION (`return <text>`, so `1+1` answers `2`) and then as a statement. `print` is
-- captured during the call, so a snippet that prints instead of returning still shows its output.
--
-- The result opens in the shared read-only viewer (`lvim-ui.info`), which is why this lives in a
-- plugin and not in a host config: the window, its border title and its `q close` footer are the
-- same ones every other panel in the set uses.
--
---@module "lvim-common.eval"

local M = {}

function M.open()
    vim.ui.input({
        prompt = "Enter command or Lua code: ",
        default = "",
    }, function(input)
        if not input or input == "" then
            return
        end
        local output
        local success = true
        local is_command = input:match("^:")
        if is_command then
            -- Execute as a Vim Ex command and capture its output
            output = vim.api.nvim_exec2(input, { output = true }).output
        else
            -- Try "return <expr>" first so bare expressions like "1+1" work
            local func, load_err = load("return " .. input)
            if not func then
                func, load_err = load(input)
                if not func then
                    output = "Error loading Lua code: " .. tostring(load_err)
                    success = false
                end
            end
            if func then
                -- Temporarily replace the global print to capture its output
                local original_print = print
                local print_output = {}
                _G.print = function(...)
                    local args = { ... }
                    local str_args = {}
                    for i, v in ipairs(args) do
                        str_args[i] = tostring(v)
                    end
                    table.insert(print_output, table.concat(str_args, "\t"))
                end
                local results = { pcall(func) }
                _G.print = original_print
                if not results[1] then
                    output = "Lua execution error: " .. tostring(results[2])
                    success = false
                else
                    table.remove(results, 1)
                    local return_values = {}
                    for i, v in ipairs(results) do
                        return_values[i] = vim.inspect(v)
                    end
                    local return_output = #return_values > 0 and "Return values:\n" .. table.concat(return_values, "\n")
                        or ""
                    local print_content = #print_output > 0 and "Printed output:\n" .. table.concat(print_output, "\n")
                        or ""
                    if #return_output > 0 and #print_content > 0 then
                        output = print_content .. "\n\n" .. return_output
                    else
                        output = print_content .. return_output
                    end
                end
            end
        end
        if output == "" then
            vim.notify("No output from " .. (is_command and "command" or "Lua code"), vim.log.levels.INFO)
            return
        end
        -- THE CANONICAL VIEWER, not a hand-rolled float: `lvim-ui.info` is the shared read-only
        -- panel (frame + border title + `q close` footer + scrolling), so this output looks and
        -- behaves like every other panel in the editor instead of being a second, unthemed
        -- implementation of the same window with its own keymaps and sizing math.
        require("lvim-ui").info(output, {
            title = (success and "Output: " or "Error: ") .. input,
            wrap = true,
        })
    end)
end

return M
