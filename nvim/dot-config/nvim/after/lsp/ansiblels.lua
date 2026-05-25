local constants = require("serranomorante.constants")

if not constants.BINARIES.ansible_language_server then return {} end

---@type vim.lsp.Config
return {
  cmd = { constants.BINARIES.ansible_language_server(), "--stdio" },
  filetypes = { "yaml.ansible" },
  root_markers = {
    "ansible.cfg",
    ".ansible-lint",
    ".git",
  },
  settings = {
    ansible = {
      ansible = {
        path = "ansible",
      },
      executionEnvironment = {
        enabled = false,
      },
      python = {
        interpreterPath = "python",
      },
      validation = {
        enabled = true,
        lint = {
          enabled = true,
          path = "ansible-lint",
          arguments = "-c " .. vim.fn.stdpath("config") .. "/lua/serranomorante/plugins/conform/ansible-lint-dev.yaml",
        },
      },
    },
  },
}
