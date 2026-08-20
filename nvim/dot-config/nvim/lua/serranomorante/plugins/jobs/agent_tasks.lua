-- ============================================================================
-- agent_tasks - orchestration helpers for sibling agent Overseer tasks.
--
-- This module lets one agent task inspect and steer other agent tasks running
-- under the same Neovim socket: list status, read terminal output, type input,
-- resume stored sessions, and spawn new provider-backed sessions.
--
-- Public functions intentionally return plain strings or JSON so they can be
-- called over Neovim RPC from the agent-tasks shell wrapper.
-- ============================================================================

local M = {}

local PROVIDER_KEY = "agent_provider"
local SESSION_ID_KEY = "agent_session_id"
-- Orchestration role metadata. Only "sub" is ever stored; the ABSENCE of the key
-- means the task is a top-level ("master"/root) agent. This is the single source
-- of truth the render, the roster JSON and the tabpage buffer name all consult so
-- a sub-agent is recognizable everywhere its task title/name shows up.
local ROLE_KEY = "agent_role"
local ROLE_SUB = "sub"
local ROLE_MASTER = "master"
local UNFIREJAILED_KEY = "agent_unfirejailed"
local PROMPT_MARKERS = {
  codex = "›",
  claude = "❯",
  gemini = "❯",
}
local LEGACY_ASCII_PROMPT_MARKER = "> "
local PROMPT_DECORATION_CHARS = "│>❯›·*"
local TMUX_SESSION_NAME_METADATA = "agent_tmux_session_name"

local DEFAULT_READ_LINES = 80
local resize_autocmd_generation = 0

---@return table<string, table>
local function providers()
  local ok, agent_sessions = pcall(require, "serranomorante.plugins.jobs.agent_sessions")
  if not ok or type(agent_sessions.providers) ~= "table" then return {} end
  return agent_sessions.providers
end

