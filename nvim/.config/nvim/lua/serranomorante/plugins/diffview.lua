return {
  "sindrets/diffview.nvim",
  cmd = { "DiffviewOpen", "DiffviewFileHistory" },
  keys = {
    {
      "<leader>vd",
      "<cmd>DiffviewOpen<CR>",
      desc = "Diffview: compare against current index",
    },
    {
      "<leader>vf",
      "<cmd>DiffviewFileHistory %<CR>",
      desc = "Diffview: all commits affecting the current file",
    },
  },
  opts = {
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
      diff_buf_read = function(bufnr) vim.b[bufnr].coc_enabled = 0 end,
    },
  },
}
