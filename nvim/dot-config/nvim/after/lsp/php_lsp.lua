local constants = require("serranomorante.constants")

if not constants.BINARIES.phpactor then return {} end

---@type vim.lsp.Config
return {
  cmd = { constants.BINARIES.phpactor(), "language-server" },
  filetypes = constants.php_aliases,
  root_markers = {
    "composer.json",
    ".git",
  },
}
