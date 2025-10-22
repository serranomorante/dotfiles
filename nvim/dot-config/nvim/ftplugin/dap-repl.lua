local winid = vim.api.nvim_get_current_win()
vim.api.nvim_set_option_value("winhl", "Normal:CustomDapReplBg", { win = winid })
