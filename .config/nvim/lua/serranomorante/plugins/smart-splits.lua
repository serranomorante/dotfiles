return {
  {
    "mrjones2014/smart-splits.nvim",
    keys = {
      ---Moving between splits
      {
        "<C-h>",
        function() require("smart-splits").move_cursor_left() end,
        desc = "Splits: Move cursor left",
      },
      {
        "<C-j>",
        function() require("smart-splits").move_cursor_down() end,
        desc = "Splits: Move cursor down",
      },
      {
        "<C-k>",
        function() require("smart-splits").move_cursor_up() end,
        desc = "Splits: Move cursor up",
      },
      {
        "<C-l>",
        function() require("smart-splits").move_cursor_right() end,
        desc = "Splits: Move cursor right",
      },
      ---Resize splits keymaps
      {
        "<C-Left>",
        function() require("smart-splits").resize_left() end,
        desc = "Splits: Resize left",
      },
      {
        "<C-Down>",
        function() require("smart-splits").resize_down() end,
        desc = "Splits: Resize down",
      },
      {
        "<C-Up>",
        function() require("smart-splits").resize_up() end,
        desc = "Splits: Resize up",
      },
      {
        "<C-Right>",
        function() require("smart-splits").resize_right() end,
        desc = "Splits: Resize right",
      },
      ---Swap splits keymaps
      {
        "<leader><leader>h",
        function() require("smart-splits").swap_buf_left() end,
        desc = "Splits: Swap left",
      },
      {
        "<leader><leader>j",
        function() require("smart-splits").swap_buf_down() end,
        desc = "Splits: Swap down",
      },
      {
        "<leader><leader>k",
        function() require("smart-splits").swap_buf_up() end,
        desc = "Splits: Swap up",
      },
      {
        "<leader><leader>l",
        function() require("smart-splits").swap_buf_right() end,
        desc = "Splits: Swap right",
      },
    },
    opts = {
      cursor_follows_swapped_bufs = true,
      ignored_filetypes = {
        "nofile",
        "prompt",
      },
    },
  },
}
