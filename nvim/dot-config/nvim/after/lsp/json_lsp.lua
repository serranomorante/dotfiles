local constants = require("serranomorante.constants")

if not constants.BINARIES.vscode_json_language_server then return {} end

---@type vim.lsp.Config
return {
  cmd = { constants.BINARIES.vscode_json_language_server(), "--stdio" },
  filetypes = constants.json_aliases,
  root_markers = {
    "package.json",
    ".git",
  },
}
