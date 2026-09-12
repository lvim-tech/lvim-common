-- lvim-common.path: a file's name as a person reads it — its project and the path inside it.
-- Shared by the quit dialog (a label per unsaved buffer) and the printer (the running header on
-- every page), so a file is called the same thing wherever lvim-common names it.
--
---@module "lvim-common.path"

local M = {}

-- Project-root markers, checked upward from the file (git first); the path is taken RELATIVE to the nearest.
M.ROOT_MARKERS = {
    ".git",
    ".hg",
    ".svn",
    "package.json",
    "Cargo.toml",
    "go.mod",
    "pyproject.toml",
    "stylua.toml",
    "Makefile",
}

--- `<project>/<path-from-root>` for a file inside a project, else the home- or cwd-relative path
--- (`:~:.`). Not elided — a caller that has a width to fit shortens it itself.
---@param name string  an absolute file name (non-empty)
---@return string
function M.in_project(name)
    local root = vim.fs.root(name, M.ROOT_MARKERS)
    if root and root ~= "" and (name == root or vim.startswith(name, root .. "/")) then
        return vim.fn.fnamemodify(root, ":t") .. "/" .. name:sub(#root + 2)
    end
    return vim.fn.fnamemodify(name, ":~:.")
end

return M
