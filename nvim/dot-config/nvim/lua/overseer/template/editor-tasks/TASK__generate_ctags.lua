---@type overseer.TemplateDefinition
return {
  name = "editor-tasks: refresh ctags",
  desc = "Refresh ctags",
  builder = function()
    return {
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
        "default",
      },
    }
  end,
  tags = { "editor-tasks" },
}
