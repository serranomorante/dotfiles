local palette = {
  red = "#c94f6d",
  blue = "#719cd6",
  cyan = "#63cdcf",
}

vim.api.nvim_set_hl(0, "StatusLine", { link = "CursorLine" })
vim.api.nvim_set_hl(0, "LspCodeLens", { link = "Comment" })

---nvim-dap
vim.api.nvim_set_hl(0, "DapBreakpoint", { fg = palette.red })
vim.api.nvim_set_hl(0, "DapLogPoint", { fg = palette.blue })
vim.api.nvim_set_hl(0, "DapStopped", { fg = palette.cyan })
