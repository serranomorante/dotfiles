local task_name = "editor-tasks-refresh-ctags"

---@type overseer.TemplateDefinition
return {
  name = task_name,
  desc = "Refresh ctags",
  builder = function()
    return {
      name = task_name,
      cmd = { "ctags" },
      args = {
        "--recurse",
        "--exclude=.git",
        "--exclude=node_modules",
      },
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
