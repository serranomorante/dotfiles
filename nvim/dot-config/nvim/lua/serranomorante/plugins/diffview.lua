local M = {}

local keys = function()
  vim.keymap.set("n", "<leader>vd", "<cmd>DiffviewOpen<CR>", { desc = "Diffview: compare against current index" })
  vim.keymap.set(
    "n",
    "<leader>vf",
    "<cmd>DiffviewFileHistory %<CR>",
    { desc = "Diffview: all commits affecting the current file" }
  )
end

local opts = function()
  return {
    watch_index = false,
    default_args = {
      DiffviewFileHistory = { "--no-merges" },
    },
    view = {
      default = {
        winbar_info = true,
      },
      file_history = {
        winbar_info = true,
      },
    },
    file_panel = {
      win_config = {
        width = 50,
        win_opts = {
          number = true,
          cursorlineopt = "line,number",
        },
      },
    },
    file_history_panel = {
      win_config = {
        win_opts = {
          number = true,
          cursorlineopt = "line,number",
        },
      },
    },
    hooks = {
      ---Fixes issue with coc.nvim
      diff_buf_read = function(bufnr) vim.api.nvim_buf_set_var(bufnr, "coc_enabled", 0) end,
    },
  }
end

M.config = function()
  keys()
  require("diffview").setup(opts())
end

return M
