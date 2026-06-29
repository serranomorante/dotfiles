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

---@type overseer.ComponentFileDefinition
return {
  desc = "Live agent state (running/awaiting_choice/idle) in the task list",
  constructor = function()
    ---Reclassify from the live buffer tail; update metadata + repaint on change.
    ---@param self table
    ---@param task overseer.Task
    local function reclassify(self, task)
      local ok, agent_tasks = pcall(require, "serranomorante.plugins.jobs.agent_tasks")
      if not ok or type(agent_tasks.task_state) ~= "function" then return end
      local state = agent_tasks.task_state(task)
      if state and state ~= self._last then
        self._last = state
        task.metadata = task.metadata or {}
        task.metadata.agent_state = state
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
      self._timer:start(
        POLL_MS,
        POLL_MS,
        function()
          vim.schedule(function()
            -- Stop polling if the task's terminal buffer is gone.
            local bufnr = task.get_bufnr and task:get_bufnr() or nil
            if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end
            reclassify(self, task)
          end)
        end
      )
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
