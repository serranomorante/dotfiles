-- Purpose: Prefix the left side of the current window's statusline with a
-- compact terminal-mode indicator while that window shows a native terminal
-- buffer. The prefix is the mode chip: "NORMAL" (accent) when keys go to Neovim
-- instead of the shell, switching to "TERMINAL" (muted) once you press `i` and
-- type into the terminal. When the buffer belongs to an Overseer task it also
-- shows the live task state and elapsed time while the task runs; agent
-- sessions surface their derived state (working / needs input / idle).
-- Names/titles are intentionally left out: the rest of the statusline keeps
-- showing them untouched.
--
-- The rest of the statusline is preserved verbatim: the window-local
-- 'statusline' is the global/default string with only this prefix prepended,
-- and the override exists solely while the terminal window is current. Non
-- terminal windows and inactive terminal windows always fall back to the plain
-- global statusline, so no extra row is added and the child pty is never
-- resized.
--
-- A single 1s timer keeps the running duration and agent state live while the
-- current window is a running task terminal; it stops as soon as the window
-- stops qualifying, mirroring the bounded timer already used by agent_watch.

local M = {}

local utils = require("serranomorante.utils")

local NORMAL_HL = "CustomTerminalModeNormal"
local TERMINAL_HL = "CustomTerminalModeInsert"
local DIM_HL = "CustomTerminalDim"
local ACTIVE_HL = "CustomTerminalStatusActive"
local OK_HL = "CustomTerminalStatusOk"
local WARN_HL = "CustomTerminalStatusWarn"
local ERR_HL = "CustomTerminalStatusErr"

local NORMAL_LABEL = "NORMAL"
local TERMINAL_LABEL = "TERMINAL"

local TICK_MS = 1000

---Overseer's RUNNING status; falls back to the plain literal when the plugin
---is not loadable (e.g. headless unit tests).
local OVERSEER_RUNNING = "RUNNING"
do
  local ok, constants = pcall(require, "overseer.constants")
  if ok and type(constants) == "table" and type(constants.STATUS) == "table" then
    if type(constants.STATUS.RUNNING) == "string" then OVERSEER_RUNNING = constants.STATUS.RUNNING end
  end
end

local augroup = vim.api.nvim_create_augroup("serranomorante_terminal_statusline", { clear = true })

---Window id currently carrying the prefixed statusline (nil when none).
---@type integer?
local active_win = nil

---Overseer task bound to the active window's buffer (nil for plain terminals).
---@type table?
local active_task = nil

---Run start timestamps (ms) keyed by task id.
---@type table<integer, number>
local task_anchors = {}

local ticker = nil

---Forward declaration: assigned below after ensure_ticker is in scope.
local tick

---@return number ms
local function now_ms() return (vim.uv or vim.loop).hrtime() / 1000000 end

---The untouched statusline that non-terminal windows use.
---@return string
local function baseline_statusline() return vim.api.nvim_get_option_value("statusline", { scope = "global" }) end

local function mode_content()
  return vim.fn.mode():sub(1, 1) ~= "t" and ("%%#%s# %s %%*"):format(NORMAL_HL, NORMAL_LABEL)
    or ("%%#%s# %s %%*"):format(TERMINAL_HL, TERMINAL_LABEL)
end

---@param winid integer
---@return boolean
local function is_regular_window(winid)
  return vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_config(winid).relative == ""
end

---Set (or clear, when content is nil) the window-local statusline override.
---@param winid integer
---@param content string?
local function set_statusline(winid, content)
  local current = vim.wo[winid].statusline
  local next_value = content or ""
  if current ~= next_value then vim.wo[winid].statusline = next_value end
end

---@param task overseer.Task
---@return boolean
local function task_running(task) return type(task) == "table" and task.status == OVERSEER_RUNNING end

local TASK_STATUS_WORDS = {
  RUNNING = { text = "running", hl = ACTIVE_HL },
  SUCCESS = { text = "done", hl = OK_HL },
  FAILURE = { text = "failed", hl = ERR_HL },
  CANCELED = { text = "canceled", hl = DIM_HL },
}

local AGENT_STATE_WORDS = {
  awaiting_choice = { text = "needs input", hl = WARN_HL },
  idle = { text = "idle", hl = DIM_HL },
  running = { text = "working", hl = ACTIVE_HL },
}

---@param task overseer.Task
---@return boolean
local function is_agent_task(task)
  local metadata = type(task) == "table" and task.metadata or {}
  return type(metadata.agent_provider) == "string" and metadata.agent_provider ~= ""
end

