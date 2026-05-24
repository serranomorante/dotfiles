local constants = require("serranomorante.constants")

if not constants.BINARIES.vue_language_server then return {} end

---@type vim.lsp.Config
return {
  cmd = { constants.BINARIES.vue_language_server(), "--stdio" },
  filetypes = { "vue" },
  root_markers = {
    "package.json",
  },
}
