local constants = require("serranomorante.constants")
local tools = require("serranomorante.tools")

local M = {}

M.config = function()
  vim.g.ale_use_global_executables = 1
  vim.g.ale_use_neovim_diagnostics_api = 1
  vim.g.ale_detail_to_floating_preview = 1
  vim.g.ale_disable_lsp = 1
  vim.g.ale_echo_cursor = 0
  vim.g.ale_hover_cursor = 0
  vim.g.ale_linters_explicit = 1
  vim.g.ale_maximum_file_size = vim.g.max_file.size
  vim.g.ale_set_signs = 0

  vim.g.ale_javascript_eslint_executable = "eslint_d"

  vim.g.ale_linter_aliases = {
    ["javascript"] = constants.javascript_aliases,
  }

  vim.g.ale_linters = {
    javascript = { "eslint" },
    javascriptreact = { "eslint" },
    typescript = { "eslint" },
    typescriptreact = { "eslint" },
    markdown = tools.by_filetype.markdown.linters,
    python = tools.by_filetype.python.linters,
  }
end

return M
