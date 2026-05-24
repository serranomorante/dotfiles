local lsp_utils = require("serranomorante.plugins.lsp.utils")

local bufnr = vim.api.nvim_get_current_buf()
local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })

if filetype == "vue" then
  lsp_utils.enable({ "vue_ls", "tailwindcss" }, bufnr)
else
  lsp_utils.enable({ "vtsls", "tailwindcss" }, bufnr)
end
