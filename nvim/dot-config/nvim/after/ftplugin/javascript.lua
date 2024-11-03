local lsp = require("serranomorante.plugins.lsp")
local coc_utils = require("serranomorante.plugins.coc.utils")

local bufnr = vim.api.nvim_get_current_buf()

if coc_utils.should_enable(bufnr) then
  require("serranomorante.plugins.coc").start(nil, { bufnr = bufnr })
else
  lsp.start(require("serranomorante.plugins.lsp.configs.vtsls").config(bufnr), { bufnr = bufnr })
  lsp.start(require("serranomorante.plugins.lsp.configs.tailwindcss").config(bufnr), { bufnr = bufnr })
end
