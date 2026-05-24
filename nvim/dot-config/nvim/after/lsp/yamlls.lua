local constants = require("serranomorante.constants")

if not constants.BINARIES.yaml_language_server then return {} end

---@type vim.lsp.Config
return {
  cmd = { constants.BINARIES.yaml_language_server(), "--stdio" },
  filetypes = constants.yaml_aliases,
  root_markers = {
    ".git",
  },
  settings = {
    redhat = {
      telemetry = {
        enabled = false,
      },
    },
    yaml = {
      format = {
        enable = true,
      },
    },
  },
}
