local M = {}

local init = function()
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
end

local opts = function()
  return {
    prune = "99999999999999999d",
    scope = "cwd",
    win_opts = {
      width = 999,
    },
  }
end

local keys = function()
  vim.keymap.set("n", "<leader>m", "<cmd>Grapple toggle<cr>", { desc = "Grapple toggle tag" })
  vim.keymap.set("n", "<leader>M", "<cmd>Grapple toggle_tags<cr>", { desc = "Grapple open tags window" })
  vim.keymap.set("n", "<leader>n", "<cmd>Grapple cycle_tags next<cr>", { desc = "Grapple cycle next tag" })
  vim.keymap.set("n", "<leader>p", "<cmd>Grapple cycle_tags prev<cr>", { desc = "Grapple cycle previous tag" })
end

M.config = function()
  init()
  keys()
  require("grapple").setup(opts())
end

return M
