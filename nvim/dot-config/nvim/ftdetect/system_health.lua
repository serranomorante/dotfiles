if vim.filetype then
  vim.filetype.add({
    pattern = {
      [".*/data/notes/foam/ops/system%-health/.*%.md"] = "markdown.system_health",
    },
  })
else
  vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
    pattern = "*/data/notes/foam/ops/system-health/*.md",
    callback = function() vim.bo.filetype = "markdown.system_health" end,
  })
  vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
    pattern = "*/data/notes/foam/ops/system-health/**/*.md",
    callback = function() vim.bo.filetype = "markdown.system_health" end,
  })
end