---@param task overseer.Task
---@param metadata table
---@return { text: string, hl: string }?
local function task_state_word(task, metadata)
  if is_agent_task(task) then
    local agent_state = metadata.agent_state
    if type(agent_state) == "string" then return AGENT_STATE_WORDS[agent_state] end
  end
  return TASK_STATUS_WORDS[task.status]
end

---@param task overseer.Task
---@return string?
local function task_duration(task)
  if not task_running(task) then return nil end
  local id = task.id
  if type(id) ~= "number" then return nil end
  local anchor = task_anchors[id]
  local now = now_ms()
  if type(anchor) ~= "number" then
    task_anchors[id] = now
    return "0:00"
  end
  local seconds = math.floor((now - anchor) / 1000)
  return ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
end

---Statusline prefix for the current task context, ending before the baseline.
---@return string
local function prefix_content()
  local parts = { mode_content() }
  local task = active_task
  if task then
    local metadata = type(task.metadata) == "table" and task.metadata or {}
    local state = task_state_word(task, metadata)
    local duration = task_duration(task)
    if state then parts[#parts + 1] = ("%%#%s# %s"):format(state.hl, state.text) end
    if duration then parts[#parts + 1] = ("%%#%s# · %s"):format(DIM_HL, duration) end
  end
  return table.concat(parts, " ")
end

---Full statusline for a current terminal window: our prefix + the plain
---statusline, so the normal content is preserved verbatim.
---@return string
local function statusline_content() return prefix_content() .. " " .. baseline_statusline() end

local function ensure_ticker(running)
  if running then
    if not ticker then
      local loop = vim.uv or vim.loop
      if type(loop.new_timer) ~= "function" then return end
      ticker = loop.new_timer()
    end
    if not ticker:is_active() then ticker:start(TICK_MS, TICK_MS, vim.schedule_wrap(tick)) end
  elseif ticker and ticker:is_active() then
    ticker:stop()
  end
end

tick = function()
  local ok = pcall(function()
    if not active_win or not vim.api.nvim_win_is_valid(active_win) then
      ensure_ticker(false)
      return
    end
    if not task_running(active_task) then
      set_statusline(active_win, statusline_content())
      ensure_ticker(false)
      return
    end
    set_statusline(active_win, statusline_content())
  end)
  if not ok then ensure_ticker(false) end
end

local function refresh_impl()
  local winid = vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(winid) then
    if active_win and vim.api.nvim_win_is_valid(active_win) then set_statusline(active_win, nil) end
    active_win = nil
    active_task = nil
    ensure_ticker(false)
    return
  end

  local bufnr = vim.api.nvim_win_get_buf(winid)
  local eligible = utils.is_terminal_buffer(bufnr) and is_regular_window(winid)

  if eligible then
    if active_win and active_win ~= winid and vim.api.nvim_win_is_valid(active_win) then
      set_statusline(active_win, nil)
    end
    active_win = winid
    local ok, task = pcall(utils.overseer_task_for_buf, bufnr)
    if not ok then task = nil end
    active_task = task
    if task and not task_running(task) and type(task.id) == "number" then task_anchors[task.id] = nil end
    set_statusline(winid, statusline_content())
    ensure_ticker(task_running(active_task))
  else
    if active_win and vim.api.nvim_win_is_valid(active_win) then set_statusline(active_win, nil) end
    active_win = nil
    active_task = nil
    ensure_ticker(false)
  end
end

---Autocmd entrypoint: never let an error escape into the caller's flow.
local function refresh() pcall(refresh_impl) end

local function on_win_closed(args)
  pcall(function()
    local winid = vim.v.event.win or args.win
    if type(winid) ~= "number" then return end
    if active_win == winid then active_win = nil end
    refresh_impl()
  end)
end

function M.setup()
  vim.api.nvim_create_autocmd({ "WinEnter", "WinNew", "BufEnter", "BufWinEnter", "TabEnter", "TermOpen" }, {
    desc = "Keep the terminal statusline prefix in sync with window changes",
    group = augroup,
    callback = refresh,
  })

  vim.api.nvim_create_autocmd("WinClosed", {
    desc = "Drop terminal statusline prefix state for closed windows",
    group = augroup,
    callback = on_win_closed,
  })

  vim.api.nvim_create_autocmd("ModeChanged", {
    desc = "Toggle the terminal statusline prefix on mode changes",
    group = augroup,
    pattern = "*:*",
    callback = refresh,
  })

  vim.api.nvim_create_autocmd({ "TermEnter", "TermLeave", "InsertEnter", "InsertLeave" }, {
    desc = "Toggle the terminal statusline prefix around terminal mode",
    group = augroup,
    callback = refresh,
  })
end

return M
