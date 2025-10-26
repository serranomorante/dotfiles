local utils = require("serranomorante.utils")

local M = {}

local function init()
  vim.api.nvim_create_autocmd("FileType", {
    desc = "Force OverseerForm to always enter insertmode",
    pattern = "OverseerForm",
    callback = function()
      vim.defer_fn(function() vim.cmd.startinsert() end, 200)
    end,
  })
end

local function keys()
  local overseer = require("overseer")
  local nnn_explorer = require("overseer.template.editor-tasks.TASK__nnn_explorer")
  local open_markdown_preview = require("overseer.template.editor-tasks.TASK__open_markdown_preview")

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
    "<cmd>OverseerTaskAction<CR>",
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

  vim.keymap.set(
    "n",
    "<leader>lm",
    function() overseer.run_template({ name = open_markdown_preview.name }) end,
    { desc = "Open markdown preview" }
  )

  vim.keymap.set("n", "<leader>e", function()
    overseer.run_template(
      { name = nnn_explorer.name, params = { startdir = vim.fn.expand("%:p") } },
      ---@param task overseer.Task
      function(task)
        vim.api.nvim_create_autocmd("WinLeave", {
          group = vim.api.nvim_create_augroup("nnn.explorer", { clear = true }),
          callback = function(args)
            local ok, task_id = pcall(vim.api.nvim_buf_get_var, args.buf, "overseer_task")
            if ok and task_id == task.id then task:dispose(true) end
          end,
        })
      end,
      { desc = "Toggle explorer" }
    )
  end)
end

local function opts()
  ---@type overseer.Config
  return {
    strategy = "terminal",
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
      ["Restart playbook"] = {
        desc = "Restart playbook",
        condition = function(task) return task.name:match("^run%-ansible%-playbook") end,
        run = function(task)
          utils.write_password({ delay = 1000 })
          require("overseer").run_action(task, "restart")
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
  init()
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
