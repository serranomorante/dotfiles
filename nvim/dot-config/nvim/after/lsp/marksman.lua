local constants = require("serranomorante.constants")

if not constants.BINARIES.marksman then return {} end

---@type vim.lsp.Config
return {
  cmd = { constants.BINARIES.marksman(), "server" },
  filetypes = constants.markdown_aliases,
}
