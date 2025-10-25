local constants = require("serranomorante.constants")

---@type vim.lsp.Config
return {
  cmd = { constants.BINARIES.marksman(), "server" },
  filetypes = constants.markdown_aliases,
}
