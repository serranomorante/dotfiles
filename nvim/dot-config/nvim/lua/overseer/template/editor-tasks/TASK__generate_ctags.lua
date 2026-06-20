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
        "--exclude=.mypy_cache",
        "--exclude=**/dist/**",
        "--exclude=**/assets/**",
        "--exclude=**/public/**",
        "--exclude=**/js/**",
        "--exclude=*.min.js",
        "--exclude=*.esm.js",
        "--exclude=*.bundle.js",
      },
      metadata = {
        hide_from_task_list = true,
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
