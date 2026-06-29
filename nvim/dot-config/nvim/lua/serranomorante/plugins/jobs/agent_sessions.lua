local utils = require("serranomorante.utils")

local M = {}

local AGENT_TASK_METADATA = "agent_session"
local AGENT_PROVIDER_METADATA = "agent_provider"
local AGENT_SESSION_ID_METADATA = "agent_session_id"
local AGENT_SESSION_PATH_METADATA = "agent_session_path"
local AGENT_SESSION_UPDATED_AT_METADATA = "agent_session_updated_at"
local SESSION_CACHE_VERSION = 1
local SESSION_CACHE_NAMESPACE = "nvim"
local SESSION_CACHE_TTL_SECONDS = 7 * 24 * 60 * 60
local SESSION_CACHE_GC_PAYLOAD_BYTES = 1024 * 1024
local SESSION_TITLE_MAX_BYTES = 240
local SESSION_LINK_POLL_INTERVAL_MS = 500
local SESSION_LINK_TIMEOUT_MS = 60 * 1000
local SESSION_TITLE_TIMEOUT_MS = 10 * 60 * 1000
local SESSION_LINK_RETRY_INTERVAL_MS = 2 * 1000
local SESSION_ORPHAN_MATCH_WINDOW_SECONDS = 5 * 60

local CODEX_AUTO_REVIEW_ARGS = { "-a", "on-request", "-c", 'approvals_reviewer="auto_review"' }

local session_caches = {}
local session_link_retry_tasks = setmetatable({}, { __mode = "k" })

---@param output string
---@return string
local function strip_ansi(output) return output:gsub("[\27\155][][()#;?%d]*[A-PRZcf-ntqry=><~]", "") end

---@param output string
---@param cwd? string
---@return boolean
local function codex_ready(output, cwd)
  local text = strip_ansi(output)
  return text:find("OpenAI Codex", 1, true) ~= nil
    or (text:find("model:", 1, true) ~= nil and text:find("directory:", 1, true) ~= nil)
    or (cwd ~= nil and text:find(vim.fn.fnamemodify(cwd, ":~"), 1, true) ~= nil)
end

---@param output string
---@param cwd? string
---@return boolean
local function claude_ready(output, cwd)
  local text = strip_ansi(output)
  return text:find("Claude Code", 1, true) ~= nil
    or text:find("? for shortcuts", 1, true) ~= nil
    or (cwd ~= nil and text:find(vim.fn.fnamemodify(cwd, ":~"), 1, true) ~= nil)
end

---@param output string
---@param cwd? string
---@return boolean
local function gemini_ready(output, cwd)
  local text = strip_ansi(output)
  return text:find("Gemini CLI", 1, true) ~= nil
    or text:find("Loaded cached credentials", 1, true) ~= nil
    or text:find("? for shortcuts", 1, true) ~= nil
    or (cwd ~= nil and text:find(vim.fn.fnamemodify(cwd, ":~"), 1, true) ~= nil)
end

---@param ... string
---@return string[]
local function codex_args(...) return vim.list_extend(vim.deepcopy(CODEX_AUTO_REVIEW_ARGS), { ... }) end

---@return string
local function generated_uuid()
  if vim.fn.executable("uuidgen") == 1 then
    local uuid = vim.fn.system({ "uuidgen" }):gsub("%s+", ""):lower()
    if uuid:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") then return uuid end
  end

  local seed = ("%s:%s:%s:%s"):format(vim.uv.hrtime(), vim.fn.getcwd(), vim.v.servername, math.random())
  local hex = vim.fn.sha256(seed):lower()
  local variant = ({ "8", "9", "a", "b" })[math.random(1, 4)]
  hex = hex:sub(1, 12) .. "4" .. hex:sub(14, 16) .. variant .. hex:sub(18, 32)
  return ("%s-%s-%s-%s-%s"):format(hex:sub(1, 8), hex:sub(9, 12), hex:sub(13, 16), hex:sub(17, 20), hex:sub(21, 32))
end

math.randomseed(tonumber(tostring(vim.uv.hrtime()):sub(-8)) or os.time())

local PROVIDERS = {
  codex = {
    name = "codex",
    display_name = "Codex",
    executable = "codex",
    sessions_dir = vim.fn.expand("~/.codex/sessions"),
    cache_key = "agent-sessions-codex-v1",
    key_prefix = "c",
    continuation_name = "codex",
    ready = codex_ready,
    start_args = function() return codex_args() end,
    resume_args = function(session) return codex_args("resume", "--no-alt-screen", "-C", session.cwd, session.id) end,
    session_epoch_seconds = function(session)
      local compact_id = type(session.id) == "string" and session.id:gsub("%-", "") or nil
      local timestamp_hex = compact_id and compact_id:match("^([0-9a-fA-F]+)") or nil
      if not timestamp_hex or #timestamp_hex < 12 then return nil end
      return tonumber(timestamp_hex:sub(1, 12), 16) / 1000
    end,
  },
  claude = {
    name = "claude",
    display_name = "Claude",
    executable = "claude",
    sessions_dir = vim.fn.expand("~/.claude/projects"),
    cache_key = "agent-sessions-claude-v1",
    key_prefix = "a",
    continuation_name = "claude",
    ready = claude_ready,
    preallocate_session_id = true,
    -- Force the recommended Opus variant with the 1M context window on every
    -- launch and resume. The CLI flag overrides the model pin in settings.
    start_args = function(session_id)
      local args = { "--model", "opus[1m]" }
      if type(session_id) == "string" and session_id ~= "" then
        vim.list_extend(args, { "--session-id", session_id })
      end
      return args
    end,
    resume_args = function(session) return { "--model", "opus[1m]", "--resume", session.id } end,
  },
  gemini = {
    name = "gemini",
    display_name = "Gemini",
    executable = "gemini",
    sessions_dir = vim.fn.expand("~/.gemini/tmp"),
    cache_key = "agent-sessions-gemini-v1",
    key_prefix = "g",
    continuation_name = "gemini",
    ready = gemini_ready,
    preallocate_session_id = true,
    start_args = function(session_id)
      local args = {}
      if type(session_id) == "string" and session_id ~= "" then
        vim.list_extend(args, { "--session-id", session_id })
      end
      return args
    end,
    resume_args = function(session) return { "--resume", session.id } end,
  },
}

M.providers = PROVIDERS

---@param name string
---@return table
local function provider_by_name(name)
  local provider = PROVIDERS[name]
  if not provider then error("unknown agent provider: " .. tostring(name)) end
  return provider
