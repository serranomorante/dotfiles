local utils = require("serranomorante.utils")

local bufnr = vim.api.nvim_get_current_buf()

if utils.buf_prevent_coc_attach(bufnr) then
  -- lsp setup here
else
  vim.cmd.CocStart()
end
