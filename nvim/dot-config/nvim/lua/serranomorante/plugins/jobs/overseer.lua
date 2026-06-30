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
  vim.api.nvim_create_autocmd("FileType", {
    desc = "Attach task output navigation keymaps",
    pattern = "OverseerOutput",
    -- Covers Overseer tasks that were not created through our task helpers.
    callback = function(args)
      vim.schedule(function() utils.attach_overseer_task_output_navigation(args.buf) end)
    end,
  })
end

local function keys()
  local overseer = require("overseer")
  local open_markdown_preview = require("overseer.template.editor-tasks.TASK__open_markdown_preview")

  vim.keymap.set("n", "<leader>oo", function()
    for _, winid in ipairs(vim.api.nvim_list_wins()) do
      local filetype = vim.api.nvim_get_option_value("filetype", { buf = vim.api.nvim_win_get_buf(winid) })
      if filetype == "OverseerList" then return pcall(overseer.close, { winid = winid }) end
    end
    vim.cmd.tabedit()
    pcall(overseer.open, { winid = 0 })
  end, { desc = "Overseer: Toggle the overseer window" })
  vim.keymap.set("n", "<leader>or", "<cmd>OverseerRun<CR>", { desc = "Overseer: Run a task from a template" })
  vim.keymap.set("n", "<leader>oc", "<cmd>OverseerRunCmd<CR>", { desc = "Overseer: Run a raw shell command" })
  require("serranomorante.plugins.jobs.agent_sessions").keys()
  require("serranomorante.plugins.jobs.agent_tasks").setup_commands()
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
    "<leader>oa",
    function() require("serranomorante.plugins.jobs.overseer_task_actions").run_recent_task_action() end,
    { desc = "Overseer: task actions sorted by recent activity" }
  )
  vim.keymap.set(
    "x",
    "<leader>oa",
    function() require("serranomorante.plugins.jobs.overseer_task_actions").run_recent_task_action({ visual = true }) end,
    { desc = "Overseer: task actions sorted by recent activity" }
  )
  vim.keymap.set(
    "n",
    "<leader>od",
    function() require("serranomorante.plugins.jobs.overseer_task_actions").open_recent_task() end,
    { desc = "Overseer: open task output sorted by recent activity" }
  )
  vim.keymap.set(
    "x",
    "<leader>od",
    function() require("serranomorante.plugins.jobs.overseer_task_actions").open_recent_task({ visual = true }) end,
    { desc = "Overseer: open task output sorted by recent activity" }
  )

  vim.keymap.set("n", "<leader>lm", function()
    overseer.run_task({ name = open_markdown_preview.name }, function(task)
      if not task then return end
      task:subscribe("on_complete", utils.close_window_on_exit_0)
    end)
  end, { desc = "Open markdown preview" })

  vim.keymap.set("n", "<leader>e", function()
    if vim.fn.executable("kitty-nnn-quick-access") ~= 1 then
      return vim.api.nvim_echo({ { "kitty-nnn-quick-access not found", "DiagnosticError" } }, false, {})
    end

    local args = { "kitty-nnn-quick-access" }
    local filepath = vim.api.nvim_buf_get_name(0)
    if filepath ~= "" and (vim.fn.filereadable(filepath) == 1 or vim.fn.isdirectory(filepath) == 1) then
      table.insert(args, filepath)
    end

    local job_id = vim.fn.jobstart(args, {
      detach = true,
      env = {
        KITTY_NNN_INSTANCE_ROLE = "nvim",
      },
    })

    if job_id <= 0 then vim.api.nvim_echo({ { "Failed to launch nnn quick access", "DiagnosticError" } }, false, {}) end
  end, { desc = "Toggle explorer" })

  vim.keymap.set(
    "n",
    "<leader>tp",
    function() require("serranomorante.plugins.jobs.ansible_task_picker").select() end,
    { desc = "Show a list of ansible tasks in vim.ui.select" }
  )
end

local function opts()
  local STATUS = require("overseer.constants").STATUS
  local ok, record_screen_actions = pcall(require, "serranomorante.plugins.jobs.record_screen_actions")
  if not ok then
    record_screen_actions =
      dofile(vim.fn.expand("~/dotfiles/nvim/dot-config/nvim/lua/serranomorante/plugins/jobs/record_screen_actions.lua"))
  end

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
      -- Custom rendering ONLY for agent-tasks sessions: long-lived agent
      -- terminals are perpetually "RUNNING" to overseer, so show the real
      -- watch-detected state instead (running / awaiting_choice / idle). The
      -- state is kept live by the `serranomorante.agent_watch` component; for
      -- tasks without it we fall back to an instant on-demand classification.
      ---@param task overseer.Task
      render = function(task)
        local r = require("overseer.render")
        local lines = r.format_standard(task)
        local is_agent = task.metadata and task.metadata.agent_provider ~= nil
        if not is_agent then return lines end

        local ok, agent_tasks = pcall(require, "serranomorante.plugins.jobs.agent_tasks")
        local state = (task.metadata and task.metadata.agent_state)
          or (ok and agent_tasks.task_state(task))
          or "unknown"
        local badge = ({
          running = "WORKING",
          awaiting_choice = "NEEDS INPUT",
          idle = "idle",
          unknown = "?",
        })[state] or state
        local hl = ({
          running = "OverseerRUNNING",
          awaiting_choice = "DiagnosticWarn",
          idle = "OverseerSUCCESS",
          unknown = "Comment",
        })[state] or "Comment"

        -- Replace the perpetual RUNNING status chunk (line 1, chunk 1) with the
        -- agent state badge; keep the name + the rest of the standard layout.
        if lines[1] and lines[1][1] then
          lines[1][1] = { badge, hl }
        else
          table.insert(lines, 1, { { badge, hl } })
        end
        return lines
      end,
    },
    task_win = {
      padding = 0,
    },
    actions = vim.tbl_extend("force", {
      stop = {
        desc = "Stop a running task. Screen recordings are stopped through their control script so the file is saved.",
        condition = function(task) return task.status == STATUS.RUNNING end,
        run = function(task)
          if record_screen_actions.is_record_screen_task(task) then
            record_screen_actions.stop(task)
          else
            task:stop()
          end
        end,
      },
      ["close term window"] = {
        desc = "Close terminal window without killing process",
        condition = function(task) return task:get_bufnr() end,
        run = function(task)
          if not utils.is_terminal_buffer(task:get_bufnr()) then return end
          utils.feedkeys("<C-\\><C-n>", "t")
          vim.api.nvim_win_close(vim.api.nvim_get_current_win(), false)
        end,
      },
    }, record_screen_actions.actions()),
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
  local overseer = require("overseer")
  overseer.setup(opts())

  if utils.is_kitty_cwd_servername(vim.v.servername) then
    local generate_ctags = require("overseer.template.editor-tasks.TASK__generate_ctags")
    overseer.run_task({ name = generate_ctags.name })
  end
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