end

---@param task overseer.Task
---@return table?
local function provider_for_task(task)
  if not task then return nil end

  local metadata = task and task.metadata or {}
  local provider_name = metadata[AGENT_PROVIDER_METADATA]
  if type(provider_name) == "string" and PROVIDERS[provider_name] then return PROVIDERS[provider_name] end

  for _, provider in pairs(PROVIDERS) do
    if task.cmd == provider.executable then return provider end
  end
end

---@param provider table
---@return table
local function session_cache(provider)
  local cache = session_caches[provider.name]
  if cache then return cache end

  cache = {
    loaded = false,
    sessions = nil,
    refresh_job = nil,
    waiters = {},
  }
  session_caches[provider.name] = cache
  return cache
end

---@param task overseer.Task
---@return integer?
local function task_job_id(task)
  ---@diagnostic disable-next-line: invisible
  local strategy = task.strategy
  return task.job_id or strategy and strategy.job_id or nil
end

local function leave_terminal_insert()
  pcall(vim.cmd.stopinsert)
  if vim.api.nvim_get_mode().mode ~= "t" then return end
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-\\><C-n>", true, false, true), "x", false)
  pcall(vim.cmd.stopinsert)
end

---@param text string
---@return string
local function markdown_fence(text)
  local ticks = 3
  for run in text:gmatch("`+") do
    if #run >= ticks then ticks = #run + 1 end
  end
  return string.rep("`", ticks)
end

---@param pos_a table
---@param pos_b table
---@return table
local function earlier_position(pos_a, pos_b)
  if pos_a[2] < pos_b[2] or (pos_a[2] == pos_b[2] and pos_a[3] <= pos_b[3]) then return pos_a end
  return pos_b
end

---@return string
local function current_buffer_name()
  local bufname = vim.api.nvim_buf_get_name(0)
  return bufname ~= "" and bufname or "[No Name]"
end

---@param source_pos table
---@return string
local function source_reference(source_pos)
  return ("%s:%s:%s"):format(current_buffer_name(), source_pos[2], source_pos[3])
end

---@param source_pos table
---@return string?
local function source_label(source_pos)
  local bufname = current_buffer_name()
  if bufname == "[No Name]" then return nil end
  return ("%s:%s"):format(vim.fn.fnamemodify(bufname, ":~:."), source_pos[2])
end

---@param start_pos table
---@param end_pos table
---@return string
local function selection_source(start_pos, end_pos) return source_reference(earlier_position(start_pos, end_pos)) end

---@param start_pos table
---@param end_pos table
---@return string?
local function selection_label(start_pos, end_pos) return source_label(earlier_position(start_pos, end_pos)) end

---@return string?
local function current_source_label()
  local bufname = current_buffer_name()
  if bufname == "[No Name]" then return nil end

  local line = vim.api.nvim_win_get_cursor(0)[1]
  return ("%s:%s"):format(vim.fn.fnamemodify(bufname, ":~:."), line)
end

---@param provider table
---@param cwd string
---@param label? string
---@return string
local function task_name(provider, cwd, label)
  local name = provider.name .. ": " .. vim.fn.fnamemodify(cwd, ":t")
  if label and label ~= "" then name = ("%s | %s"):format(name, label) end
  return ("%s | %s"):format(name, vim.fn.strftime("%H:%M"))
end

---@param data string|string[]
---@return string
local function output_to_string(data)
  if type(data) == "string" then return data end
  if type(data) == "table" then return table.concat(data, "\n") end
  return ""
end

---@param payload_bytes integer
local function collect_session_payload_garbage(payload_bytes)
  if payload_bytes < SESSION_CACHE_GC_PAYLOAD_BYTES then return end

  vim.schedule(function()
    collectgarbage("collect")
    collectgarbage("collect")
  end)
end

---@param title string?
---@return string?
local function normalized_session_title(title)
  if type(title) ~= "string" then return nil end

  local text = title:sub(1, SESSION_TITLE_MAX_BYTES + 64):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then return nil end
  if #text > SESSION_TITLE_MAX_BYTES then text = text:sub(1, SESSION_TITLE_MAX_BYTES) .. "..." end
  return text
end

---@return string?
local function cachectl_bin()
  local configured_bin = vim.env.CACHECTL_BIN
  if configured_bin and configured_bin ~= "" and vim.fn.executable(configured_bin) == 1 then return configured_bin end

  local repo_bin = utils.join_paths(vim.env.HOME, "dotfiles", "utilities", "bin", "cachectl")
  if vim.fn.executable(repo_bin) == 1 then return repo_bin end
  if vim.fn.executable("cachectl") == 1 then return "cachectl" end
end

---@return string[]?
local function cachectl_cmd(...)
  local bin = cachectl_bin()
  if not bin then return end

  return vim.list_extend({ bin }, { ... })
end

---@return string?
local function agent_session_store_bin()
  local configured_bin = vim.env.AGENT_SESSION_STORE_BIN
  if configured_bin and configured_bin ~= "" and vim.fn.executable(configured_bin) == 1 then return configured_bin end

  local repo_bin = utils.join_paths(vim.env.HOME, "dotfiles", "utilities", "bin", "agent-session-store")
  if vim.fn.executable(repo_bin) == 1 then return repo_bin end
  if vim.fn.executable("agent-session-store") == 1 then return "agent-session-store" end
end

---@param provider table
---@return string[]?
local function agent_session_store_cmd(provider, ...)
  local bin = agent_session_store_bin()
  if not bin then return end

  return vim.list_extend({ bin, "--provider", provider.name, "--root", provider.sessions_dir }, { ... })
end

---@class AgentStoredSession
---@field provider string
---@field id string
---@field cwd string
---@field timestamp string
---@field updated_at string
---@field title string?
---@field path string
---@field originator string?

---@param sessions any
---@return AgentStoredSession[]
local function valid_sessions(sessions)
  if type(sessions) ~= "table" then return {} end

  local valid = {}
  for _, session in ipairs(sessions) do
    local updated_at = type(session) == "table" and session.updated_at or nil
    if type(updated_at) ~= "string" and type(session) == "table" then updated_at = session.timestamp end

    if
      type(session) == "table"
      and type(session.provider) == "string"
      and type(session.id) == "string"
      and type(session.cwd) == "string"
      and type(session.timestamp) == "string"
      and type(session.path) == "string"
      and (session.originator == nil or type(session.originator) == "string")
      and (session.title == nil or type(session.title) == "string")
    then
      session.title = normalized_session_title(session.title)
      session.updated_at = updated_at
      table.insert(valid, session)
    end
  end

  table.sort(valid, function(a, b)
    local a_updated_at = a.updated_at or a.timestamp
    local b_updated_at = b.updated_at or b.timestamp
    if a_updated_at == b_updated_at then return a.timestamp > b.timestamp end
    return a_updated_at > b_updated_at
  end)
  return valid
