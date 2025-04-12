local binaries = require("serranomorante.binaries")
local constants = require("serranomorante.constants")

---@type vim.lsp.Config
return {
  cmd = { binaries.gopls() },
  filetypes = constants.go_aliases,
  root_markers = {
    "go.work",
    "go.mod",
    ".git",
  },
}
