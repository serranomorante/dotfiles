vim.api.nvim_create_autocmd("BufReadPost", {
  desc = "Force html filetype when htmlangular is somehow detected",
  pattern = "*.html",
  command = "set filetype=html",
})
