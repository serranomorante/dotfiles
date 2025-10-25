local constants = require("serranomorante.constants")

---@type vim.lsp.Config
return {
  cmd = { constants.BINARIES.vscode_html_language_server(), "--stdio" },
  filetypes = constants.html_aliases,
}
