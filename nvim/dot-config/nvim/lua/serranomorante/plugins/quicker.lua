local M = {}

local opts = function()
  return {
    opts = {
      number = true,
    },
    on_qf = function()
      vim.keymap.set("n", ">", "<cmd>cnewer<CR>", { desc = "Quicker: go to next quickfix in history", nowait = true })
      vim.keymap.set(
        "n",
        "<",
        "<cmd>colder<CR>",
        { desc = "Quicker: go to previous quickfix in history", nowait = true }
      )
      vim.keymap.set("n", "+", function()
        require("quicker").expand({ before = 2, after = 2, add_to_existing = true })
        vim.api.nvim_win_set_height(0, math.min(20, vim.api.nvim_buf_line_count(0)))
      end, { desc = "Quicker: expand quickfix content" })
      vim.keymap.set("n", "=", function()
        require("quicker").collapse()
        vim.api.nvim_win_set_height(0, 10)
      end, { desc = "Quicker: collapse quickfix content" })
      vim.keymap.set(
        "n",
        "<C-l>",
        function() require("quicker").refresh() end,
        { desc = "Quicker: refresh quickfix content" }
      )
    end,
  }
end

M.config = function() require("quicker").setup(opts()) end

return M
