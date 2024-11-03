local repl_ns = vim.api.nvim_create_namespace("dap-repl-hl")
local group = vim.api.nvim_create_augroup("dap-repl-hl", { clear = true })
local buffer = vim.api.nvim_get_current_buf()

vim.api.nvim_create_autocmd({ "BufEnter", "TabEnter", "WinEnter" }, {
  desc = "Change window background color for dap-repl",
  buffer = buffer,
  group = group,
  callback = function()
    vim.api.nvim_set_hl(repl_ns, "Normal", { link = "CustomDapReplBg" })
    vim.api.nvim_win_set_hl_ns(0, repl_ns)
  end,
})

vim.api.nvim_create_autocmd("BufLeave", {
  desc = "Reset window background color when leaving dap-repl",
  buffer = buffer,
  group = group,
  callback = vim.schedule_wrap(function() vim.api.nvim_win_set_hl_ns(0, 0) end),
})