---@return string[]
local function provider_names()
  local names = {}
  for name in pairs(providers()) do
    table.insert(names, name)
  end
  table.sort(names, function(a, b) return #a > #b end)
  return names
end

---@param name string
---@return table?
local function provider_by_name(name)
  local provider = providers()[name]
  return provider
end

---@return table[]
local function store_providers()
  local items = {}
  for _, provider in pairs(providers()) do
    if type(provider.name) == "string" and type(provider.sessions_dir) == "string" then
      table.insert(items, { name = provider.name, root = provider.sessions_dir })
    end
  end
  table.sort(items, function(a, b) return a.name < b.name end)
  return items
end

---@return overseer.Task[]
local function list_tasks()
  local ok, overseer = pcall(require, "overseer")
  if not ok then return {} end
  local lok, tasks = pcall(overseer.list_tasks)
  if not lok or type(tasks) ~= "table" then return {} end
  return tasks
end

---@param t overseer.Task
---@return string?
local function task_provider(t)
  local md = t.metadata or {}
  return md[PROVIDER_KEY]
end

---@param t overseer.Task
---@return string?
local function task_session_id(t)
  local md = t.metadata or {}
  return md[SESSION_ID_KEY]
end

---@param t overseer.Task
---@return string?
local function task_tmux_session_name(t)
  local md = t.metadata or {}
  if type(md[TMUX_SESSION_NAME_METADATA]) == "string" and md[TMUX_SESSION_NAME_METADATA] ~= "" then
    return md[TMUX_SESSION_NAME_METADATA]
  end

  local ok, target = pcall(function() return require("serranomorante.utils").agent_task_tmux_target(t) end)
  if ok and type(target) == "string" and target ~= "" then return target end
end

---@param provider string?
---@param tmux_session_name string?
---@return string?
local function session_id_from_tmux_session_name(provider, tmux_session_name)
  if type(provider) ~= "string" or provider == "" then return nil end
  if type(tmux_session_name) ~= "string" or tmux_session_name == "" then return nil end

  local sub_prefix = provider .. "-sub-"
  if tmux_session_name:sub(1, #sub_prefix) == sub_prefix then
    local session_id = tmux_session_name:sub(#sub_prefix + 1)
    if session_id ~= "" and not session_id:match("^pending%-") then return session_id end
    return nil
  end

  local master_prefix = provider .. "-"
  if tmux_session_name:sub(1, #master_prefix) == master_prefix then
    local session_id = tmux_session_name:sub(#master_prefix + 1)
    if session_id ~= "" and not session_id:match("^pending%-") then return session_id end
  end
end

---Orchestration role of a task. Defaults to "master" when unmarked so every
---pre-existing / top-level agent reads as master/root without needing a stamp.
---@param t overseer.Task
---@return string  -- "sub" | "master"
local function task_role(t)
  local md = t.metadata or {}
  return md[ROLE_KEY] == ROLE_SUB and ROLE_SUB or ROLE_MASTER
end

---@param t overseer.Task
---@return boolean
local function task_unfirejailed(t)
  local md = t.metadata or {}
  return md[UNFIREJAILED_KEY] == true
end

---Short uppercase badge for a role, for name/title listings.
---@param role string
---@return string
local function role_badge(role) return role == ROLE_SUB and "SUB" or "MASTER" end

---@param provider_name string?
---@param session_id string?
---@return string?
local function short_session_id(provider_name, session_id)
  if type(session_id) ~= "string" or session_id == "" then return nil end
  local id = session_id
  if provider_name == "opencode" then id = id:gsub("^ses_", "") end
  return id:sub(1, 6)
end

---@param t overseer.Task
---@return string
local function task_display_name(t)
  local ok, agent_sessions = pcall(require, "serranomorante.plugins.jobs.agent_sessions")
  if ok and type(agent_sessions.apply_task_display_name) == "function" then
    local name = agent_sessions.apply_task_display_name(t)
    if type(name) == "string" and name ~= "" then return name end
  end
  return type(t.name) == "string" and t.name or ""
end

---@param provider string?
---@return string[]
local function prompt_markers_for_provider(provider)
  local marker = type(provider) == "string" and PROMPT_MARKERS[provider] or nil
  if marker then return { marker } end

  local markers = { LEGACY_ASCII_PROMPT_MARKER }
  local seen = { [LEGACY_ASCII_PROMPT_MARKER] = true }
  for _, value in pairs(PROMPT_MARKERS) do
    if not seen[value] then
      table.insert(markers, value)
      seen[value] = true
    end
  end
  return markers
end

---@param provider string?
---@param line string
---@return boolean
local function line_has_prompt_marker(provider, line)
  for _, marker in ipairs(prompt_markers_for_provider(provider)) do
    if line:find(marker, 1, true) then return true end
  end
  return false
end

---@param t overseer.Task
---@return integer?
local function task_job_id(t)
  ---@diagnostic disable-next-line: invisible
  local strategy = t.strategy
  return t.job_id or (strategy and strategy.job_id) or nil
end

---@param t overseer.Task
---@return string[]?
local function task_buffer_lines(t)
  local ok, bufnr = pcall(function() return t:get_bufnr() end)
  if not ok or not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return nil end
  return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

---Best-effort agent state from a terminal tail.
---@param provider string?
---@param lines string[]?
---@return string
local function detect_state(provider, lines)
  if type(lines) ~= "table" or #lines == 0 then return "unknown" end
  local from = math.max(1, #lines - 25)
  local tail = table.concat(vim.list_slice(lines, from, #lines), "\n")
  if tail:find("esc to interrupt", 1, true) then return "busy" end
  for _, marker in ipairs(prompt_markers_for_provider(provider)) do
    if tail:find(marker, 1, true) then return "idle" end
  end
  return "unknown"
end

---Resolve a task by exact session id, Overseer numeric id, unique session id
---prefix, or unique case-insensitive name substring.
---@param ref string
---@return overseer.Task? task
---@return string? err
local function resolve_task(ref)
  if type(ref) ~= "string" or ref == "" then return nil, "missing task ref" end
  local tasks = list_tasks()

  for _, t in ipairs(tasks) do
    if task_session_id(t) == ref then return t end
  end

  if ref:match("^%d+$") then
    for _, t in ipairs(tasks) do
      if tostring(t.id) == ref then return t end
    end
  end

  local prefix = {}
  for _, t in ipairs(tasks) do
    local sid = task_session_id(t)
    if sid and sid:sub(1, #ref) == ref then table.insert(prefix, t) end
  end
  if #prefix == 1 then return prefix[1] end
  if #prefix > 1 then return nil, ("ambiguous ref '%s' matches %d session ids"):format(ref, #prefix) end

  local low = ref:lower()
  local named = {}
  for _, t in ipairs(tasks) do
    if type(t.name) == "string" and t.name:lower():find(low, 1, true) then table.insert(named, t) end
  end
  if #named == 1 then return named[1] end
  if #named > 1 then return nil, ("ambiguous ref '%s' matches %d task names"):format(ref, #named) end

  return nil, ("no task matches '%s'"):format(ref)
end

---@param t overseer.Task
---@return table
local function task_summary(t)
  local lines = task_buffer_lines(t)
  return {
    id = t.id,
    status = tostring(t.status),
    provider = task_provider(t),
    session_id = task_session_id(t),
    session_short_id = short_session_id(task_provider(t), task_session_id(t)),
    name = task_display_name(t),
    role = task_role(t),
    unfirejailed = task_unfirejailed(t),
    state = detect_state(task_provider(t), lines),
  }
end

-- ---------------------------------------------------------------------------
-- Public RPC API
-- ---------------------------------------------------------------------------

---JSON roster of agent tasks and best-effort state.
---@return string
function M.list_json()
  local tasks = {}
  for _, t in ipairs(list_tasks()) do
    table.insert(tasks, task_summary(t))
  end
  return vim.json.encode({ version = 1, count = #tasks, tasks = tasks })
end

---Terminal tail for a task with a small metadata header.
---@param ref string
---@param n? integer|string
---@return string
function M.read(ref, n)
  local t, err = resolve_task(ref)
  if not t then return "ERROR: " .. tostring(err) end
  n = tonumber(n) or DEFAULT_READ_LINES
  local lines = task_buffer_lines(t)
  if not lines then return "ERROR: task has no valid terminal buffer" end
  while #lines > 0 and lines[#lines]:match("^%s*$") do
    table.remove(lines)
  end
  local total = #lines
  local start = math.max(1, total - n + 1)
  local header = ("# task id=%s session=%s provider=%s role=%s%s state=%s status=%s\n# lines %d-%d of %d"):format(
    tostring(t.id),
    short_session_id(task_provider(t), task_session_id(t)) or "-",
    tostring(task_provider(t)),
    task_role(t),
    task_unfirejailed(t) and " unfirejailed" or "",
    detect_state(task_provider(t), lines),
    tostring(t.status),
    start,
    total,
    total
  )
  return header .. "\n" .. table.concat(vim.list_slice(lines, start, total), "\n")
end

---Type text into an agent task through nvim_chan_send.
---`with_newline` sends '\r' to the terminal input; the receiving TUI decides
---whether that inserts a line break or submits.
---@param ref string
---@param b64_text string base64 del texto (evita problemas de quoting vía RPC)
---@param with_newline? boolean|string|integer
---@return string json
function M.send(ref, b64_text, with_newline)
  local t, err = resolve_task(ref)
  if not t then return vim.json.encode({ ok = false, error = err }) end
  local job = task_job_id(t)
  if not job then return vim.json.encode({ ok = false, error = "task has no job/channel id" }) end

  -- Tmux copy-mode guard: for tmux-backed agent tasks the terminal channel points at
  -- the tmux client, so if the pane is in copy-mode (e.g. after scrollback navigation)
  -- a bracketed paste is intercepted by tmux and never reaches the agent TUI. Cancel
  -- copy-mode first so the paste lands. Mirrors leave_tmux_copy_mode_before_paste from
  -- the visual-paste path (commit 7176ef8ce). No-op for non-tmux tasks / when not in mode.
  do
    local u = require("serranomorante.utils")
    local target = u.agent_task_tmux_target(t)
    if target and u.tmux_pane_in_mode(u.agent_tmux_server_name(), target) then
      u.run_tmux_command(u.agent_tmux_server_name(), { "send-keys", "-t", target, "-X", "cancel" })
    end
  end

  local text = ""
  if type(b64_text) == "string" and b64_text ~= "" then
    if type(vim.base64) ~= "table" then
      return vim.json.encode({ ok = false, error = "vim.base64 unavailable (needs Neovim >= 0.10)" })
    end
    local dok, decoded = pcall(vim.base64.decode, b64_text)
    if not dok then return vim.json.encode({ ok = false, error = "invalid base64 payload" }) end
    text = decoded
  end

  local newline = with_newline == true or with_newline == "true" or with_newline == "1" or with_newline == 1
  local ok_text
  if newline and text ~= "" then
    -- Submit GUARANTEE: a multi-line paste must reach the TUI atomically — a raw
    -- '\r' embedded mid-text submits early or gets swallowed (the recurring
    -- "prompt never got sent" bug). So wrap the text in a bracketed paste
    -- (\27[200~ … \27[201~) and fire the submit '\r' SEPARATELY and DEFERRED,
    -- once the TUI has ingested the paste. vim.defer_fn SCHEDULES the Enter
    -- without blocking the editor (no vim.wait → your Neovim stays interactive).
    ok_text = pcall(vim.api.nvim_chan_send, job, "\27[200~" .. text .. "\27[201~")
    vim.defer_fn(function() pcall(vim.api.nvim_chan_send, job, "\r") end, 250)
  elseif newline then
    -- bare Enter: submit whatever is already in the input box (e.g. a leftover paste)
    ok_text = pcall(vim.api.nvim_chan_send, job, "\r")
  else
    -- type only, no submit
    ok_text = pcall(vim.api.nvim_chan_send, job, text)
  end

  return vim.json.encode({
    ok = ok_text,
    id = t.id,
    session_id = task_session_id(t),
    job = job,
    bytes = #text,
    newline = newline,
    bracketed_paste = (newline and text ~= "") or nil,
  })
end

---Status for one task, or the full roster when ref is empty.
---@param ref? string
---@return string json
function M.status(ref)
  if type(ref) == "string" and ref ~= "" then
    local t, err = resolve_task(ref)
    if not t then return vim.json.encode({ ok = false, error = err }) end
    local summary = task_summary(t)
    summary.ok = true
    return vim.json.encode(summary)
  end
  return M.list_json()
end

---Classify what a TUI agent is doing from its terminal tail. Pure + instant
---(no blocking) so `state`/`wait` never freeze Neovim.
---@param provider string?
---@param lines string[]?
---@return string state  -- "running"|"awaiting_choice"|"idle"|"unknown"
---@return table options -- [{n=integer,label=string}] when awaiting_choice
local function classify_state(provider, lines)
  if type(lines) ~= "table" or #lines == 0 then return "unknown", {} end
  local from = math.max(1, #lines - 30)
  local tail_lines = vim.list_slice(lines, from, #lines)
  local tail = table.concat(tail_lines, "\n")

  local latest_busy = nil
  local latest_prompt = nil
  local latest_choice = nil

  -- AWAITING A CHOICE: a numbered selection menu is open. Parse the options so
  -- the caller knows exactly what to pick (→ `choose <n>`).
  local is_choice = tail:find("Enter to select", 1, true) ~= nil
    or tail:find("to navigate", 1, true) ~= nil
    or tail:find("to select", 1, true) ~= nil
  local options = {}
  for idx, ln in ipairs(tail_lines) do
    if ln:find("esc to interrupt", 1, true) then latest_busy = idx end
    if line_has_prompt_marker(provider, ln) then latest_prompt = idx end
    if ln:find("Enter to select", 1, true) or ln:find("to navigate", 1, true) or ln:find("to select", 1, true) then
      latest_choice = idx
    end
    -- Strip leading box-drawing/marker decoration, then parse "N. label".
    local num, label = ln:match(("^[%%s%s]*(%%d+)%%.%%s+(.+)$"):format(PROMPT_DECORATION_CHARS))
    if num and label then
      label = label:gsub("%s+$", "")
      table.insert(options, { n = tonumber(num), label = label })
      latest_choice = idx
    end
  end
  if
    #options >= 2
    and latest_choice
    and latest_choice >= (latest_prompt or 0)
    and latest_choice >= (latest_busy or 0)
    and (is_choice or latest_prompt)
  then
    return "awaiting_choice", options
  end

  -- BUSY: the agent is working (spinner shows the interrupt hint). The tail may
  -- still contain an older busy hint after the TUI has returned to the prompt, so
  -- only trust it when it is newer than the last prompt/choice signal.
  if latest_busy and latest_busy > (latest_prompt or 0) and latest_busy > (latest_choice or 0) then
    return "running", {}
  end

  -- IDLE: a prompt marker is present and nothing is running → ready for input
  -- (a free-text question from the agent also lands here; read `tail` to see it).
  if latest_prompt then return "idle", {} end
  return "unknown", {}
end

---Instant, non-blocking classification of an agent's current state + the tail
---of its output (and parsed menu options when it's awaiting a choice). This is
---the ONLY nvim-facing call `wait` uses; the wait LOOP lives in the shell so
---Neovim is never blocked.
---@param ref string
---@return string json
function M.state(ref)
  local t, err = resolve_task(ref)
  if not t then return vim.json.encode({ ok = false, error = err }) end
  local lines = task_buffer_lines(t)
  local provider = task_provider(t)
  local state, options = classify_state(provider, lines)
  local tail = ""
  if type(lines) == "table" then
    local trimmed = vim.deepcopy(lines)
    while #trimmed > 0 and trimmed[#trimmed]:match("^%s*$") do
      table.remove(trimmed)
    end
    tail = table.concat(vim.list_slice(trimmed, math.max(1, #trimmed - 8), #trimmed), "\n")
  end
  return vim.json.encode({
    ok = true,
    id = t.id,
    session_id = task_session_id(t),
    provider = provider,
    role = task_role(t),
    unfirejailed = task_unfirejailed(t),
    state = state,
    options = options,
    tail = tail,
  })
end

---Select option <n> in an agent's numbered selection menu. Types the digit then
---submits with a DEFERRED Enter (non-blocking). Fixes "I sent a choice but it
---never registered".
---@param ref string
---@param n integer|string
---@return string json
function M.choose(ref, n)
  local t, err = resolve_task(ref)
  if not t then return vim.json.encode({ ok = false, error = err }) end
  local job = task_job_id(t)
  if not job then return vim.json.encode({ ok = false, error = "task has no job/channel id" }) end
  local num = tonumber(n)
  if not num then return vim.json.encode({ ok = false, error = "choice must be a number" }) end
  pcall(vim.api.nvim_chan_send, job, tostring(num))
  vim.defer_fn(function() pcall(vim.api.nvim_chan_send, job, "\r") end, 200)
  return vim.json.encode({ ok = true, id = t.id, session_id = task_session_id(t), chose = num })
end

---Classify an agent task DIRECTLY (no ref resolution). Used by the task_list
---render function and the agent_watch component. Cheap + non-blocking.
---@param task overseer.Task
---@return string state  -- "running"|"awaiting_choice"|"idle"|"unknown"
function M.task_state(task)
  if type(task) ~= "table" then return "unknown" end
  local state = classify_state(task_provider(task), task_buffer_lines(task))
  return state
end

---Orchestration role of a task DIRECTLY (no ref resolution). Used by the
---task_list render to badge master vs sub agents. Defaults to "master".
---@param task overseer.Task
---@return string  -- "sub" | "master"
function M.task_role(task)
  if type(task) ~= "table" then return ROLE_MASTER end
  return task_role(task)
end

---Whether an agent task was intentionally launched outside the Firejail sandbox.
---@param task overseer.Task
---@return boolean
function M.task_unfirejailed(task)
  if type(task) ~= "table" then return false end
  return task_unfirejailed(task)
end

local AGENT_WATCH_COMPONENT = "serranomorante.agent_watch"

---Attach the agent_watch component (live state in the task list) to one agent task.
---@param ref string
---@return string json
function M.attach_watch(ref)
  local t, err = resolve_task(ref)
  if not t then return vim.json.encode({ ok = false, error = err }) end
  if not t:has_component(AGENT_WATCH_COMPONENT) then pcall(function() t:add_component(AGENT_WATCH_COMPONENT) end) end
  return vim.json.encode({ ok = true, id = t.id, session_id = task_session_id(t), attached = AGENT_WATCH_COMPONENT })
end

---Attach agent_watch to ALL current agent tasks (retrofit already-running children
---so the task list reflects their live state without recreating them).
---@return string json
function M.attach_watch_all()
  local n = 0
  for _, t in ipairs(list_tasks()) do
    if task_provider(t) and not t:has_component(AGENT_WATCH_COMPONENT) then
      local ok = pcall(function() t:add_component(AGENT_WATCH_COMPONENT) end)
      if ok then n = n + 1 end
    end
  end
  return vim.json.encode({ ok = true, attached = n })
end

---Resolve agent-session-store in the same order used by agent_sessions.lua.
---@return string?
local function store_bin()
  local env = vim.env.AGENT_SESSION_STORE_BIN
  if env and env ~= "" and vim.fn.executable(env) == 1 then return env end
  local repo = vim.fn.expand("~/dotfiles/utilities/bin/agent-session-store")
  if vim.fn.executable(repo) == 1 then return repo end
  if vim.fn.executable("agent-session-store") == 1 then return "agent-session-store" end
  return nil
end

---Known session ids for the current cwd across all configured providers.
---@return string[]?
local function known_session_ids()
  local bin = store_bin()
  if not bin then return nil end
  local cwd = vim.fn.getcwd()
  local ids, seen, any_ok = {}, {}, false
  for _, p in ipairs(store_providers()) do
    local out = vim.fn.system({ bin, "--provider", p.name, "--root", p.root, "ids", cwd })
    if vim.v.shell_error == 0 and out ~= "" then
      local ok, decoded = pcall(vim.json.decode, out)
      if ok and type(decoded) == "table" and type(decoded.ids) == "table" then
        any_ok = true
        for _, id in ipairs(decoded.ids) do
          if type(id) == "string" and not seen[id] then
            seen[id] = true
            table.insert(ids, id)
          end
        end
      end
    end
  end
  if not any_ok then return nil end
  return ids
end

---Resolve a full session id or unique prefix against known ids.
---@param ref string
---@param known string[]
---@return string? full_id
---@return string? err  -- "ambiguous" | "not_found"
local function resolve_session_ref(ref, known)
  for _, id in ipairs(known) do
    if id == ref then return id end
  end
  local matches = {}
  for _, id in ipairs(known) do
    if id:sub(1, #ref) == ref then table.insert(matches, id) end
  end
  if #matches == 1 then return matches[1] end
  if #matches > 1 then return nil, "ambiguous" end
  return nil, "not_found"
end

---@param provider string
---@param name string
---@return table?
local function parse_tmux_agent_session(provider, name)
  local sub_prefix = provider .. "-sub-"
  if name:sub(1, #sub_prefix) == sub_prefix then
    local session_id = name:sub(#sub_prefix + 1)
    if session_id ~= "" and not session_id:match("^pending%-") then
      return { provider = provider, role = ROLE_SUB, session_id = session_id, tmux_session_name = name }
    end
    return nil
  end

  local master_prefix = provider .. "-"
  if name:sub(1, #master_prefix) == master_prefix then
    local session_id = name:sub(#master_prefix + 1)
    if session_id ~= "" and not session_id:match("^pending%-") then
      return { provider = provider, role = ROLE_MASTER, session_id = session_id, tmux_session_name = name }
    end
  end
end

---@return table[]?
---@return string?
local function tmux_agent_sessions()
  if vim.fn.executable("tmux") ~= 1 then return nil, "tmux executable not found" end

  local ok_utils, utils = pcall(require, "serranomorante.utils")
  if not ok_utils then return nil, "serranomorante.utils unavailable" end

  local server_name = utils.agent_tmux_server_name()
  utils.ensure_agent_tmux_socket_dirs(server_name)
  local out = vim.fn.system({ "tmux", "-L", server_name, "list-sessions", "-F", "#{session_name}" })
  if vim.v.shell_error ~= 0 then
    local message = vim.trim(out or "")
    if message == "" then message = "tmux server has no sessions" end
    return {}, message
  end

  local sessions = {}
  for line in tostring(out):gmatch("[^\r\n]+") do
    local name = vim.trim(line)
    for _, provider in ipairs(provider_names()) do
      local session = parse_tmux_agent_session(provider, name)
      if session then
        table.insert(sessions, session)
        break
      end
    end
  end

  table.sort(sessions, function(a, b) return a.tmux_session_name < b.tmux_session_name end)
  return sessions
end

---@return string[]?
---@return string?
local function tmux_agent_session_names()
  if vim.fn.executable("tmux") ~= 1 then return nil, "tmux executable not found" end

  local ok_utils, utils = pcall(require, "serranomorante.utils")
  if not ok_utils then return nil, "serranomorante.utils unavailable" end

  local server_name = utils.agent_tmux_server_name()
  utils.ensure_agent_tmux_socket_dirs(server_name)
  local out = vim.fn.system({ "tmux", "-L", server_name, "list-sessions", "-F", "#{session_name}" })
  if vim.v.shell_error ~= 0 then
    local message = vim.trim(out or "")
    if message == "" then message = "tmux server has no sessions" end
    return {}, message
  end

  local names = {}
  for line in tostring(out):gmatch("[^\r\n]+") do
    local name = vim.trim(line)
    for _, provider in ipairs(provider_names()) do
      if name:sub(1, #provider + 1) == provider .. "-" then
        table.insert(names, name)
        break
      end
    end
  end
  table.sort(names)
  return names
end

---@param name string
---@return boolean
local function is_pending_tmux_session_name(name)
  for _, provider in ipairs(provider_names()) do
    if name:sub(1, #provider + 9) == provider .. "-pending-" then return true end
    if name:sub(1, #provider + 13) == provider .. "-sub-pending-" then return true end
  end
  return false
end

---@param t overseer.Task
---@return { width: integer, height: integer }?
local function task_terminal_window_size(t)
  local bufnr = t.get_bufnr and t:get_bufnr() or nil
  if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then return nil end

  local current_win = vim.api.nvim_get_current_win()
  if vim.api.nvim_win_is_valid(current_win) and vim.api.nvim_win_get_buf(current_win) == bufnr then
    return {
      width = vim.api.nvim_win_get_width(current_win),
      height = vim.api.nvim_win_get_height(current_win),
    }
  end

  for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
    if vim.api.nvim_win_is_valid(winid) then
      return {
        width = vim.api.nvim_win_get_width(winid),
        height = vim.api.nvim_win_get_height(winid),
      }
    end
  end
end

---@return integer
local function tabline_height()
  if vim.o.showtabline == 2 then return 1 end
  if vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() > 1 then return 1 end
  return 0
end

---@return integer
local function statusline_height()
  if vim.o.laststatus == 0 then return 0 end
  if vim.o.laststatus == 1 and #vim.api.nvim_tabpage_list_wins(0) <= 1 then return 0 end
  return 1
end

---@return { width: integer, height: integer }
local function fallback_tmux_size()
  return {
    width = vim.o.columns,
    height = math.max(vim.o.lines - vim.o.cmdheight - tabline_height() - statusline_height(), 1),
  }
end

---@param session_name string
---@return overseer.Task?
local function task_for_tmux_session_name(session_name)
  for _, t in ipairs(list_tasks()) do
    if task_tmux_session_name(t) == session_name then return t end
  end
end

---@param session_name string?
---@return { width: integer, height: integer }
local function current_tmux_size(session_name)
  if type(session_name) == "string" and session_name ~= "" then
    local task = task_for_tmux_session_name(session_name)
    local size = task and task_terminal_window_size(task) or nil
    if size then return size end
  end

  return fallback_tmux_size()
end

---@param t overseer.Task
---@return integer?
local function task_terminal_job_id(t)
  local job_id = t.job_id or (t.strategy and t.strategy.job_id) or nil
  if type(job_id) == "number" and job_id ~= 0 then return job_id end

  local bufnr = t.get_bufnr and t:get_bufnr() or nil
  if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then return nil end
  job_id = vim.b[bufnr].terminal_job_id
  if type(job_id) == "number" and job_id ~= 0 then return job_id end

  local ok_channel, channel = pcall(vim.api.nvim_get_option_value, "channel", { buf = bufnr })
  if ok_channel and type(channel) == "number" and channel ~= 0 then return channel end

  for _, chan in ipairs(vim.api.nvim_list_chans()) do
    if chan.mode == "terminal" and (chan.buffer == bufnr or chan.buf == bufnr) then return chan.id end
  end
end

---@param t overseer.Task?
---@param size { width: integer, height: integer }
---@return boolean?
local function resize_task_terminal_job(t, size)
  if not t then return nil end
  local job_id = task_terminal_job_id(t)
  if not job_id then return nil end
  local ok = pcall(vim.fn.jobresize, job_id, size.width, size.height)
  return ok
end

---@param utils table
---@param session_name string
---@param size { width: integer, height: integer }
---@return boolean
local function resize_tmux_session_window(utils, session_name, size)
  if type(session_name) ~= "string" or session_name == "" then return false end
  if not size or size.width <= 0 or size.height <= 0 then return false end
  return utils.run_tmux_command(utils.agent_tmux_server_name(), {
    "resize-window",
    "-t",
    session_name,
    "-x",
    tostring(size.width),
    "-y",
    tostring(size.height),
  })
end

---@param utils table
---@param session_name string
---@param size { width: integer, height: integer }
---@return boolean
local function pulse_tmux_session_window(utils, session_name, size)
  local pulse_size = { width = size.width, height = size.height }
  if pulse_size.height > 1 then
    pulse_size.height = pulse_size.height - 1
  elseif pulse_size.width > 1 then
    pulse_size.width = pulse_size.width - 1
  end
  if pulse_size.width == size.width and pulse_size.height == size.height then return true end
  local pulse_ok = resize_tmux_session_window(utils, session_name, pulse_size)
  local restore_ok = resize_tmux_session_window(utils, session_name, size)
  return pulse_ok and restore_ok
end

---@param tmux_session table
---@param t overseer.Task
local function apply_tmux_session_metadata(tmux_session, t)
  t.metadata = t.metadata or {}
  t.metadata[TMUX_SESSION_NAME_METADATA] = tmux_session.tmux_session_name
  if tmux_session.role == ROLE_SUB then
    t.metadata[ROLE_KEY] = ROLE_SUB
  elseif tmux_session.role == ROLE_MASTER then
    t.metadata[ROLE_KEY] = nil
  end
end

---@param tmux_session table
---@return boolean
local function task_exists_for_tmux_session(tmux_session)
  for _, t in ipairs(list_tasks()) do
    if task_provider(t) == tmux_session.provider and task_session_id(t) == tmux_session.session_id then
      apply_tmux_session_metadata(tmux_session, t)
      return true
    end
    if task_tmux_session_name(t) == tmux_session.tmux_session_name then
      apply_tmux_session_metadata(tmux_session, t)
      return true
    end
  end
  return false
end

---@param session table
local function resume_tmux_session(session)
  local session_id = session.session_id
  local role = session.role
  vim.schedule(function()
    local ok_as, agent_sessions = pcall(require, "serranomorante.plugins.jobs.agent_sessions")
    if ok_as and type(agent_sessions.resume_by_id) == "function" then
      agent_sessions.resume_by_id(session_id, { role = role })
      return
    end

    pcall(vim.cmd, "AgentResumeById " .. session_id)
  end)
end

---Open existing sessions as Overseer tasks by id or unique id prefix.
---By default the ids are validated against the sessions known for the CURRENT
---cwd. Pass all=true to BYPASS that cwd filter (mirrors the `<leader>{p}L`
---"resume any session" picker): each id is resumed directly via AgentResumeById,
---which scans every provider's full session cache regardless of cwd. Use it to
---open child sessions that belong to another working directory (e.g. the
---frontend git worktrees), whose ids the cwd-scoped store would report as
---not_found.
---@param ids string comma/space separated session ids (unique prefixes allowed when cwd-scoped)
---@param all? boolean|string true / "true" / "1" → bypass the cwd filter
---@return string json
function M.open(ids, all)
  local bypass_cwd = all == true or all == "true" or all == "1" or all == 1
  local requested, opened, not_found, ambiguous = {}, {}, {}, {}
  -- known == nil drives the "resume by id directly, no cwd validation" branch:
  -- it happens either when the session store is unavailable OR when the caller
  -- explicitly asked to bypass the cwd filter (all=true).
  local known = (not bypass_cwd) and known_session_ids() or nil

  for id in tostring(ids):gmatch("[^,%s]+") do
    table.insert(requested, id)
    if known == nil then
      local target = id
      vim.schedule(function() pcall(vim.cmd, "AgentResumeById " .. target) end)
      table.insert(opened, id)
    else
      local full, err = resolve_session_ref(id, known)
      if full then
        table.insert(opened, full)
        vim.schedule(function() pcall(vim.cmd, "AgentResumeById " .. full) end)
      elseif err == "ambiguous" then
        table.insert(ambiguous, id)
      else
        table.insert(not_found, id)
      end
    end
  end

  if #requested == 0 then return vim.json.encode({ ok = false, error = "no session ids given" }) end

  local ok = (#not_found == 0 and #ambiguous == 0)
  local result = { ok = ok, requested = requested, opened = opened }
  if #not_found > 0 then result.not_found = not_found end
  if #ambiguous > 0 then result.ambiguous = ambiguous end
  if bypass_cwd then
    result.cwd_filter = "bypassed"
  elseif known == nil then
    result.warning = "session store unavailable; ids not validated"
  end
  if not ok then result.error = ("could not resolve %d of %d id(s)"):format(#not_found + #ambiguous, #requested) end
  return vim.json.encode(result)
end

---Reconcile persistent tmux-backed agent sessions with the current Overseer list.
---Live tmux sessions are authoritative for long-running terminals; missing
---Overseer tasks are reopened through agent_sessions.resume_by_id so the resume
---path stays shared while preserving role metadata parsed from the tmux name.
---@return string json
function M.reconcile()
  local tmux_sessions, warning = tmux_agent_sessions()
  if not tmux_sessions then return vim.json.encode({ ok = false, error = warning }) end

  local opened, existing = {}, {}
  for _, session in ipairs(tmux_sessions) do
    if task_exists_for_tmux_session(session) then
      table.insert(existing, session)
    else
      table.insert(opened, session)
      resume_tmux_session(session)
    end
  end

  return vim.json.encode({
    ok = true,
    tmux_sessions = #tmux_sessions,
    existing_count = #existing,
    opened_count = #opened,
    existing = existing,
    opened = opened,
    warning = warning,
  })
end

---@param sessions table[]?
---@return string[]
local function reconcile_session_lines(sessions)
  local lines = {}
  for _, session in ipairs(sessions or {}) do
    local provider = session.provider or "agent"
    local role = session.role == ROLE_SUB and ROLE_SUB or ROLE_MASTER
    local session_id = session.session_id or session.tmux_session_name or "unknown"
    table.insert(lines, ("  - %s %s %s"):format(provider, role, short_session_id(provider, session_id) or "unknown"))
  end
  return lines
end

---@param raw_result string
---@return string
local function format_reconcile_result(raw_result)
  local ok, result = pcall(vim.json.decode, raw_result)
  if not ok or type(result) ~= "table" then return raw_result end
  if not result.ok then return "Agent task reconcile failed: " .. tostring(result.error or "unknown error") end

  local tmux_sessions = tonumber(result.tmux_sessions) or 0
  local existing_count = tonumber(result.existing_count) or 0
  local opened_count = tonumber(result.opened_count) or 0
  local lines = {
    ("Agent task reconcile: %d tmux session%s, %d already open, %d reopened."):format(
      tmux_sessions,
      tmux_sessions == 1 and "" or "s",
      existing_count,
      opened_count
    ),
  }

  if opened_count > 0 then
    table.insert(lines, "Reopened:")
    vim.list_extend(lines, reconcile_session_lines(result.opened))
  end

  if type(result.warning) == "string" and result.warning ~= "" then
    table.insert(lines, "Warning: " .. result.warning)
  end

  return table.concat(lines, "\n")
end

---Resize all agent tmux sessions in the current Neovim-scoped tmux server to
---the current editor terminal geometry. Useful after moving Neovim between
---monitors or changing the terminal size.
---@param opts? { pulse?: boolean }
---@return string json
function M.resize_tmux_sessions(opts)
  opts = opts or {}
  local names, warning = tmux_agent_session_names()
  if not names then return vim.json.encode({ ok = false, error = warning }) end

  local ok_utils, utils = pcall(require, "serranomorante.utils")
  if not ok_utils then return vim.json.encode({ ok = false, error = "serranomorante.utils unavailable" }) end

  local resized, failed, sizes = {}, {}, {}
  local pulsed, pulse_failed = {}, {}
  local terminal_resized, terminal_failed = {}, {}
  local last_size
  for _, name in ipairs(names) do
    local size = current_tmux_size(name)
    last_size = size
    sizes[name] = size
    local task = task_for_tmux_session_name(name)
    local terminal_ok = resize_task_terminal_job(task, size)
    if terminal_ok == true then
      table.insert(terminal_resized, name)
    elseif terminal_ok == false then
      table.insert(terminal_failed, name)
    end
    local ok = resize_tmux_session_window(utils, name, size)
    if ok and opts.pulse == true then
      local pulse_ok = pulse_tmux_session_window(utils, name, size)
      table.insert(pulse_ok and pulsed or pulse_failed, name)
    end
    table.insert(ok and resized or failed, name)
  end

  return vim.json.encode({
    ok = #failed == 0,
    width = last_size and last_size.width or 0,
    height = last_size and last_size.height or 0,
    sizes = sizes,
    terminal_resized = terminal_resized,
    terminal_failed = terminal_failed,
    resized = resized,
    resized_count = #resized,
    failed = failed,
    pulsed = pulsed,
    pulse_failed = pulse_failed,
    warning = warning,
  })
end

---@param provider_name string
---@param t overseer.Task
---@return boolean
local function task_is_ready(provider_name, t)
  local lines = task_buffer_lines(t)
  if detect_state(lines) == "idle" then return true end

  local provider = provider_by_name(provider_name)
  if type(provider) ~= "table" or type(provider.ready) ~= "function" then return false end
  local output = type(lines) == "table" and table.concat(lines, "\n") or ""
  local ok, ready = pcall(provider.ready, output, t.cwd)
  return ok and ready == true
end

---Open a new provider-backed session as an Overseer task.
---When a prompt is supplied, wait best-effort until the new task is ready and
---paste the prompt into it using bracketed paste followed by '\r'.
---@param provider_name string
---@param b64_prompt? string optional base64-encoded initial prompt
---@param role? string "sub" to mark the spawned task as a sub-agent (default master)
---@param mcp? boolean|string true to launch through the provider's MCP wrapper
---@return string json
function M.new(provider_name, b64_prompt, role, mcp)
  if type(provider_name) ~= "string" or provider_name == "" then
    return vim.json.encode({ ok = false, error = "missing provider" })
  end
  local provider = provider_by_name(provider_name)
  if not provider then return vim.json.encode({ ok = false, error = "unknown provider: " .. provider_name }) end
  local as_sub = role == ROLE_SUB
  local use_mcp = mcp == true or mcp == "true" or mcp == "1"
  if use_mcp and (type(provider.mcp_executable) ~= "string" or provider.mcp_executable == "") then
    return vim.json.encode({ ok = false, error = provider.name .. " does not have an MCP launcher" })
  end

  local ok_as, agent_sessions = pcall(require, "serranomorante.plugins.jobs.agent_sessions")
  if not ok_as or type(agent_sessions.open_new) ~= "function" then
    return vim.json.encode({ ok = false, error = "agent_sessions.open_new unavailable" })
  end

  local before = {}
  for _, t in ipairs(list_tasks()) do
    local sid = task_session_id(t)
    if sid then before[sid] = true end
  end

  local prompt
  if type(b64_prompt) == "string" and b64_prompt ~= "" and type(vim.base64) == "table" then
    local dok, decoded = pcall(vim.base64.decode, b64_prompt)
    if dok then prompt = decoded end
  end

  vim.schedule(function()
    local opts = {}
    if as_sub then opts.role = ROLE_SUB end
    if use_mcp then opts.mcp = true end
    agent_sessions.open_new(provider.name, opts)
  end)

  if prompt then
    local tries = 0
    local function find_new()
      for _, t in ipairs(list_tasks()) do
        local sid = task_session_id(t)
        if sid and not before[sid] and task_provider(t) == provider.name then return t end
      end
    end
    local function step()
      tries = tries + 1
      local t = find_new()
      local job = t and task_job_id(t)
      local ready = t and task_is_ready(provider.name, t)
      if t and job and ready then
        pcall(vim.api.nvim_chan_send, job, "\27[200~" .. prompt .. "\27[201~")
        vim.defer_fn(function() pcall(vim.api.nvim_chan_send, job, "\r") end, 400)
      elseif tries < 60 then
        vim.defer_fn(step, 500)
      end
    end
    vim.defer_fn(step, 1000)
  end

  return vim.json.encode({
    ok = true,
    provider = provider.name,
    spawning = true,
    with_prompt = prompt ~= nil,
    role = as_sub and ROLE_SUB or ROLE_MASTER,
    mcp = use_mcp,
  })
end

---Re-tag an existing task's orchestration role. Setting "sub" marks it as a
---sub-agent; "master"/"root"/"" clears the mark. Renames the terminal buffer so
---the change shows in the Neovim tabpage title and refreshes the task list badge.
---@param ref string
---@param role string  -- "sub" | "master" | "root" | ""
---@return string json
function M.set_role(ref, role)
  local t, err = resolve_task(ref)
  if not t then return vim.json.encode({ ok = false, error = err }) end
  t.metadata = t.metadata or {}
  if role == ROLE_SUB then
    t.metadata[ROLE_KEY] = ROLE_SUB
  elseif role == ROLE_MASTER or role == "root" or role == "" or role == nil then
    t.metadata[ROLE_KEY] = nil
  else
    return vim.json.encode({ ok = false, error = "invalid role: " .. tostring(role) .. " (use sub|master)" })
  end

  -- Refresh the tabpage title (buffer name) + the task_list render badge. We only
  -- ever RENAME the task's own output buffer here; we never delete buffers (a stray
  -- bwipeout in this shared session can dispose live agent tasks). nvim_buf_set_name
  -- leaves the previous name behind as an unlisted, unloaded, empty alternate buffer
  -- — harmless and invisible in the tabline/buffer list.
  pcall(function()
    local bufnr = t:get_bufnr()
    if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
      require("serranomorante.utils").name_overseer_task_output(t, bufnr)
    end
  end)
  pcall(function() require("overseer.task_list").touch(t) end)

  return vim.json.encode({
    ok = true,
    id = t.id,
    session_id = task_session_id(t),
    role = task_role(t),
  })
end

---Dispose (stop + REMOVE from the Overseer task list) a single agent task by ref.
---Uses overseer's Task:dispose(force=true) so it disappears from the list even if
---the terminal is still attached. Idempotent-ish: a missing ref is a clean error.
---@param ref string
---@return string json
function M.dispose(ref)
  local t, err = resolve_task(ref)
  if not t then return vim.json.encode({ ok = false, error = err }) end
  local sid, id = task_session_id(t), t.id
  local ok = pcall(function() t:dispose(true) end)
  return vim.json.encode({ ok = ok, id = id, session_id = sid, disposed = ok })
end

---@param t overseer.Task
---@return table
local function dispose_and_kill_tmux_task(t)
  local sid, id = task_session_id(t), t.id
  local tmux_session_name = task_tmux_session_name(t)
  local disposed = pcall(function() t:dispose(true) end)
  local tmux_killed = false

  if type(tmux_session_name) == "string" and tmux_session_name ~= "" then
    local u = require("serranomorante.utils")
    tmux_killed = u.run_tmux_command(u.agent_tmux_server_name(), { "kill-session", "-t", tmux_session_name })
  end

  return {
    ok = disposed and (tmux_session_name == nil or tmux_killed),
    id = id,
    session_id = sid,
    disposed = disposed,
    tmux_killed = tmux_killed,
    tmux_session_name = tmux_session_name,
  }
end

---Dispose a task and also kill its tmux session if one is known.
---This is for manual session teardown, not for the normal "remove from list" flow.
---@param ref string
---@return string json
function M.dispose_and_kill_tmux(ref)
  local t, err = resolve_task(ref)
  if not t then return vim.json.encode({ ok = false, error = err }) end
  return vim.json.encode(dispose_and_kill_tmux_task(t))
end

---Kill the sandboxed tmux task and reopen the same conversation without Firejail.
---@param ref string
---@return string json
function M.detach_from_sandbox(ref)
  local t, err = resolve_task(ref)
  if not t then return vim.json.encode({ ok = false, error = err }) end
  local provider = task_provider(t)
  if provider ~= "codex" and provider ~= "opencode" and provider ~= "claude" and provider ~= "gemini" then
    return vim.json.encode({ ok = false, error = "detach from sandbox is only supported for codex, opencode, claude and gemini tasks" })
  end

  local tmux_session_name = task_tmux_session_name(t)
  local session_id = task_session_id(t) or session_id_from_tmux_session_name(provider, tmux_session_name)
  if type(session_id) ~= "string" or session_id == "" then
    return vim.json.encode({ ok = false, error = "task has no resolved " .. provider .. " session id" })
  end

  local role = task_role(t)
  local start_win = vim.api.nvim_get_current_win()
  local result = dispose_and_kill_tmux_task(t)
  if not result.ok then
    result.detached = false
    return vim.json.encode(result)
  end

  result.detached = true
  result.unfirejailed = true
  result.session_id = session_id
  vim.schedule(function()
    local ok_as, agent_sessions = pcall(require, "serranomorante.plugins.jobs.agent_sessions")
    if ok_as and type(agent_sessions.resume_by_id) == "function" then
      agent_sessions.resume_by_id(session_id, { role = role, start_win = start_win, unfirejailed = true })
    end
  end)

  return vim.json.encode(result)
end

---Kill pending tmux sessions in the current Neovim-scoped tmux server. Pending
---Codex sessions do not yet have a real session id, so they cannot reliably be
---resolved through normal task refs.
---@return string json
function M.dispose_pending_tmux()
  local names, warning = tmux_agent_session_names()
  if not names then return vim.json.encode({ ok = false, error = warning }) end

  local ok_utils, utils = pcall(require, "serranomorante.utils")
  if not ok_utils then return vim.json.encode({ ok = false, error = "serranomorante.utils unavailable" }) end

  local killed, failed, skipped = {}, {}, {}
  for _, name in ipairs(names) do
    if is_pending_tmux_session_name(name) then
      local ok = utils.run_tmux_command(utils.agent_tmux_server_name(), { "kill-session", "-t", name })
      table.insert(ok and killed or failed, name)
    else
      table.insert(skipped, name)
    end
  end

  return vim.json.encode({
    ok = #failed == 0,
    killed = killed,
    killed_count = #killed,
    failed = failed,
    skipped_count = #skipped,
    warning = warning,
  })
end

---Dispose ALL provider-backed agent tasks whose current state is "idle" (a prompt
---marker present and nothing running) — they vanish from the task list. Tasks that
---are running/awaiting_choice/unknown are left untouched. Pass exclude_sid (a full
---session id) to protect one session (e.g. the orchestrator or an in-flight child).
---@param exclude_sid? string
---@return string json
function M.dispose_idle(exclude_sid)
  if type(exclude_sid) ~= "string" or exclude_sid == "" then exclude_sid = nil end
  local disposed, skipped = {}, {}
  for _, t in ipairs(list_tasks()) do
    if task_provider(t) then
      local sid = task_session_id(t)
      local state = classify_state(task_buffer_lines(t))
      if state == "idle" and sid ~= exclude_sid then
        local ok = pcall(function() t:dispose(true) end)
        if ok then
          table.insert(disposed, sid or tostring(t.id))
        else
          table.insert(skipped, { session_id = sid, reason = "dispose-failed" })
        end
      else
        table.insert(skipped, { session_id = sid, reason = (sid == exclude_sid) and "excluded" or state })
      end
    end
  end
  return vim.json.encode({ ok = true, disposed = disposed, disposed_count = #disposed, skipped = skipped })
end

-- ---------------------------------------------------------------------------
-- Ex commands for humans; automated callers use the agent-tasks wrapper.
-- ---------------------------------------------------------------------------

function M.setup_commands()
  local resize_group = vim.api.nvim_create_augroup("DotfilesAgentTasksTmuxResize", { clear = true })
  vim.api.nvim_create_autocmd("VimResized", {
    group = resize_group,
    desc = "Agent tasks: resize current Neovim-scoped tmux agent sessions",
    callback = function()
      resize_autocmd_generation = resize_autocmd_generation + 1
      local generation = resize_autocmd_generation
      vim.defer_fn(function()
        if generation ~= resize_autocmd_generation then return end
        pcall(M.resize_tmux_sessions)
        local ok_utils, utils = pcall(require, "serranomorante.utils")
        if ok_utils then pcall(utils.refresh_terminal_window) end
      end, 100)
    end,
  })

  vim.api.nvim_create_user_command("AgentTasks", function()
    local data = vim.json.decode(M.list_json())
    local lines = { ("Agent tasks (%d):"):format(data.count) }
    for _, t in ipairs(data.tasks) do
      table.insert(
        lines,
        ("  [%s] %-7s %-7s %-9s %s"):format(
          tostring(t.id),
          t.state or "?",
          t.provider or "-",
          t.session_short_id or short_session_id(t.provider, t.session_id) or "-",
          t.name or ""
        )
      )
    end
    vim.api.nvim_echo({ { table.concat(lines, "\n") } }, false, {})
  end, { desc = "Agent tasks: list sibling agent tasks and state" })

  vim.api.nvim_create_user_command(
    "AgentTasksReconcile",
    function() vim.api.nvim_echo({ { format_reconcile_result(M.reconcile()) } }, false, {}) end,
    { desc = "Agent tasks: reconcile live tmux agent sessions with Overseer tasks" }
  )

  vim.api.nvim_create_user_command(
    "AgentTasksResizeTmux",
    function() vim.api.nvim_echo({ { M.resize_tmux_sessions({ pulse = true }) } }, false, {}) end,
    { desc = "Agent tasks: resize and repaint all current Neovim-scoped tmux agent sessions" }
  )

  vim.api.nvim_create_user_command(
    "AgentTasksDisposePendingTmux",
    function() vim.api.nvim_echo({ { M.dispose_pending_tmux() } }, false, {}) end,
    { desc = "Agent tasks: kill pending tmux agent sessions in the current Neovim server" }
  )

  vim.api.nvim_create_user_command(
    "AgentTaskRead",
    function(a) vim.api.nvim_echo({ { M.read(a.fargs[1], a.fargs[2]) } }, false, {}) end,
    { nargs = "+", desc = "Agent tasks: read tail of an agent task buffer (<ref> [lines])" }
  )

  vim.api.nvim_create_user_command(
    "AgentTaskDisposeAndKillTmux",
    function(a) vim.api.nvim_echo({ { M.dispose_and_kill_tmux(a.fargs[1]) } }, false, {}) end,
    { nargs = 1, desc = "Agent tasks: dispose a task and kill its tmux session (<ref>)" }
  )

  vim.api.nvim_create_user_command(
    "AgentTaskDetachFromSandbox",
    function(a) vim.api.nvim_echo({ { M.detach_from_sandbox(a.fargs[1]) } }, false, {}) end,
    { nargs = 1, desc = "Agent tasks: dispose a Codex task, kill tmux, and resume it without Firejail (<ref>)" }
  )

  vim.api.nvim_create_user_command("AgentTaskSend", function(a)
    local ref = a.fargs[1]
    local text = table.concat(vim.list_slice(a.fargs, 2, #a.fargs), " ")
    local b64 = vim.base64.encode(text)
    vim.api.nvim_echo({ { M.send(ref, b64, false) } }, false, {})
  end, { nargs = "+", desc = "Agent tasks: type text into an agent task input, no submit (<ref> <text...>)" })

  vim.api.nvim_create_user_command(
    "AgentTaskOpen",
    function(a) vim.api.nvim_echo({ { M.open(table.concat(a.fargs, ","), a.bang) } }, false, {}) end,
    { nargs = "+", bang = true, desc = "Agent tasks: open existing agent session(s) by id (! = bypass cwd filter)" }
  )

  vim.api.nvim_create_user_command(
    "AgentTaskNew",
    function(a)
      local provider_name = a.fargs[1]
      local use_mcp = false
      local role = ""
      local prompt_args = {}
      local i = 2
      while i <= #a.fargs do
        local arg = a.fargs[i]
        if arg == "--mcp" then
          use_mcp = true
        elseif arg == "--sub" or arg == "-s" then
          role = ROLE_SUB
        elseif arg == "--role" and i < #a.fargs then
          role = a.fargs[i + 1]
          i = i + 1
        else
          table.insert(prompt_args, arg)
        end
        i = i + 1
      end
      local prompt = table.concat(prompt_args, " ")
      local b64 = prompt ~= "" and vim.base64.encode(prompt) or ""
      vim.api.nvim_echo({ { M.new(provider_name, b64, role, use_mcp) } }, false, {})
    end,
    { nargs = "+", desc = "Agent tasks: spawn a new provider session (<provider> [--mcp] [--sub|--role role] [task])" }
  )
end

return M