end

---@param provider table
---@return AgentStoredSession[]?
local function read_session_cache(provider)
  local cache = session_cache(provider)
  if cache.loaded then return cache.sessions end
  cache.loaded = true

  local cmd = cachectl_cmd("get", SESSION_CACHE_NAMESPACE, provider.cache_key)
  if not cmd then return nil end

  local result = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 or result == "" then return nil end
  local payload_bytes = #result

  local decoded_ok, decoded = pcall(vim.json.decode, result)
  if
    not decoded_ok
    or type(decoded) ~= "table"
    or decoded.version ~= SESSION_CACHE_VERSION
    or type(decoded.sessions) ~= "table"
  then
    collect_session_payload_garbage(payload_bytes)
    return nil
  end

  cache.sessions = valid_sessions(decoded.sessions)
  collect_session_payload_garbage(payload_bytes)
  return cache.sessions
end

---@param provider table
---@param sessions AgentStoredSession[]
local function write_session_cache(provider, sessions)
  local cmd = cachectl_cmd("set", SESSION_CACHE_NAMESPACE, provider.cache_key, tostring(SESSION_CACHE_TTL_SECONDS))
  if not cmd then return end

  local payload = {
    version = SESSION_CACHE_VERSION,
    provider = provider.name,
    generated_at = os.time(),
    sessions = sessions,
  }

  pcall(vim.fn.system, cmd, vim.json.encode(payload))
end

---@param provider table
---@param sessions AgentStoredSession[]?
---@param cwd? string
---@param opts? { all?: boolean }
---@return AgentStoredSession[]
local function scoped_sessions(provider, sessions, cwd, opts)
  opts = opts or {}
  sessions = sessions or {}
  if opts.all then return valid_sessions(sessions) end

  cwd = cwd or vim.fn.getcwd()
  local scoped = {}
  for _, session in ipairs(sessions) do
    if session.provider == provider.name and session.cwd == cwd then table.insert(scoped, session) end
  end
  return valid_sessions(scoped)
end

---@param cache table
---@param sessions AgentStoredSession[]?
---@param ok boolean
local function finish_session_cache_refresh(cache, sessions, ok)
  local waiters = cache.waiters
  cache.waiters = {}

  for _, callback in ipairs(waiters) do
    callback(sessions, ok)
  end
end

---@param provider table
---@param opts? { callback?: fun(sessions: AgentStoredSession[]?, ok: boolean), silent?: boolean }
local function refresh_session_cache(provider, opts)
  opts = opts or {}
  local cache = session_cache(provider)
  if opts.callback then table.insert(cache.waiters, opts.callback) end
  if cache.refresh_job then return end

  local cmd = agent_session_store_cmd(provider, "refresh")
  if not cmd then
    if not opts.silent then vim.notify("agent-session-store executable not found", vim.log.levels.ERROR) end
    finish_session_cache_refresh(cache, cache.sessions, false)
    return
  end

  local stdout = {}
  local stderr = {}
  local job = vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, result)
      for _, line in ipairs(result) do
        if line ~= "" then table.insert(stdout, line) end
      end
    end,
    on_stderr = function(_, result)
      for _, line in ipairs(result) do
        if line ~= "" then table.insert(stderr, line) end
      end
    end,
    on_exit = vim.schedule_wrap(function(_, exit_code)
      cache.refresh_job = nil

      if exit_code ~= 0 then
        if not opts.silent then
          local msg = stderr[1] and table.concat(stderr, "\n")
            or ("%s session refresh failed: %s"):format(provider.display_name, exit_code)
          vim.notify(msg, vim.log.levels.ERROR)
        end
        finish_session_cache_refresh(cache, cache.sessions, false)
        return
      end

      local raw_output = table.concat(stdout, "\n")
      local payload_bytes = #raw_output
      local decoded_ok, decoded = pcall(vim.json.decode, raw_output)
      if
        not decoded_ok
        or type(decoded) ~= "table"
        or decoded.version ~= SESSION_CACHE_VERSION
        or decoded.provider ~= provider.name
      then
        if not opts.silent then
          vim.notify(("%s session refresh returned invalid JSON"):format(provider.display_name), vim.log.levels.ERROR)
        end
        collect_session_payload_garbage(payload_bytes)
        finish_session_cache_refresh(cache, cache.sessions, false)
        return
      end

      local sessions = valid_sessions(decoded.sessions)
      cache.loaded = true
      cache.sessions = sessions
      write_session_cache(provider, sessions)
      finish_session_cache_refresh(cache, sessions, true)
      collect_session_payload_garbage(payload_bytes)
    end),
  })

  if job <= 0 then
    cache.refresh_job = nil
    if not opts.silent then
      vim.notify("Failed to start " .. provider.display_name .. " session refresh", vim.log.levels.ERROR)
    end
    finish_session_cache_refresh(cache, cache.sessions, false)
    return
  end

  cache.refresh_job = job
end

local link_task_to_session

---@param provider table
---@param command string[]
---@return Promise
local function session_watch_job(provider, command)
  return require("promise")(function(resolve, reject)
    local stdout = {}
    local stderr = {}
    local job = vim.fn.jobstart(command, {
      stdout_buffered = true,
      stderr_buffered = true,
      on_stdout = function(_, result)
        for _, line in ipairs(result) do
          if line ~= "" then table.insert(stdout, line) end
        end
      end,
      on_stderr = function(_, result)
        for _, line in ipairs(result) do
          if line ~= "" then table.insert(stderr, line) end
        end
      end,
      on_exit = vim.schedule_wrap(function(_, exit_code)
        if exit_code ~= 0 then
          reject(
            stderr[1] and table.concat(stderr, "\n")
              or ("%s session watch failed: %s"):format(provider.display_name, exit_code)
          )
          return
        end

        local raw_output = table.concat(stdout, "\n")
        local payload_bytes = #raw_output
        local decoded_ok, decoded = pcall(vim.json.decode, raw_output)
        if
          not decoded_ok
          or type(decoded) ~= "table"
          or decoded.version ~= SESSION_CACHE_VERSION
          or decoded.provider ~= provider.name
        then
          reject(provider.display_name .. " session watch returned invalid JSON")
          collect_session_payload_garbage(payload_bytes)
          return
        end

        collect_session_payload_garbage(payload_bytes)
        resolve(decoded)
      end),
    })

    if job <= 0 then reject("Failed to start " .. provider.display_name .. " session watch") end
  end)
