local constants = require("serranomorante.constants")

return {
  name = "Restart eslint_d",
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
      if not vim.list_contains(constants.javascript_filetypes, search.filetype) then return false end
      local mason_registry = require("mason-registry")
      local eslint_d_exists = mason_registry.get_package("eslint_d")
      return eslint_d_exists
    end,
  },
  tags = { "editor" },
}
