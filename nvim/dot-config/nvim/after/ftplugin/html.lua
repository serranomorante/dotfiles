local utils = require("serranomorante.utils")
local lsp = require("serranomorante.plugins.lsp")

local bufnr = vim.api.nvim_get_current_buf()

if utils.buf_prevent_coc_attach(bufnr) then
  lsp.start(require("serranomorante.plugins.lsp.configs.html_lsp").config(bufnr), { bufnr = bufnr })
else
  vim.cmd.CocStart()
end