end

---@param provider table
---@param cwd string
---@return Promise
local function async_sessions(provider, cwd)
  local cmd = agent_session_store_cmd(provider, "refresh")
  if not cmd then return require("promise").reject("agent-session-store executable not found") end

  return session_watch_job(provider, cmd):thenCall(
    function(decoded) return scoped_sessions(provider, decoded.sessions, cwd) end
  )
end

---@param task overseer.Task
---@param session table
local function update_task_title(task, session)
  local provider = provider_by_name(session.provider)
  local title = normalized_session_title(session.title)
  if type(title) ~= "string" or title == "" then return end
  task.name = provider.name .. ": " .. title
end

---@param session AgentStoredSession
---@return string
local function session_display_title(session)
  if type(session.title) == "string" and session.title ~= "" then return session.title end
  return "Untitled session"
end

---@param provider table
---@param task overseer.Task
---@param command string[]
---@return Promise
local function watch_new_session_job(provider, task, command)
  return require("promise")(function(resolve, reject)
    local stdout_pending = ""
    local stderr = {}
    local resolved = false

    local function resolve_once(session)
      if resolved then return end
      resolved = true
      resolve(session)
    end

    local function handle_line(line)
      if line == "" then return end

      local decoded_ok, decoded = pcall(vim.json.decode, line)
      if
        not decoded_ok
        or type(decoded) ~= "table"
        or decoded.version ~= SESSION_CACHE_VERSION
        or decoded.provider ~= provider.name
      then
        return
      end

      if decoded.event == "session" and type(decoded.session) == "table" then
        link_task_to_session(task, decoded.session)
      elseif decoded.event == "title" and type(decoded.session) == "table" then
        link_task_to_session(task, decoded.session)
        resolve_once(decoded.session)
      elseif decoded.event == "timeout" then
        resolve_once()
      end
    end

    local job = vim.fn.jobstart(command, {
      stdout_buffered = false,
      stderr_buffered = true,
      on_stdout = function(_, result)
        if #result == 0 then return end

        result[1] = stdout_pending .. result[1]
        stdout_pending = table.remove(result) or ""

        for _, line in ipairs(result) do
          handle_line(line)
        end
      end,
      on_stderr = function(_, result)
        for _, line in ipairs(result) do
          if line ~= "" then table.insert(stderr, line) end
        end
      end,
      on_exit = vim.schedule_wrap(function(_, exit_code)
        handle_line(stdout_pending)

        if exit_code ~= 0 then
          reject(
            stderr[1] and table.concat(stderr, "\n")
              or ("%s session watch failed: %s"):format(provider.display_name, exit_code)
          )
          return
        end

        resolve_once()
      end),
    })

    if job <= 0 then reject("Failed to start " .. provider.display_name .. " session watch") end
  end)
end

---@param provider table
---@param cwd string
---@return Promise
local function async_session_ids(provider, cwd)
  local cmd = agent_session_store_cmd(provider, "ids", cwd)
  if not cmd then return require("promise").reject("agent-session-store executable not found") end

  return session_watch_job(provider, cmd):thenCall(function(decoded)
    local ids = {}
    if type(decoded.ids) ~= "table" then return ids end

    for _, id in ipairs(decoded.ids) do
      if type(id) == "string" then ids[id] = true end
    end

    return ids
  end)
end

---@param provider table
---@param task overseer.Task
---@param cwd string
---@param known_session_ids table<string, true>
---@return Promise
local function async_watch_new_session(provider, task, cwd, known_session_ids)
  local ids = {}
  for id in pairs(known_session_ids) do
    table.insert(ids, id)
  end

  local cmd = agent_session_store_cmd(
    provider,
    "watch-new",
    cwd,
    vim.json.encode(ids),
    tostring(SESSION_LINK_TIMEOUT_MS / 1000),
    tostring(SESSION_LINK_POLL_INTERVAL_MS / 1000),
    tostring(SESSION_TITLE_TIMEOUT_MS / 1000)
  )
  if not cmd then return require("promise").reject("agent-session-store executable not found") end

  return watch_new_session_job(provider, task, cmd)
end

---@param provider table
---@param task overseer.Task
---@return boolean
local function is_unlinked_plain_agent_task(provider, task)
  if task.status ~= require("overseer.constants").STATUS.RUNNING then return false end
  if task.metadata and task.metadata[AGENT_SESSION_PATH_METADATA] then return false end
  if task.cmd ~= provider.executable then return false end
  if provider.name == "codex" then return type(task.args) ~= "table" or #task.args == 0 end
  return false
end

---@param provider table
---@param task overseer.Task
---@param session AgentStoredSession
---@param known_session_ids? table<string, true>
---@return number?
local function unlinked_task_session_delta(provider, task, session, known_session_ids)
  if known_session_ids and known_session_ids[session.id] then return nil end
  if session.provider ~= provider.name then return nil end
  if not is_unlinked_plain_agent_task(provider, task) then return nil end
  if task.cwd ~= session.cwd then return nil end
  if type(task.time_start) ~= "number" then return nil end
  if type(provider.session_epoch_seconds) ~= "function" then return nil end

  local session_start = provider.session_epoch_seconds(session)
  if not session_start then return nil end

  local delta = math.abs(session_start - task.time_start)
  if delta > SESSION_ORPHAN_MATCH_WINDOW_SECONDS then return nil end
  return delta
end

---@param provider table
---@param task overseer.Task
---@param sessions AgentStoredSession[]
---@param known_session_ids? table<string, true>
---@return AgentStoredSession?
local function matching_unlinked_task_session(provider, task, sessions, known_session_ids)
  local best_session
  local best_delta

  for _, session in ipairs(sessions) do
    local delta = unlinked_task_session_delta(provider, task, session, known_session_ids)
    if delta and (not best_delta or delta < best_delta) then
      best_session = session
      best_delta = delta
    end
  end

  return best_session
end

