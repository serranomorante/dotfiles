return {
  "stevearc/overseer.nvim",
  lazy = true,
  keys = function()
    local keymaps = {
      { "<leader>oo", "<cmd>OverseerToggle<CR>", desc = "Overseer: Toggle the overseer window" },
      { "<leader>or", "<cmd>OverseerRun<CR>", desc = "Overseer: Run a task from a template" },
      { "<leader>oc", "<cmd>OverseerRunCmd<CR>", desc = "Overseer: Run a raw shell command" },
      { "<leader>ol", "<cmd>OverseerLoadBundle<CR>", desc = "Overseer: Load tasks that were saved to disk" },
      {
        "<leader>ob",
        "<cmd>OverseerToggle! bottom<CR>",
        desc = "Overseer: Toggle the overseer window. Cursor stays in current window",
      },
      { "<leader>od", "<cmd>OverseerQuickAction<CR>", desc = "Overseer: Run an action on the most recent task" },
      { "<leader>os", "<cmd>OverseerTaskAction<CR>", desc = "Overseer: Select a task to run an action on" },
    }
    return keymaps
  end,
  opts = {
    ---Disable the automatic patch and do it manually on nvim-dap config
    ---https://github.com/stevearc/overseer.nvim/blob/master/doc/third_party.md#dap
    dap = false,
    templates = { "builtin", "vscode-tasks", "editor-tasks", "debugging-tasks" },
    task_win = {
      border = "single",
      padding = 0,
    },
  },
}
