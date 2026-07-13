-- agent_watch: keep an interactive agent session's STATE live in the task list.
--
-- Long-lived agent terminals (claude/codex/gemini) are perpetually "RUNNING" to
-- overseer, so the built-in status is useless. This component reclassifies the
-- agent's REAL state (running / awaiting_choice / idle) from its terminal output,
-- stores it on `task.metadata.agent_state`, and `touch`es the task list so the
-- custom render (see the overseer `task_list.render` config) repaints. It is cheap
-- and non-blocking (no vim.wait): classification is a regex over the last ~30
-- output lines, and only fires a re-render on an actual change.
--
-- WHY a timer (not only on_output_lines): the agent's transition to IDLE is an
-- in-place TUI redraw (ANSI), which often emits NO parseable "output line" event,
-- so an event-only watcher leaves agent_state stuck on the last "running". A light
-- repeating timer re-reads the buffer tail and catches the idle settle. on_output_lines
-- still gives instant updates while the agent is actively streaming.
--
-- Scope: only meaningful on agent tasks (those carry agent_provider metadata).
-- Attached to new sessions by agent_sessions.lua and retrofit to existing ones
-- via `agent-tasks` (M.attach_watch_all).
local POLL_MS = 3000
local PROVIDER_KEY = "agent_provider"
local SESSION_ID_KEY = "agent_session_id"
local NOTIFICATION_ACTION_BIN = vim.fn.expand("~/bin/notification-action")

---@param state string
---@return string
local function state_label(state)
  return ({
    awaiting_choice = "needs input",
    idle = "idle",
    running = "working",
    unknown = "unknown",
  })[state] or state
end

---@param value string?
---@param max integer
---@return string
local function truncate(value, max)
  value = tostring(value or "")
  if #value <= max then return value end
  return value:sub(1, max - 1) .. "..."
end

---@param path string?
---@return string
local function compact_path(path)
  if type(path) ~= "string" or path == "" then return "unknown cwd" end
  return vim.fn.fnamemodify(path, ":~")
end

---@param task overseer.Task
---@param state string
---@return string
local function notification_summary(task, state)
  local provider = task.metadata and task.metadata[PROVIDER_KEY] or "agent"
  if state == "awaiting_choice" then return ("%s needs input"):format(provider) end
  if state == "idle" then return ("%s is idle"):format(provider) end
  return ("%s changed state"):format(provider)
end

---@param task overseer.Task
---@param state string
---@return string
local function notification_body(task, state)
  local metadata = task.metadata or {}
  local provider = tostring(metadata[PROVIDER_KEY] or "agent")
  local session_id = tostring(metadata[SESSION_ID_KEY] or "")
  local sid = session_id ~= "" and session_id:sub(1, 8) or "pending"
  return table.concat({
    ("State: %s"):format(state_label(state)),
    ("Task: %s"):format(truncate(task.name, 72)),
    ("Provider: %s   Session: %s"):format(provider, sid),
    ("CWD: %s"):format(truncate(compact_path(task.cwd), 72)),
    "Click to open the agent task.",
  }, "\n")
end

---@param task overseer.Task
---@param state string
local function send_system_notification(task, state)
  local metadata = task.metadata or {}
  local session_id = metadata[SESSION_ID_KEY]
  if type(session_id) ~= "string" or session_id == "" then return end
  if type(vim.v.servername) ~= "string" or vim.v.servername == "" then return end
  if vim.fn.executable(NOTIFICATION_ACTION_BIN) ~= 1 then return end

  local payload = {
    schema = "dotfiles.notification-action.v1",
    action = "open-agent-task",
    servername = vim.v.servername,
    ["session-id"] = session_id,
  }
  local icon = state == "awaiting_choice" and "dialog-question" or "utilities-terminal"
  local urgency = state == "awaiting_choice" and "normal" or "low"
  vim.system({
    NOTIFICATION_ACTION_BIN,
    "send",
    "--summary",
    notification_summary(task, state),
    "--body",
    notification_body(task, state),
    "--label",
    "Open agent",
    "--timeout-ms",
    state == "awaiting_choice" and "12000" or "7000",
    "--app-name",
    "agent-master-task",
    "--category",
    "dev.agent.master",
    "--urgency",
    urgency,
    "--icon",
    icon,
    vim.json.encode(payload),
  }, { detach = true })
end

---@type overseer.ComponentFileDefinition
return {
  desc = "Live agent state in the task list and notify when master agents stop working",
  constructor = function()
    ---Notify when a master/root agent leaves the working state. Sub-agents are
    ---intentionally quiet so delegated work does not spam the operator.
    ---@param task overseer.Task
    ---@param agent_tasks table
    ---@param previous string?
    ---@param state string
    local function notify_master_left_working(task, agent_tasks, previous, state)
      if previous ~= "running" or state == "running" then return end
      if type(agent_tasks.task_role) == "function" and agent_tasks.task_role(task) ~= "master" then return end

      local name = type(task.name) == "string" and task.name ~= "" and task.name or ("task " .. tostring(task.id))
      send_system_notification(task, state)
      if type(vim.notify) == "function" and vim.fn.executable(NOTIFICATION_ACTION_BIN) ~= 1 then
        vim.notify(
          ("%s is %s"):format(name, state_label(state)),
          state == "awaiting_choice" and vim.log.levels.WARN or vim.log.levels.INFO,
          { title = "Agent master task" }
        )
      end
    end

    ---Reclassify from the live buffer tail; update metadata + repaint on change.
    ---@param self table
    ---@param task overseer.Task
    local function reclassify(self, task)
      local ok, agent_tasks = pcall(require, "serranomorante.plugins.jobs.agent_tasks")
      if not ok or type(agent_tasks.task_state) ~= "function" then return end
      local state = agent_tasks.task_state(task)
      if state and state ~= self._last then
        local previous = self._last
        self._last = state
        task.metadata = task.metadata or {}
        task.metadata.agent_state = state
        notify_master_left_working(task, agent_tasks, previous, state)
        -- Re-render the row in place (no re-sort). Guarded: the list may be closed.
        pcall(function() require("overseer.task_list").touch(task) end)
      end
    end

    ---Start the repeating poll once (idempotent). Survives both fresh starts
    ---(on_init) and retrofits (first on_output_lines).
    ---@param self table
    ---@param task overseer.Task
    local function ensure_timer(self, task)
      if self._timer then return end
      local uv = vim.uv or vim.loop
      if not uv then return end
      self._timer = uv.new_timer()
      if not self._timer then return end
      self._timer:start(POLL_MS, POLL_MS, function()
        vim.schedule(function()
          -- Stop polling if the task's terminal buffer is gone.
          local bufnr = task.get_bufnr and task:get_bufnr() or nil
          if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end
          reclassify(self, task)
        end)
      end)
    end

    ---@param self table
    local function stop_timer(self)
      if self._timer then
        pcall(function()
          self._timer:stop()
          self._timer:close()
        end)
        self._timer = nil
      end
    end

    return {
      _last = nil,
      _timer = nil,
      ---@param self table
      ---@param task overseer.Task
      on_init = function(self, task) ensure_timer(self, task) end,
      ---@param self table
      ---@param task overseer.Task
      on_output_lines = function(self, task, _lines)
        ensure_timer(self, task)
        reclassify(self, task)
      end,
      ---@param self table
      on_dispose = function(self) stop_timer(self) end,
    }
  end,
}
