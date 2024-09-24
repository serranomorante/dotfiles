local dap_repl_hl = vim.api.nvim_create_namespace("dap-repl-hl")
vim.api.nvim_set_hl(dap_repl_hl, "Normal", { bg = "NvimDarkGray3" })
vim.api.nvim_win_set_hl_ns(0, dap_repl_hl)
