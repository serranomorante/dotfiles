local lsp_utils = require("serranomorante.plugins.lsp.utils")

local bufnr = vim.api.nvim_get_current_buf()
local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })

if filetype == "yaml.ansible" then
  lsp_utils.enable({ "yamlls", "ansiblels" }, bufnr)
else
  lsp_utils.enable("yamlls", bufnr)
end
