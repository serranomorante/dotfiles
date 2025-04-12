local binaries = require("serranomorante.binaries")
local constants = require("serranomorante.constants")

---@type vim.lsp.Config
return {
  cmd = { binaries.phpactor(), "language-server" },
  filetypes = constants.php_aliases,
  root_markers = {
    "composer.json",
    ".git",
  },
}
