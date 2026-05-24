local lsp_utils = require("serranomorante.plugins.lsp.utils")

local bufnr = vim.api.nvim_get_current_buf()

lsp_utils.enable("yamlls", bufnr)
