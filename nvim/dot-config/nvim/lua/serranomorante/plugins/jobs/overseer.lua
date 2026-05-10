local utils = require("serranomorante.utils")

local M = {}

local function init()
  vim.api.nvim_create_autocmd("FileType", {
    desc = "Force the task builder to always enter on insertmode",
    pattern = "OverseerForm",
    callback = function(args)
      if vim.fn.bufname(args.buf) ~= "Overseer form" then return end
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

  vim.keymap.set("n", "<leader>lm", function()
    overseer.run_task({ name = open_markdown_preview.name }, function(task)
      if not task then return end
      task:subscribe("on_complete", utils.close_window_on_exit_0)
    end)
  end, { desc = "Open markdown preview" })

  vim.keymap.set("n", "<leader>e", function()
    overseer.run_task(
      { autostart = false, name = nnn_explorer.name, params = { startdir = vim.fn.expand("%:p") } },
      function(task)
        if not task then return end
        utils.force_very_fullscreen_float(task)
        utils.start_insert_mode(task)
        task:subscribe("on_output", utils.dispose_on_window_close)
        task:subscribe("on_complete", utils.close_window_on_exit_0)
        task:start()
      end
    )
  end, { desc = "Toggle explorer" })

  vim.keymap.set("n", "<leader>w", function() utils.cmd({ "kitten", "@", "action", "goto_tab", "2" }) end)

  vim.keymap.set(
    "n",
    "<leader>tp",
    function() require("serranomorante.plugins.jobs.ansible_task_picker").select() end,
    { desc = "Show a list of ansible tasks in vim.ui.select" }
  )
end

local function opts()
  ---@type overseer.SetupOpts
  return {
    output = {
      use_terminal = true,
      preserve_output = true,
    },
    ---Disable the automatic patch and do it manually on nvim-dap config
    ---https://github.com/stevearc/overseer.nvim/blob/master/doc/third_party.md#dap
    dap = true,
    form = {
      border = "single",
    },
    task_list = {
      direction = "left",
    },
    task_win = {
      padding = 0,
    },
    actions = {
      ["close term window"] = {
        desc = "Close terminal window without killing process",
        condition = function(task) return task:get_bufnr() end,
        run = function()
          if vim.bo.buftype ~= "terminal" then return end
          utils.feedkeys("<C-\\><C-n>", "t")
          vim.api.nvim_win_close(vim.api.nvim_get_current_win(), false)
        end,
      },
      ["Restart playbook"] = {
        desc = "Restart playbook",
        condition = function(task) return task.name:match("^run%-ansible%-playbook") end,
        run = function(task)
          require("overseer").run_action(task, "restart")
          utils.attach_keymaps(task)
          utils.schedule_open_overseer_task_float(task)
        end,
      },
      ["Quit & save ffmpeg recording"] = {
        desc = "Send `q` to the terminal. This quits ffmpeg recording.",
        condition = function(task)
          return task.name:match("^ffmpeg") and task.status == require("overseer.constants").STATUS.RUNNING
        end,
        run = function(task)
          utils.attach_keymaps(task)
          require("overseer").run_action(task, "open float")
          utils.feedkeys("q", "t")
        end,
      },
    },
    component_aliases = {
      defaults_without_dispose = {
        "on_exit_set_status",
        "on_complete_notify",
      },
      defaults_without_notification = {
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
