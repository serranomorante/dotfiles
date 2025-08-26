local coc_utils = require("serranomorante.plugins.coc.utils")
local lsp_utils = require("serranomorante.plugins.lsp.utils")

local bufnr = vim.api.nvim_get_current_buf()

if coc_utils.should_enable(bufnr) then
  require("serranomorante.plugins.coc").start(nil, { bufnr = bufnr })
  if not vim.g.markdown_preview_loaded then
    vim.cmd("CocCommand markdown-preview-enhanced.openPreview")
    vim.g.markdown_preview_loaded = true
  end
elseif lsp_utils.should_enable(bufnr) then
  vim.lsp.enable("marksman")
  vim.api.nvim_exec_autocmds("FileType", { group = "nvim.lsp.enable" })
else
  require("serranomorante.plugins.nvim-ufo").config()
end
