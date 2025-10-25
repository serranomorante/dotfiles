local constants = require("serranomorante.constants")

---@type vim.lsp.Config
return {
  cmd = { constants.BINARIES.phpactor(), "language-server" },
  filetypes = constants.php_aliases,
  root_markers = {
    "composer.json",
    ".git",
  },
}
