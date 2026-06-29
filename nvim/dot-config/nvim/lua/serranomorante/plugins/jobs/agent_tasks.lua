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
local PROMPT_MARKERS = {
  codex = "›",
  claude = "❯",
  gemini = "❯",
}

local DEFAULT_READ_LINES = 80

---@return table<string, table>
local function providers()
  local ok, agent_sessions = pcall(require, "serranomorante.plugins.jobs.agent_sessions")
  if not ok or type(agent_sessions.providers) ~= "table" then return {} end
  return agent_sessions.providers
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

---@param provider string?
---@return string?
local function prompt_marker_for_provider(provider)
  if type(provider) ~= "string" then return nil end
  return PROMPT_MARKERS[provider] or nil
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
  local marker = prompt_marker_for_provider(provider)
  if marker and tail:find(marker, 1, true) then return "idle" end
  if tail:find("> ", 1, true) then return "idle" end
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
    name = t.name,
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
  local header = ("# task id=%s session=%s provider=%s state=%s status=%s\n# lines %d-%d of %d"):format(
    tostring(t.id),
    tostring(task_session_id(t)),
    tostring(task_provider(t)),
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
---@param lines string[]?
---@return string state  -- "running"|"awaiting_choice"|"idle"|"unknown"
---@return table options -- [{n=integer,label=string}] when awaiting_choice
local function classify_state(lines)
  if type(lines) ~= "table" or #lines == 0 then return "unknown", {} end
  local from = math.max(1, #lines - 30)
  local tail_lines = vim.list_slice(lines, from, #lines)
  local tail = table.concat(tail_lines, "\n")

  -- BUSY: the agent is working (spinner shows the interrupt hint).
  if tail:find("esc to interrupt", 1, true) then return "running", {} end

  -- AWAITING A CHOICE: a numbered selection menu is open. Parse the options so
  -- the caller knows exactly what to pick (→ `choose <n>`).
  local is_choice = tail:find("Enter to select", 1, true) ~= nil
    or tail:find("to navigate", 1, true) ~= nil
    or tail:find("to select", 1, true) ~= nil
  local options = {}
  for _, ln in ipairs(tail_lines) do
    -- strip leading box-drawing/marker decoration ("│", "❯", ">", spaces), then "N. label"
    local num, label = ln:match("^[%s│>❯·*]*(%d+)%.%s+(.+)$")
    if num and label then
      label = label:gsub("%s+$", "")
      table.insert(options, { n = tonumber(num), label = label })
    end
  end
  if #options >= 2 and (is_choice or tail:find("❯%s*%d+%.")) then
    return "awaiting_choice", options
  end

  -- IDLE: a prompt marker is present and nothing is running → ready for input
  -- (a free-text question from the agent also lands here; read `tail` to see it).
  if tail:find("❯", 1, true) or tail:find("│ >", 1, true) or tail:find("> ", 1, true) then
    return "idle", {}
  end
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
  local state, options = classify_state(lines)
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
    provider = task_provider(t),
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
  local state = classify_state(task_buffer_lines(task))
  return state
end

local AGENT_WATCH_COMPONENT = "serranomorante.agent_watch"

---Attach the agent_watch component (live state in the task list) to one agent task.
---@param ref string
---@return string json
function M.attach_watch(ref)
  local t, err = resolve_task(ref)
  if not t then return vim.json.encode({ ok = false, error = err }) end
  if not t:has_component(AGENT_WATCH_COMPONENT) then
    pcall(function() t:add_component(AGENT_WATCH_COMPONENT) end)
  end
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
---@return string json
function M.new(provider_name, b64_prompt)
  if type(provider_name) ~= "string" or provider_name == "" then
    return vim.json.encode({ ok = false, error = "missing provider" })
  end
  local provider = provider_by_name(provider_name)
  if not provider then return vim.json.encode({ ok = false, error = "unknown provider: " .. provider_name }) end

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

  vim.schedule(function() agent_sessions.open_new(provider.name) end)

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

  return vim.json.encode({ ok = true, provider = provider.name, spawning = true, with_prompt = prompt ~= nil })
end

-- ---------------------------------------------------------------------------
-- Ex commands for humans; automated callers use the agent-tasks wrapper.
-- ---------------------------------------------------------------------------

function M.setup_commands()
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
          (t.session_id or "-"):sub(1, 8),
          t.name or ""
        )
      )
    end
    vim.api.nvim_echo({ { table.concat(lines, "\n") } }, false, {})
  end, { desc = "Agent tasks: list sibling agent tasks and state" })

  vim.api.nvim_create_user_command(
    "AgentTaskRead",
    function(a) vim.api.nvim_echo({ { M.read(a.fargs[1], a.fargs[2]) } }, false, {}) end,
    { nargs = "+", desc = "Agent tasks: read tail of an agent task buffer (<ref> [lines])" }
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

  vim.api.nvim_create_user_command("AgentTaskNew", function(a)
    local provider_name = a.fargs[1]
    local prompt = table.concat(vim.list_slice(a.fargs, 2, #a.fargs), " ")
    local b64 = prompt ~= "" and vim.base64.encode(prompt) or ""
    vim.api.nvim_echo({ { M.new(provider_name, b64) } }, false, {})
  end, { nargs = "+", desc = "Agent tasks: spawn a new provider session (<provider> [task to run])" })
end

return M
