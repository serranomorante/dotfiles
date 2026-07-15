local task_name = "editor-tasks-refresh-ctags"
local utils = require("serranomorante.utils")

---@type overseer.TemplateDefinition
return {
  name = task_name,
  desc = "Refresh ctags",
  builder = function()
    local project_root = utils.git_root_or_cwd()
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
