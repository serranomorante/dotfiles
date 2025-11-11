local constants = require("serranomorante.constants")

if not constants.BINARIES.vscode_html_language_server then return {} end

---@type vim.lsp.Config
return {
  cmd = { constants.BINARIES.vscode_html_language_server(), "--stdio" },
  filetypes = constants.html_aliases,
}