---@param provider table
---@param session AgentStoredSession
---@param tasks overseer.Task[]
---@return overseer.Task?
local function matching_unlinked_session_task(provider, session, tasks)
  local best_task
  local best_delta

  for _, task in ipairs(tasks) do
    local delta = unlinked_task_session_delta(provider, task, session)
    if delta and (not best_delta or delta < best_delta) then
      best_task = task
      best_delta = delta
    end
  end

  return best_task
end

---@param provider table
---@param task overseer.Task
---@param cwd string
---@param known_session_ids table<string, true>
---@return Promise
local function async_link_task_to_recent_session(provider, task, cwd, known_session_ids)
  return async_sessions(provider, cwd):thenCall(function(sessions)
    local session = matching_unlinked_task_session(provider, task, sessions, known_session_ids)
    if session then link_task_to_session(task, session) end
    return session
  end)
end

---@param task overseer.Task
---@return boolean
local function task_has_session_path(task)
  return type(task.metadata) == "table" and type(task.metadata[AGENT_SESSION_PATH_METADATA]) == "string"
end

---@param task overseer.Task
---@return boolean
local function should_retry_session_link(task)
  if task_has_session_path(task) then return false end
  if type(task.is_disposed) ~= "function" then return true end

  local ok, disposed = pcall(task.is_disposed, task)
  return not ok or not disposed
end

---@param provider table
---@param task overseer.Task
---@param cwd string
---@param known_session_ids table<string, true>
local function retry_link_task_until_session_path(provider, task, cwd, known_session_ids)
  if not should_retry_session_link(task) then
    session_link_retry_tasks[task] = nil
    return
  end

  if session_link_retry_tasks[task] then return end
  session_link_retry_tasks[task] = true

  local function retry()
    if not should_retry_session_link(task) then
      session_link_retry_tasks[task] = nil
      return
    end

    async_link_task_to_recent_session(provider, task, cwd, known_session_ids)
      :thenCall(function()
        session_link_retry_tasks[task] = nil
        if should_retry_session_link(task) then
          retry_link_task_until_session_path(provider, task, cwd, known_session_ids)
        end
      end)
      :catch(function()
        session_link_retry_tasks[task] = nil
        if should_retry_session_link(task) then
          retry_link_task_until_session_path(provider, task, cwd, known_session_ids)
        end
      end)
  end

  vim.defer_fn(retry, SESSION_LINK_RETRY_INTERVAL_MS)
end

---@param timestamp string
---@return string
local function format_timestamp(timestamp) return timestamp:gsub("T", " "):gsub("%..+$", ""):gsub("Z$", "") end

---@param path string?
---@return boolean
local function is_existing_dir(path) return type(path) == "string" and path ~= "" and vim.fn.isdirectory(path) == 1 end

---@param provider table
---@param session AgentStoredSession
---@return AgentStoredSession
local function session_with_resolved_cwd(provider, session)
  if is_existing_dir(session.cwd) then return session end

  local fallback_cwd = vim.fn.getcwd()
  local resolved = vim.tbl_extend("force", session, { cwd = fallback_cwd })
  vim.notify(
    ("%s session cwd no longer exists; resuming from %s instead: %s"):format(
      provider.display_name,
      vim.fn.fnamemodify(fallback_cwd, ":~"),
      session.cwd
    ),
    vim.log.levels.WARN
  )
  return resolved
end

---@param winid integer
---@return boolean
local function is_regular_win(winid)
  return vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_config(winid).relative == ""
end

---@param preferred_win integer?
---@return integer?
local function regular_win(preferred_win)
  if preferred_win and is_regular_win(preferred_win) then return preferred_win end

  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if is_regular_win(winid) then return winid end
  end
end

---@param preferred_win integer?
local function restore_regular_win(preferred_win)
  local winid = regular_win(preferred_win)
  if winid then pcall(vim.api.nvim_set_current_win, winid) end
end

---@param task overseer.Task
---@param session_id string
---@return boolean
local function task_references_session_id(task, session_id)
  if type(task.cmd) == "string" and task.cmd:find(session_id, 1, true) then return true end

  if type(task.args) == "table" then
    for _, arg in ipairs(task.args) do
      if tostring(arg):find(session_id, 1, true) then return true end
    end
  end

  return false
end

---@param task overseer.Task
---@param session AgentStoredSession
function link_task_to_session(task, session)
  session.title = normalized_session_title(session.title)
  task.metadata = task.metadata or {}
  task.metadata[AGENT_TASK_METADATA] = true
  task.metadata[AGENT_PROVIDER_METADATA] = session.provider
  task.metadata[AGENT_SESSION_ID_METADATA] = session.id
  task.metadata[AGENT_SESSION_PATH_METADATA] = session.path
  task.metadata[AGENT_SESSION_UPDATED_AT_METADATA] = session.updated_at
  update_task_title(task, session)
  local ok, bufnr = pcall(function() return task:get_bufnr() end)
  if ok and bufnr and vim.api.nvim_buf_is_valid(bufnr) then utils.attach_overseer_task_output_navigation(bufnr) end
end

---@param task overseer.Task
---@return integer?
function M.task_session_mtime(task)
  local path = task.metadata and task.metadata[AGENT_SESSION_PATH_METADATA] or nil
  if type(path) ~= "string" then return nil end

  local stat = vim.uv.fs_stat(path)
  return stat and stat.mtime and stat.mtime.sec or nil
end

---@param provider table
---@param session AgentStoredSession
---@return overseer.Task?
local function running_task_for_session(provider, session)
  local STATUS = require("overseer.constants").STATUS
  local tasks = require("overseer").list_tasks({ status = STATUS.RUNNING })
  for _, task in ipairs(tasks) do
    local metadata = task.metadata or {}
    if metadata[AGENT_PROVIDER_METADATA] == provider.name and metadata[AGENT_SESSION_ID_METADATA] == session.id then
      link_task_to_session(task, session)
      return task
    end
    if task.cmd == provider.executable and task_references_session_id(task, session.id) then
      link_task_to_session(task, session)
      return task
    end
  end

  local task = matching_unlinked_session_task(provider, session, tasks)
  if task then
    link_task_to_session(task, session)
    return task
  end
end

---@param provider table
---@param session AgentStoredSession
local function dispose_pending_task_for_session(provider, session)
  local STATUS = require("overseer.constants").STATUS
  local tasks = require("overseer").list_tasks({ status = STATUS.PENDING })
  for _, task in ipairs(tasks) do
    local metadata = task.metadata or {}
    local matches_metadata = metadata[AGENT_PROVIDER_METADATA] == provider.name
      and metadata[AGENT_SESSION_ID_METADATA] == session.id
    local matches_command = task.cmd == provider.executable and task_references_session_id(task, session.id)
    if matches_metadata or matches_command then task:dispose(true) end
  end
