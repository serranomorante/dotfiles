local binaries = require("serranomorante.binaries")
local constants = require("serranomorante.constants")

---@type vim.lsp.Config
return {
  cmd = { binaries.vscode_html_language_server(), "--stdio" },
  filetypes = constants.html_aliases,
}
