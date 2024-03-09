return {
  "lewis6991/gitsigns.nvim",
  enabled = vim.fn.executable("git") == 1,
  ---Do not lazy load gitsigns
  ---https://github.com/lewis6991/gitsigns.nvim/issues/796#issuecomment-1554076466
  lazy = false,
  opts = {
    worktrees = vim.g.git_worktrees,
    attach_to_untracked = true,
  },
  keys = {
    {
      "<leader>gl",
      function() require("gitsigns").blame_line() end,
      desc = "Git: Blame line",
    },
    {
      "<leader>gL",
      function() require("gitsigns").blame_line({ full = true }) end,
      desc = "Git: Blame full buffer",
    },
    {
      "<leader>gd",
      function() require("gitsigns").diffthis() end,
      desc = "Git: Diff this",
    },
    {
      "<leader>gp",
      function() require("gitsigns").preview_hunk() end,
      desc = "Git: Preview hunk",
    },
    {
      "]g",
      function() require("gitsigns").next_hunk() end,
      desc = "Git: Next hunk",
    },
    {
      "[g",
      function() require("gitsigns").prev_hunk() end,
      desc = "Git: Prev hunk",
    },
    {
      "<leader>gh",
      function() require("gitsigns").reset_hunk() end,
      desc = "Git: Reset hunk",
    },
    {
      "<leader>gh",
      ":Gitsigns reset_hunk<CR>",
      desc = "Git: Reset hunk (partial)",
      mode = "v",
    },
    {
      "<leader>gH",
      function() require("gitsigns").reset_buffer() end,
      desc = "Git: Reset buffer",
    },
    {
      "<leader>gS",
      function() require("gitsigns").stage_buffer() end,
      desc = "Git: Stage buffer",
    },
    {
      "<leader>gs",
      function() require("gitsigns").stage_hunk() end,
      desc = "Git: Stage hunk",
    },
    {
      "<leader>gs",
      ":Gitsigns stage_hunk<CR>",
      desc = "Git: Stage hunk (partial)",
      mode = "v",
    },
    {
      "<leader>gu",
      function() require("gitsigns").undo_stage_hunk() end,
      desc = "Git: Unstage hunk",
    },
  },
}
