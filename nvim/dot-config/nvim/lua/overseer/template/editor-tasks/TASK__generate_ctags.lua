local utils = require("serranomorante.utils")
local task_name = "editor-tasks-refresh-ctags"

---@type overseer.TemplateDefinition
return {
  name = task_name,
  desc = "Refresh ctags",
  builder = function()
    local command = {
      "ctags",
      "--recurse",
      "--exclude=.git",
      "--exclude=node_modules",
    }
    return {
      name = task_name,
      cmd = { "tmux" },
      args = utils.wrap_overseer_args_with_tmux(command, { session_name = task_name }),
      components = {
        {
          "restart_on_save",
          paths = { vim.fn.getcwd() },
        },
        "defaults_without_notification",
      },
    }
  end,
  tags = { "editor-tasks" },
}
