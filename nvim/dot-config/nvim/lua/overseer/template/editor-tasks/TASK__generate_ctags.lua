local utils = require("serranomorante.utils")

local task_name = "editor-tasks-refresh-ctags"

---@type overseer.TemplateDefinition
return {
  name = task_name,
  desc = "Refresh ctags",
  builder = function()
    local session_name = task_name .. vim.fn.fnameescape(vim.v.servername)
    return {
      cmd = { "tmux" },
      args = utils.wrap_overseer_args_with_tmux({
        "ctags",
        "--recurse",
        "--exclude=.git",
        "--exclude=node_modules",
      }, session_name),
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
