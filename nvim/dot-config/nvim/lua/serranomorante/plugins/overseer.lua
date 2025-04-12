local M = {}

local function keys()
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
    "<leader>oa",
    "<cmd>OverseerQuickAction open float insertmode<CR>",
    { desc = "Overseer: Run open float action on the most recent task" }
  )
  vim.keymap.set(
    "n",
    "<leader>os",
    "<cmd>OverseerTaskAction<CR>",
    { desc = "Overseer: Select a task to run an action on" }
  )
  vim.keymap.set("n", "<leader>lm", function()
    local overseer = require("overseer")
    local task_spec = require("overseer.template.editor-tasks.TASK__open_markdown_preview")
    overseer.run_template({ name = task_spec.name }, function(task)
      if not task then return end
      require("overseer").run_action(task, "open float")
      if vim.bo.buftype == "terminal" then vim.cmd.startinsert() end
    end)
  end, { desc = "Open markdown preview" })
end

local function opts()
  ---@type overseer.Config
  return {
    strategy = "jobstart",
    ---Disable the automatic patch and do it manually on nvim-dap config
    ---https://github.com/stevearc/overseer.nvim/blob/master/doc/third_party.md#dap
    dap = false,
    templates = { "builtin", "vscode-tasks", "editor-tasks", "debugging-tasks", "system-tasks" },
    task_list = {
      direction = "left",
    },
    task_win = {
      border = "single",
      padding = 0,
    },
    actions = {
      ["open float insertmode"] = {
        desc = "Open float in insert mode",
        condition = function(task) return task:get_bufnr() end,
        run = function(task)
          task:open_output("float")
          vim.defer_fn(function()
            if vim.bo.buftype == "terminal" then vim.cmd.startinsert() end
          end, 200)
        end,
      },
    },
    component_aliases = {
      defaults_without_notification = {
        { "display_duration", detail_level = 2 },
        "on_output_summarize",
        "on_exit_set_status",
        { "on_complete_dispose", require_view = { "SUCCESS", "FAILURE" } },
      },
    },
  }
end

function M.config()
  keys()
  require("overseer").setup(opts())
end

---Check if task is allowed to store in session
---@param task overseer.Task
---@return boolean
function M.task_allowed_to_store_in_session(task)
  local allowed_tasks = {
    "editor-tasks-refresh-ctags",
  }
  return vim.tbl_count(
    vim.tbl_filter(
      function(allowed_task) return string.find(task.name, allowed_task, nil, true) ~= nil end,
      allowed_tasks
    )
  ) > 0
end

return M