end

---@class AgentSessionOpts
---@field visual? boolean
---@field wait_for_ready? boolean
---@field open_output? boolean
---@field all? boolean
---@field start_win? integer

---@param opts? AgentSessionOpts
---@return string? prompt
---@return string? label
local function prompt_from_visual_selection(opts)
  opts = opts or {}
  local mode = vim.fn.mode()
  local is_current_visual = vim.list_contains({ "v", "V", "\22" }, mode)
  if not is_current_visual and not opts.visual then return nil end

  local start_pos = is_current_visual and vim.fn.getpos("v") or vim.fn.getpos("'<")
  local end_pos = is_current_visual and vim.fn.getpos(".") or vim.fn.getpos("'>")
  if start_pos[2] == 0 or end_pos[2] == 0 then return nil end

  local region_type = is_current_visual and mode or vim.fn.visualmode()
  if region_type == "" then region_type = "v" end
  local region = vim.fn.getregion(start_pos, end_pos, { type = region_type })
  local selected_text = table.concat(region, "\n")
  if selected_text == "" then return nil end

  local filetype = vim.bo.filetype ~= "" and vim.bo.filetype or "text"
  filetype = filetype:gsub("[^%w_.+-]", "")
  local fence = markdown_fence(selected_text)
  return ("%s\n\n%s%s\n%s\n%s\n\n"):format(selection_source(start_pos, end_pos), fence, filetype, selected_text, fence),
    selection_label(start_pos, end_pos)
end

---@return overseer.Task?
local function current_overseer_task()
  local bufnr = vim.api.nvim_get_current_buf()
  local task_id = vim.b[bufnr].overseer_task
  if task_id then
    local ok, task_list = pcall(require, "overseer.task_list")
    local task = ok and task_list.get(task_id) or nil
    if task then return task end
  end

  if vim.bo[bufnr].filetype ~= "OverseerList" then return nil end

  local ok, sidebar = pcall(require, "overseer.task_list.sidebar")
  if not ok or type(sidebar.get_or_create) ~= "function" then return nil end

  local sidebar_ok, sb = pcall(sidebar.get_or_create)
  if not sidebar_ok or type(sb) ~= "table" or type(sb.get_task_from_line) ~= "function" then return nil end

  local task_ok, task = pcall(sb.get_task_from_line, sb)
  return task_ok and task or nil
end

---@return string?
local function prompt_from_agent_task(task)
  local metadata = task and task.metadata or nil
  local session_id = metadata and metadata[AGENT_SESSION_ID_METADATA] or nil
  if type(session_id) ~= "string" or session_id == "" then return nil end

  local provider_name = metadata[AGENT_PROVIDER_METADATA]
  local provider = provider_name and PROVIDERS[provider_name] or nil
  local continuation_name = provider and provider.continuation_name or "agent"
  return ("continuing this %s conversation with id: %s\n\n"):format(continuation_name, session_id)
end

---@return string?
local function prompt_from_agent_task_under_cursor() return prompt_from_agent_task(current_overseer_task()) end

---@param opts? AgentSessionOpts
---@return string? prompt
---@return string? label
local function prompt_from_context(opts)
  local prompt_parts = {}
  local continuation_prompt = prompt_from_agent_task_under_cursor()
  if continuation_prompt then table.insert(prompt_parts, continuation_prompt) end

  local visual_prompt, label = prompt_from_visual_selection(opts)
  if visual_prompt then table.insert(prompt_parts, visual_prompt) end

  if #prompt_parts == 0 then return nil, label end
  return table.concat(prompt_parts), label
end

---@param opts? AgentSessionOpts
---@return string? prompt
---@return string? label
function M.prompt_from_context(opts) return prompt_from_context(opts) end

local function leave_visual_mode()
  local mode = vim.fn.mode()
  if not vim.list_contains({ "v", "V", "\22" }, mode) then return end
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
end

---@param opts? AgentSessionOpts
---@return { visual_prompt: string?, source_task: overseer.Task? }
function M.capture_task_action_prompt_context(opts)
  local visual_prompt = prompt_from_visual_selection(opts)
  local source_task = current_overseer_task()
  leave_visual_mode()
  return {
    visual_prompt = visual_prompt,
    source_task = source_task,
  }
end

---@param context { visual_prompt: string?, source_task: overseer.Task? }?
---@param target_task overseer.Task?
---@return string?
function M.prompt_from_task_action_context(context, target_task)
  if not context then return nil end
  if context.visual_prompt and context.visual_prompt ~= "" then return context.visual_prompt end

  local source_task = context.source_task
  if not source_task or not target_task or source_task.id == target_task.id then return nil end
  return prompt_from_agent_task(source_task)
end

---@param provider table
---@param task overseer.Task
---@param prompt? string
local function paste_prompt(provider, task, prompt)
  if not prompt or prompt == "" then return end

  local function send()
    local job_id = task_job_id(task)
    if not job_id then return false end

    local ok, err = pcall(vim.api.nvim_chan_send, job_id, "\27[200~" .. prompt .. "\27[201~")
    if not ok then
      vim.notify(("Could not paste selection into %s: %s"):format(provider.display_name, err), vim.log.levels.ERROR)
    end
    leave_terminal_insert()
    return ok
  end

  if not task.metadata.wait_for_agent_ready then
    send()
    return
  end

  local sent = false
  local output_tail = ""
  task:subscribe("on_output", function(_, data)
    output_tail = (output_tail .. output_to_string(data)):sub(-4000)
    if sent or not provider.ready(output_tail, task.cwd) then return end
    sent = send()
  end)
end

---@param provider table
---@param task overseer.Task
---@param cwd string
---@param known_session_ids table<string, true>
local function link_new_task_to_session_id(provider, task, cwd, known_session_ids)
  async_watch_new_session(provider, task, cwd, known_session_ids)
    :thenCall(function()
      if task_has_session_path(task) then return end
      retry_link_task_until_session_path(provider, task, cwd, known_session_ids)
    end)
    :catch(function(err)
      vim.notify(tostring(err), vim.log.levels.ERROR)
      retry_link_task_until_session_path(provider, task, cwd, known_session_ids)
    end)
end

