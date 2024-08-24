local constants = require("serranomorante.constants")

return {
  name = "editor-tasks: restart eslint_d",
  builder = function()
    return {
      cmd = { "eslint_d" },
      args = {
        "restart",
      },
      components = { "default" },
    }
  end,
  condition = {
    callback = function(search)
      if not vim.list_contains(constants.javascript_aliases, search.filetype) then return false end
      return vim.fn.executable("eslint_d") == 1
    end,
  },
  tags = { "editor-tasks" },
}
