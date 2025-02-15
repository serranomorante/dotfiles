local lsp = require("serranomorante.plugins.lsp")
local lsp_utils = require("serranomorante.plugins.lsp.utils")
local coc_utils = require("serranomorante.plugins.coc.utils")

local bufnr = vim.api.nvim_get_current_buf()

if coc_utils.should_enable(bufnr) then
  require("serranomorante.plugins.coc").start(nil, { bufnr = bufnr })
elseif lsp_utils.should_enable(bufnr) then
  lsp.start(require("serranomorante.plugins.lsp.configs.html_lsp").config(bufnr), { bufnr = bufnr })
end