---@param provider table
---@param task overseer.Task
---@param prompt? string
---@param opts? AgentSessionOpts
local function open_task(provider, task, prompt, opts)
  opts = opts or {}
  task.metadata = task.metadata or {}
  task.metadata[AGENT_TASK_METADATA] = true
  task.metadata[AGENT_PROVIDER_METADATA] = provider.name
  task.metadata.wait_for_agent_ready = opts.wait_for_ready == true
  utils.attach_keymaps(task)
  if opts.open_output ~= false then
    utils.schedule_open_overseer_task_output(task, { winid = opts.start_win })
    require("serranomorante.remote_kitty_focus").focus_current_window()
  end
  paste_prompt(provider, task, prompt)
end

---@param provider table
---@param task overseer.Task
---@param start_win integer
---@return boolean
local function start_and_open_task_output(provider, task, start_win)
  restore_regular_win(start_win)
  start_win = start_win or vim.api.nvim_get_current_win()
  leave_terminal_insert()
  utils.remember_overseer_output_previous_buffer(start_win)
  if not task:start() then
    vim.notify(("Failed to start %s task"):format(provider.display_name), vim.log.levels.ERROR)
    task:dispose(true)
    return false
  end

  utils.schedule_open_overseer_task_output(task, { winid = start_win })
  require("serranomorante.remote_kitty_focus").focus_current_window()
  return true
end

---@param session AgentStoredSession
---@param include_cwd? boolean
---@return string
local function format_session(session, include_cwd)
  local label = ("%s | %s"):format(
    format_timestamp(session.updated_at or session.timestamp),
    session_display_title(session)
  )
  if include_cwd then label = ("%s | %s"):format(label, vim.fn.fnamemodify(session.cwd, ":~")) end
  return label
end

---@param value string
---@return string
local function fzf_field(value) return value:gsub("\t", " "):gsub("\n", " ") end

---@param provider table
---@param sessions AgentStoredSession[]
---@param opts AgentSessionOpts
---@param loading? boolean
---@return string[]
local function session_fzf_entries(provider, sessions, opts, loading)
  if loading then return { ("__%s-loading\tLoading %s sessions..."):format(provider.name, provider.display_name) } end

  if #sessions == 0 then
    local scope = opts.all and "any working directory" or vim.fn.getcwd()
    return { ("__%s-empty\tNo %s sessions found for %s"):format(provider.name, provider.display_name, fzf_field(scope)) }
  end

  local entries = {}
  for _, session in ipairs(sessions) do
    table.insert(entries, ("%s\t%s"):format(session.id, fzf_field(format_session(session, opts.all))))
  end
  return entries
end

---@param sessions AgentStoredSession[]
---@return table<string, AgentStoredSession>
local function sessions_by_id(sessions)
  local by_id = {}
  for _, session in ipairs(sessions) do
    by_id[session.id] = session
  end
  return by_id
end

---@param text string?
---@return string?
local function agent_session_id(text)
  if type(text) ~= "string" then return nil end
  return text:match("^%s*@agent%s+(%S+)") or text:match("^%s*(%S+)")
end

---@param provider table
---@param session AgentStoredSession
---@param prompt? string
---@param start_win integer
local function resume_session(provider, session, prompt, start_win)
  restore_regular_win(start_win)
  session = session_with_resolved_cwd(provider, session)

  local existing_task = running_task_for_session(provider, session)
  if existing_task then
    open_task(provider, existing_task, prompt, { start_win = start_win })
    return
  end
  dispose_pending_task_for_session(provider, session)

  local task = require("overseer").new_task({
    name = ("%s resume: %s"):format(provider.name, session_display_title(session)),
    cmd = provider.executable,
    args = provider.resume_args(session),
    cwd = session.cwd,
    metadata = {
      [AGENT_TASK_METADATA] = true,
      [AGENT_PROVIDER_METADATA] = provider.name,
      [AGENT_SESSION_ID_METADATA] = session.id,
      [AGENT_SESSION_PATH_METADATA] = session.path,
      [AGENT_SESSION_UPDATED_AT_METADATA] = session.updated_at,
    },
    components = { "defaults_without_notification", "serranomorante.agent_watch" },
  })

  open_task(provider, task, prompt, { wait_for_ready = true, start_win = start_win, open_output = false })
  if not start_and_open_task_output(provider, task, start_win) then return end
end

---@param provider table
---@param session_id string?
---@param active_sessions_by_id table<string, AgentStoredSession>
---@param prompt? string
---@param start_win integer
---@return boolean
local function resume_selected_session_id(provider, session_id, active_sessions_by_id, prompt, start_win)
  session_id = agent_session_id(session_id)
  local session = session_id and active_sessions_by_id[session_id] or nil
  if not session then return false end

  vim.schedule(function() resume_session(provider, session, prompt, start_win) end)
  return true
end

---@param provider table
---@param session_id string
---@param prompt? string
---@param start_win integer?
---@return boolean
local function resume_cached_provider_session(provider, session_id, prompt, start_win)
  local cached_sessions = read_session_cache(provider)
  if not cached_sessions then return false end
  return resume_selected_session_id(provider, session_id, sessions_by_id(cached_sessions), prompt, start_win)
end

---@param provider table
---@param session_id string
---@param prompt? string
---@param start_win integer?
local function refresh_and_resume_provider_session(provider, session_id, prompt, start_win)
  refresh_session_cache(provider, {
    silent = true,
    callback = function(refreshed_sessions, ok)
      if
        ok
        and resume_selected_session_id(
          provider,
          session_id,
          sessions_by_id(refreshed_sessions or {}),
          prompt,
          start_win
        )
      then
        return
      end

      vim.notify(("Agent session not found: %s"):format(session_id), vim.log.levels.ERROR)
    end,
  })
end

---@param task overseer.Task
---@param prompt? string
---@param opts? { start_win?: integer }
---@return boolean
function M.open_task_with_prompt(task, prompt, opts)
  opts = opts or {}
  local provider = provider_for_task(task)
  if not provider then return false end

  if task.status == require("overseer.constants").STATUS.RUNNING then
    open_task(provider, task, prompt, { start_win = opts.start_win })
    return true
  end

  local metadata = task.metadata or {}
  local session_id = metadata[AGENT_SESSION_ID_METADATA]
  if type(session_id) ~= "string" or session_id == "" then return false end
  if resume_cached_provider_session(provider, session_id, prompt, opts.start_win) then return true end

  refresh_and_resume_provider_session(provider, session_id, prompt, opts.start_win)
  return true
end

