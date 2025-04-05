local coc_utils = require("serranomorante.plugins.coc.utils")

local bufnr = vim.api.nvim_get_current_buf()

if coc_utils.should_enable(bufnr) then
  require("serranomorante.plugins.coc").start(nil, { bufnr = bufnr })
else
  require("serranomorante.plugins.nvim-ufo").config()
end
