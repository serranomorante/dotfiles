local binaries = require("serranomorante.binaries")
local constants = require("serranomorante.constants")

---@type vim.lsp.Config
return {
  cmd = { binaries.fish_lsp(), "start" },
  filetypes = constants.fish_aliases,
  cmd_env = { fish_lsp_show_client_popups = false },
  root_markers = {
    ".fish",
    ".git",
  },
}
