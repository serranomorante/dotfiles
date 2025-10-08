vim.cmd.packadd("nvim.undotree")

vim.keymap.set("n", "<leader>uu", "<cmd>Undotree<CR>", { desc = "Toggle undotree" })
