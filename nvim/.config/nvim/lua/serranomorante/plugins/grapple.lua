return {
  "cbochs/grapple.nvim",
  init = function()
    vim.api.nvim_create_autocmd("FileType", {
      pattern = "grapple",
      callback = vim.schedule_wrap(function()
        for _, option in ipairs({ { "cursorline", true }, { "cursorlineopt", "line" } }) do
          vim.api.nvim_set_option_value(option[1], option[2], {
            scope = "local",
            win = 0,
          })
        end
      end),
    })
  end,
  opts = {
    prune = "99999999999999999d",
    scope = "cwd",
    win_opts = {
      width = 999,
    },
  },
  event = { "BufReadPost", "BufNewFile" },
  cmd = "Grapple",
  keys = {
    { "<leader>m", "<cmd>Grapple toggle<cr>", desc = "Grapple toggle tag" },
    { "<leader>M", "<cmd>Grapple toggle_tags<cr>", desc = "Grapple open tags window" },
    { "<leader>n", "<cmd>Grapple cycle_tags next<cr>", desc = "Grapple cycle next tag" },
    { "<leader>p", "<cmd>Grapple cycle_tags prev<cr>", desc = "Grapple cycle previous tag" },
  },
}
