local M = {}

local keys = function()
  vim.keymap.set("n", "<leader>oo", "<cmd>OverseerToggle<CR>", { desc = "Overseer: Toggle the overseer window" })
  vim.keymap.set("n", "<leader>or", "<cmd>OverseerRun<CR>", { desc = "Overseer: Run a task from a template" })
  vim.keymap.set("n", "<leader>oc", "<cmd>OverseerRunCmd<CR>", { desc = "Overseer: Run a raw shell command" })
  vim.keymap.set(
    "n",
    "<leader>ol",
    "<cmd>OverseerLoadBundle<CR>",
    { desc = "Overseer: Load tasks that were saved to disk" }
  )
  vim.keymap.set(
    "n",
    "<leader>ob",
    "<cmd>OverseerToggle! bottom<CR>",
    { desc = "Overseer: Toggle the overseer window. Cursor stays in current window" }
  )
  vim.keymap.set(
    "n",
    "<leader>od",
    "<cmd>OverseerQuickAction<CR>",
    { desc = "Overseer: Run an action on the most recent task" }
  )
  vim.keymap.set(
    "n",
    "<leader>os",
    "<cmd>OverseerTaskAction<CR>",
    { desc = "Overseer: Select a task to run an action on" }
  )
end

local opts = function()
  return {
    ---Disable the automatic patch and do it manually on nvim-dap config
    ---https://github.com/stevearc/overseer.nvim/blob/master/doc/third_party.md#dap
    dap = false,
    templates = { "builtin", "vscode-tasks", "editor-tasks", "debugging-tasks" },
    task_win = {
      border = "single",
      padding = 0,
    },
  }
end

M.config = function()
  keys()
  require("overseer").setup(opts())
end

return M
