return {
  { "nvim-lua/plenary.nvim", lazy = true },
  { "kevinhwang91/promise-async", lazy = true },
  {
    "nvim-tree/nvim-web-devicons",
    lazy = true,
    init = function()
      vim.api.nvim_create_autocmd("ColorScheme", {
        desc = "Reset nvim-web-devicons highlight groups on ColorScheme",
        group = vim.api.nvim_create_augroup("nvim-web-devicons-group", { clear = true }),
        callback = function() require("nvim-web-devicons").setup({}) end,
      })
    end,
  },
}
