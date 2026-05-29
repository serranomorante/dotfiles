local constants = require("serranomorante.constants")

if not constants.BINARIES.ansible_language_server then return {} end

local ansible_lint_path = vim.fn.expand("~/.local/bin/ansible-lint")

---@type vim.lsp.Config
return {
  cmd = { constants.BINARIES.ansible_language_server(), "--stdio" },
  filetypes = { "yaml.ansible" },
  before_init = function(params)
    -- Firejail's PID namespace can hide Neovim's host PID from the server.
    -- vscode-languageserver treats an invisible processId as a dead client.
    params.processId = vim.NIL
  end,
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
          path = ansible_lint_path,
          arguments = "-c " .. vim.fn.stdpath("config") .. "/lua/serranomorante/plugins/conform/ansible-lint-dev.yaml",
        },
      },
    },
  },
}
