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

    if vim.fn.executable("lazygit") == 1 then
      table.insert(keymaps, {
        "<leader>gg",
        function()
          local template_name = "Toggle Lazygit"
          local overseer = require("overseer")
          local STATUS = require("overseer.constants").STATUS
          local tasks = overseer.list_tasks({ name = "lazygit", status = STATUS.RUNNING })

          if #tasks == 0 then
            overseer.run_template({ name = template_name }, function(task)
              if task then overseer.run_action(task, "open float") end
            end)
          else
            for _, task in pairs(tasks) do
              if task then overseer.run_action(task, "open float") end
            end
          end

          ---Auto enter insert mode
          ---https://github.com/stevearc/overseer.nvim/issues/44#issuecomment-1270198242
          vim.defer_fn(function()
            if vim.api.nvim_get_option_value("buftype", { buf = 0 }) == "terminal" then vim.cmd([[startinsert]]) end
          end, 100)
        end,
        desc = "Overseer: Toggle Lazygit Task",
      })
    end

    return keymaps
  end,
  opts = {
    ---Disable the automatic patch and do it manually on nvim-dap config
    ---https://github.com/stevearc/overseer.nvim/blob/master/doc/third_party.md#dap
    dap = false,
    templates = { "builtin", "vscode-tasks", "editor" },
    task_win = {
      border = "single",
      win_opts = {
        winblend = 0,
      },
    },
  },
}
