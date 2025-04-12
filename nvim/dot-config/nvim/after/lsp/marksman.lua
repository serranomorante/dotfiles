local binaries = require("serranomorante.binaries")
local constants = require("serranomorante.constants")

---@type vim.lsp.Config
return {
  cmd = { binaries.marksman(), "server" },
  filetypes = constants.markdown_aliases,
}
