local utils = require("serranomorante.utils")

local M = {}

local function init()
  vim.api.nvim_create_autocmd("FileType", {
    desc = "Force the task builder to always enter on insertmode",
    pattern = "OverseerForm",
    callback = function(args)
      if vim.fn.bufname(args.buf) ~= "Overseer task builder" then return end
      vim.defer_fn(function() vim.cmd.startinsert() end, 200)
    end,
  })
end

local function keys()
  local overseer = require("overseer")
  local nnn_explorer = require("overseer.template.editor-tasks.TASK__nnn_explorer")
  local lazygit = require("overseer.template.system-tasks.TASK__run_lazygit")
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
    "<cmd>OverseerTaskAction<CR>",
    { desc = "Overseer: Run open float action on the most recent task" }
  )
  vim.keymap.set(
    "n",
    "<leader>os",
    "<cmd>OverseerTaskAction<CR>",
    { desc = "Overseer: Select a task to run an action on" }
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

  local previous_task = nil
  vim.keymap.set("n", "<leader>w", function()
    if previous_task and previous_task.status == "RUNNING" then
      overseer.run_action(previous_task, "open float")
      return
    end
    overseer.run_task({ autostart = false, name = lazygit.name }, function(task)
      if not task then return end
      previous_task = task
      utils.force_very_fullscreen_float(task)
      utils.start_insert_mode(task)
      utils.attach_keymaps(task)
      task:start()
      vim.keymap.set("t", "<leader>", "<space>", { buffer = task:get_bufnr(), nowait = true })
      vim.keymap.set(
        "t",
        "q",
        function() overseer.run_action(task, "close term window") end,
        { buffer = task:get_bufnr() }
      )
    end)
  end)

  vim.keymap.set("n", "<leader>tp", function()
    local lines = {}
    vim.fn.jobstart("ansible-playbook tools.yml -l localhost --list-tasks", {
      cwd = vim.env.HOME .. "/dotfiles/playbooks",
      on_stdout = function(_, result)
        for _, line in ipairs(result) do
          if line ~= "" then table.insert(lines, line) end
        end
      end,
      on_exit = function(_, exit_code)
        local ok, private_tasks = pcall(require, "serranomorante.private-tasks")
        if exit_code ~= 0 then
          vim.notify("Command failed with exit code: " .. exit_code, vim.log.levels.ERROR)
          return
        end

        local items = {}

        for _, line in ipairs(lines) do
          -- Look for lines that contain tasks (have leading spaces and contain TAGS:)
          if line:match("^%s+.*TAGS:") then
            -- Extract task name (before TAGS:)
            local task_part = line:match("^%s+(.-)\tTAGS:")
            if task_part then
              -- Extract tags section
              local tags_part = line:match("TAGS:%s*%[(.-)%]")
              if tags_part then
                -- Extract role name (before the colon)
                local role_name = task_part:match("^(.-)%s*:")
                -- Extract task description (after the colon)
                local task_desc = task_part:match("^.-:%s*(.+)$") or task_part

                if role_name and task_desc then
                  -- Split tags by comma and process each
                  for tag in tags_part:gmatch("([^,]+)") do
                    tag = tag:match("^%s*(.-)%s*$") -- trim whitespace

                    -- Check if tag matches \d+-\d+ pattern (only numbers and dash)
                    if tag:match("^%d+%-%d+$") then
                      local item = tag .. " : " .. task_desc .. " (" .. role_name .. ")"
                      table.insert(items, item)
                    end
                  end
                end
              end
            end
          end
        end
        vim.list_extend(items, {
          "all", -- all tasks
          "setup", -- base tasks like running stow
          "never", -- very slow tasks that I rarely need to perform
          "always", -- tasks that should always be executed
          "20-50,20-60 [Full editor setup]",
          "10-170,20-170 [Full AI setup]",
          "10-170,40-20 [Full browser extensions]",
          "10-system-tools,20-dev-tools,30-lang-tools,40-PKM,80-for-my-eyes-only [Base setup]",
        })
        -- Add private playbooks
        if ok then vim.list_extend(items, private_tasks or {}) end

        -- Remove duplicates (same task might have multiple numeric tags)
        local unique_items = {}
        local seen = {}
        for _, item in ipairs(items) do
          if not seen[item] then
            table.insert(unique_items, item)
            seen[item] = true
          end
        end

        if #unique_items == 0 then
          vim.notify("No tasks with numeric tags found", vim.log.levels.WARN)
          return
        end

        vim.ui.select(unique_items, {
          prompt = "Ansible tasks",
          format_item = function(item) return item end,
        }, function(choice)
          if choice then
            local playbooks = require("overseer.template.system-tasks.TASK__run_ansible_playbook")
            require("overseer").run_task({
              name = playbooks.name,
              params = { task_id = choice, pass = vim.g.pass },
            }, function(task)
              if not task then return end
              utils.force_very_fullscreen_float(task)
              utils.attach_keymaps(task)
              vim.defer_fn(function()
                overseer.run_action(task, "open float")
                utils.write_password({ delay = 1000 })
              end, 500)
            end)
          end
        end)
      end,
    })
  end, { desc = "Show a list of ansible tasks in vim.ui.select" })
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
          vim.defer_fn(function()
            require("overseer").run_action(task, "open float")
            utils.write_password({ delay = 1000 })
          end, 500)
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
