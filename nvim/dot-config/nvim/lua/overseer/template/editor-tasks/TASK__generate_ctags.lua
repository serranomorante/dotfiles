local task_name = "editor-tasks-refresh-ctags"
local utils = require("serranomorante.utils")

local function normalize_path(path)
  if not path or path == "" then return nil end
  return vim.fs.normalize(vim.fn.fnamemodify(path, ":p")):gsub("/$", "")
end

local function is_home_project_root(project_root) return normalize_path(project_root) == normalize_path(vim.env.HOME) end

---@type overseer.TemplateDefinition
return {
  name = task_name,
  desc = "Refresh ctags",
  is_home_project_root = is_home_project_root,
  builder = function()
    local project_root = utils.git_root_or_cwd()
    if is_home_project_root(project_root) then error("Refusing to refresh ctags with HOME as the project root") end

    local refresh_ctags_cmd = vim.env.HOME .. "/bin/dotfiles-refresh-ctags"
    if vim.fn.executable(refresh_ctags_cmd) == 0 then
      refresh_ctags_cmd = vim.env.HOME .. "/dotfiles/nvim/bin/dotfiles-refresh-ctags"
    end

    return {
      name = task_name,
      cmd = { refresh_ctags_cmd },
      cwd = project_root,
      metadata = {
        hide_from_task_list = true,
      },
      components = {
        {
          "restart_on_save",
          paths = { project_root },
        },
        "defaults_without_notification",
      },
    }
  end,
  tags = { "editor-tasks" },
}