---@param session_id string
---@param start_win integer
---@return boolean
local function resume_cached_session_any_provider(session_id, start_win)
  for _, provider in pairs(PROVIDERS) do
    local cached_sessions = read_session_cache(provider)
    if
      cached_sessions
      and resume_selected_session_id(provider, session_id, sessions_by_id(cached_sessions), nil, start_win)
    then
      return true
    end
  end
  return false
end

---@param session_id string
---@param start_win integer
local function refresh_and_resume_any_provider(session_id, start_win)
  local pending = 0
  local finished = false

  local function finish_not_found()
    if finished or pending > 0 then return end
    vim.notify("Agent session not found: " .. session_id, vim.log.levels.ERROR)
  end

  for _, provider in pairs(PROVIDERS) do
    pending = pending + 1
    refresh_session_cache(provider, {
      silent = true,
      callback = function(refreshed_sessions, ok)
        pending = pending - 1
        if
          not finished
          and ok
          and resume_selected_session_id(provider, session_id, sessions_by_id(refreshed_sessions or {}), nil, start_win)
        then
          finished = true
          return
        end
        finish_not_found()
      end,
    })
  end
end

---@param provider_name string
---@param opts? AgentSessionOpts
function M.select(provider_name, opts)
  local provider = provider_by_name(provider_name)
  opts = opts or {}
  local prompt = prompt_from_context(opts)
  leave_visual_mode()
  local cached_sessions = read_session_cache(provider)
  local sessions = scoped_sessions(provider, cached_sessions, nil, { all = opts.all == true })
  local has_cache = cached_sessions ~= nil
  local active_sessions_by_id = sessions_by_id(sessions)
  local start_win = vim.api.nvim_get_current_win()

  utils.fzf({
    source = session_fzf_entries(provider, sessions, opts, not has_cache),
    prompt = opts.all and ("%s sessions (all cwd)"):format(provider.display_name)
      or ("%s sessions"):format(provider.display_name),
    options = {
      "--delimiter='\t'",
      "--with-nth=2..",
    },
    refresh = function(reload)
      refresh_session_cache(provider, {
        silent = true,
        callback = function(refreshed_sessions, ok)
          if not ok then return end

          sessions = scoped_sessions(provider, refreshed_sessions, nil, { all = opts.all == true })
          active_sessions_by_id = sessions_by_id(sessions)
          reload(session_fzf_entries(provider, sessions, opts))
        end,
      })
    end,
    sink = function(entry)
      local session_id = entry:match("^([^\t]+)\t")
      resume_selected_session_id(provider, session_id, active_sessions_by_id, prompt, start_win)
    end,
  })
end

---@param provider_name string
---@param opts? AgentSessionOpts
function M.open_new(provider_name, opts)
  local provider = provider_by_name(provider_name)
  if vim.fn.executable(provider.executable) ~= 1 then
    vim.api.nvim_echo({ { provider.executable .. " executable not found", "DiagnosticError" } }, false, {})
    return
  end

  local prompt, label = prompt_from_context(opts)
  leave_visual_mode()
  local cwd = vim.fn.getcwd()
  local label_or_source = label or current_source_label()
  local preallocated_session_id = provider.preallocate_session_id and generated_uuid() or nil
  local start_win = vim.api.nvim_get_current_win()

  require("async")(function()
    local known_session_ids = await(async_session_ids(provider, cwd))
    local metadata = {
      [AGENT_TASK_METADATA] = true,
      [AGENT_PROVIDER_METADATA] = provider.name,
    }
    if preallocated_session_id then metadata[AGENT_SESSION_ID_METADATA] = preallocated_session_id end

    local task = require("overseer").new_task({
      name = task_name(provider, cwd, label_or_source),
      cmd = provider.executable,
      args = provider.start_args(preallocated_session_id),
      cwd = cwd,
      metadata = metadata,
      components = { "defaults_without_notification", "serranomorante.agent_watch" },
    })

    open_task(provider, task, prompt, { wait_for_ready = true, start_win = start_win, open_output = false })
    if not start_and_open_task_output(provider, task, start_win) then return end
    link_new_task_to_session_id(provider, task, cwd, known_session_ids)
  end):catch(function(err) vim.notify(tostring(err), vim.log.levels.ERROR) end)
end

local function create_agent_resume_command()
  vim.api.nvim_create_user_command("AgentResumeById", function(command_args)
    local session_id = agent_session_id(command_args.args)
    if not session_id then return vim.notify("Agent session id is required", vim.log.levels.ERROR) end

    local start_win = vim.api.nvim_get_current_win()
    if resume_cached_session_any_provider(session_id, start_win) then return end
    refresh_and_resume_any_provider(session_id, start_win)
  end, {
    force = true,
    nargs = 1,
    desc = "Resume an agent session in Overseer by id",
  })
end

---@param provider table
local function create_provider_keymaps(provider)
  local prefix = provider.key_prefix
  local display = provider.display_name

  vim.keymap.set(
    "n",
    ("<leader>%sl"):format(prefix),
    function() require("serranomorante.plugins.jobs.agent_sessions").select(provider.name) end,
    { desc = display .. ": Resume project session" }
  )

  vim.keymap.set(
    "n",
    ("<leader>%sL"):format(prefix),
    function() require("serranomorante.plugins.jobs.agent_sessions").select(provider.name, { all = true }) end,
    { desc = display .. ": Resume any session" }
  )

  vim.keymap.set(
    "x",
    ("<leader>%sl"):format(prefix),
    function() require("serranomorante.plugins.jobs.agent_sessions").select(provider.name, { visual = true }) end,
    { desc = display .. ": Resume project session" }
  )

  vim.keymap.set(
    "x",
    ("<leader>%sL"):format(prefix),
    function()
      require("serranomorante.plugins.jobs.agent_sessions").select(provider.name, { visual = true, all = true })
    end,
    { desc = display .. ": Resume any session" }
  )

  vim.keymap.set(
    "n",
    ("<leader>%sn"):format(prefix),
    function() require("serranomorante.plugins.jobs.agent_sessions").open_new(provider.name) end,
    { desc = display .. ": New Overseer session" }
  )

  vim.keymap.set(
    "x",
    ("<leader>%sn"):format(prefix),
    function() require("serranomorante.plugins.jobs.agent_sessions").open_new(provider.name, { visual = true }) end,
    { desc = display .. ": New Overseer session" }
  )
end

function M.keys()
  create_agent_resume_command()
  create_provider_keymaps(PROVIDERS.codex)
  create_provider_keymaps(PROVIDERS.claude)
  create_provider_keymaps(PROVIDERS.gemini)
end

return M
