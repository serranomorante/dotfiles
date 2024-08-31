local M = {}

local init = function()
  vim.g.colorizer_auto_filetype = "dap-repl"
  vim.g.colorizer_disable_bufleave = 1
  ---Disable everything except term to improve performance
  vim.g.colorizer_term_disable = 0
  vim.g.colorizer_term_bold_disable = 0
  vim.g.colorizer_term_nroff_disable = 0
  vim.g.colorizer_term_conceal_disable = 0
  vim.g.colorizer_vimhighl_dump_disable = 1
  vim.g.colorizer_taskwarrior_disable = 1
  vim.g.colorizer_vimhighlight_disable = 1
  vim.g.colorizer_vimcolors_disable = 1
  vim.g.colorizer_rgba_disable = 1
  vim.g.colorizer_rgb_disable = 1
  vim.g.colorizer_hsla_disable = 1
  vim.g.colorizer_colornames_disable = 1

  vim.api.nvim_create_autocmd("FileType", {
    desc = "Force colorize on dap-repl",
    pattern = "dap-repl",
    group = vim.api.nvim_create_augroup("auto_colorize", { clear = true }),
    callback = function() vim.cmd("ColorHighlight!") end,
  })
end

M.config = function() init() end

return M
