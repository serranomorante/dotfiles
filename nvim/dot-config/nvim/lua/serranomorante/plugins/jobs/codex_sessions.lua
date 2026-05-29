local utils = require("serranomorante.utils")

local M = {}

local CODEX_TASK_METADATA = "codex_session"
local CODEX_SESSION_ID_METADATA = "codex_session_id"
local CODEX_SESSION_PATH_METADATA = "codex_session_path"
local CODEX_SESSION_UPDATED_AT_METADATA = "codex_session_updated_at"
local CODEX_SESSIONS_DIR = vim.fn.expand("~/.codex/sessions")
local SESSION_CACHE_VERSION = 1
local SESSION_CACHE_NAMESPACE = "nvim"
local SESSION_CACHE_KEY = "codex-sessions-v3"
local SESSION_CACHE_TTL_SECONDS = 7 * 24 * 60 * 60
local SESSION_LINK_POLL_INTERVAL_MS = 500
local SESSION_LINK_TIMEOUT_MS = 60 * 1000
local SESSION_TITLE_TIMEOUT_MS = 10 * 60 * 1000
local SESSION_LINK_RETRY_INTERVAL_MS = 2 * 1000
local SESSION_ORPHAN_MATCH_WINDOW_SECONDS = 5 * 60

local session_cache = {
  loaded = false,
  sessions = nil,
  refresh_job = nil,
  waiters = {},
}
local session_link_retry_tasks = setmetatable({}, { __mode = "k" })

local function codex_session_store_bin()
  local configured_bin = vim.env.CODEX_SESSION_STORE_BIN
  if configured_bin and configured_bin ~= "" and vim.fn.executable(configured_bin) == 1 then return configured_bin end

  local repo_bin = utils.join_paths(vim.env.HOME, "dotfiles", "utilities", "bin", "codex-session-store")
  if vim.fn.executable(repo_bin) == 1 then return repo_bin end
  if vim.fn.executable("codex-session-store") == 1 then return "codex-session-store" end
end

---@return string[]?
local function codex_session_store_cmd(...)
  local bin = codex_session_store_bin()
  if not bin then return end

  return vim.list_extend({ bin, "--root", CODEX_SESSIONS_DIR }, { ... })
end

---@param task overseer.Task
---@return integer?
local function task_job_id(task)
  ---@diagnostic disable-next-line: invisible
  local strategy = task.strategy
  return task.job_id or strategy and strategy.job_id or nil
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

---@param cwd string
---@param label? string
---@return string
local function task_name(cwd, label)
  local name = "codex: " .. vim.fn.fnamemodify(cwd, ":t")
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

---@param sessions any
---@return CodexStoredSession[]
local function valid_sessions(sessions)
  if type(sessions) ~= "table" then return {} end

  local valid = {}
  for _, session in ipairs(sessions) do
    local updated_at = type(session) == "table" and session.updated_at or nil
    if type(updated_at) ~= "string" and type(session) == "table" then updated_at = session.timestamp end

    if
      type(session) == "table"
      and type(session.id) == "string"
      and type(session.cwd) == "string"
      and type(session.timestamp) == "string"
      and type(session.path) == "string"
      and (session.originator == nil or type(session.originator) == "string")
      and (session.title == nil or type(session.title) == "string")
    then
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

---@return CodexStoredSession[]?
local function read_session_cache()
  if session_cache.loaded then return session_cache.sessions end
  session_cache.loaded = true

  local cmd = cachectl_cmd("get", SESSION_CACHE_NAMESPACE, SESSION_CACHE_KEY)
  if not cmd then return nil end

  local result = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 or result == "" then return nil end

  local decoded_ok, decoded = pcall(vim.json.decode, result)
  if
    not decoded_ok
    or type(decoded) ~= "table"
    or decoded.version ~= SESSION_CACHE_VERSION
    or type(decoded.sessions) ~= "table"
  then
    return nil
  end

  session_cache.sessions = valid_sessions(decoded.sessions)
  return session_cache.sessions
end

---@param sessions CodexStoredSession[]
local function write_session_cache(sessions)
  local cmd = cachectl_cmd("set", SESSION_CACHE_NAMESPACE, SESSION_CACHE_KEY, tostring(SESSION_CACHE_TTL_SECONDS))
  if not cmd then return end

  local payload = {
    version = SESSION_CACHE_VERSION,
    generated_at = os.time(),
    sessions = sessions,
  }

  pcall(vim.fn.system, cmd, vim.json.encode(payload))
end

---@param sessions CodexStoredSession[]?
---@param cwd? string
---@param opts? { all?: boolean }
---@return CodexStoredSession[]
local function scoped_sessions(sessions, cwd, opts)
  opts = opts or {}
  sessions = sessions or {}
  if opts.all then return valid_sessions(sessions) end

  cwd = cwd or vim.fn.getcwd()
  local scoped = {}
  for _, session in ipairs(sessions) do
    if session.cwd == cwd then table.insert(scoped, session) end
  end
  return valid_sessions(scoped)
end

---@param sessions CodexStoredSession[]?
---@param ok boolean
local function finish_session_cache_refresh(sessions, ok)
  local waiters = session_cache.waiters
  session_cache.waiters = {}

  for _, callback in ipairs(waiters) do
    callback(sessions, ok)
  end
end

---@param opts? { callback?: fun(sessions: CodexStoredSession[]?, ok: boolean), silent?: boolean }
local function refresh_session_cache(opts)
  opts = opts or {}
  if opts.callback then table.insert(session_cache.waiters, opts.callback) end
  if session_cache.refresh_job then return end

  local cmd = codex_session_store_cmd("refresh")
  if not cmd then
    if not opts.silent then vim.notify("codex-session-store executable not found", vim.log.levels.ERROR) end
    finish_session_cache_refresh(session_cache.sessions, false)
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
      session_cache.refresh_job = nil

      if exit_code ~= 0 then
        if not opts.silent then
          local msg = stderr[1] and table.concat(stderr, "\n") or ("Codex session refresh failed: " .. exit_code)
          vim.notify(msg, vim.log.levels.ERROR)
        end
        finish_session_cache_refresh(session_cache.sessions, false)
        return
      end

      local decoded_ok, decoded = pcall(vim.json.decode, table.concat(stdout, "\n"))
      if not decoded_ok or type(decoded) ~= "table" or decoded.version ~= SESSION_CACHE_VERSION then
        if not opts.silent then vim.notify("Codex session refresh returned invalid JSON", vim.log.levels.ERROR) end
        finish_session_cache_refresh(session_cache.sessions, false)
        return
      end

      local sessions = valid_sessions(decoded.sessions)
      session_cache.loaded = true
      session_cache.sessions = sessions
      write_session_cache(sessions)
      finish_session_cache_refresh(sessions, true)
    end),
  })

  if job <= 0 then
    session_cache.refresh_job = nil
    if not opts.silent then vim.notify("Failed to start Codex session refresh", vim.log.levels.ERROR) end
    finish_session_cache_refresh(session_cache.sessions, false)
    return
  end

  session_cache.refresh_job = job
end

---@param sessions CodexStoredSession[]
---@return table<string, true>
local function session_ids(sessions)
  local ids = {}
  for _, session in ipairs(sessions) do
    ids[session.id] = true
  end
  return ids
end

local link_task_to_session

---@param command string[]
---@return Promise
local function session_watch_job(command)
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
          reject(stderr[1] and table.concat(stderr, "\n") or ("Codex session watch failed: " .. exit_code))
          return
        end

        local decoded_ok, decoded = pcall(vim.json.decode, table.concat(stdout, "\n"))
        if not decoded_ok or type(decoded) ~= "table" or decoded.version ~= SESSION_CACHE_VERSION then
          reject("Codex session watch returned invalid JSON")
          return
        end

        resolve(decoded)
      end),
    })

    if job <= 0 then reject("Failed to start Codex session watch") end
  end)
end

---@param cwd string
---@return Promise
local function async_sessions(cwd)
  local cmd = codex_session_store_cmd("refresh")
  if not cmd then return require("promise").reject("codex-session-store executable not found") end

  return session_watch_job(cmd):thenCall(function(decoded) return scoped_sessions(decoded.sessions, cwd) end)
end

---@param task overseer.Task
---@param session table
local function update_task_title(task, session)
  if type(session.title) ~= "string" or session.title == "" then return end
  task.name = "codex: " .. session.title
end

---@param session CodexStoredSession
---@return string
local function session_display_title(session)
  if type(session.title) == "string" and session.title ~= "" then return session.title end
  return "Untitled session"
end

---@param task overseer.Task
---@param command string[]
---@return Promise
local function watch_new_session_job(task, command)
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
      if not decoded_ok or type(decoded) ~= "table" or decoded.version ~= SESSION_CACHE_VERSION then return end

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
          reject(stderr[1] and table.concat(stderr, "\n") or ("Codex session watch failed: " .. exit_code))
          return
        end

        resolve_once()
      end),
    })

    if job <= 0 then reject("Failed to start Codex session watch") end
  end)
end

---@param cwd string
---@return Promise
local function async_session_ids(cwd)
  local cmd = codex_session_store_cmd("ids", cwd)
  if not cmd then return require("promise").reject("codex-session-store executable not found") end

  return session_watch_job(cmd):thenCall(function(decoded)
    local ids = {}
    if type(decoded.ids) ~= "table" then return ids end

    for _, id in ipairs(decoded.ids) do
      if type(id) == "string" then ids[id] = true end
    end

    return ids
  end)
end

---@param task overseer.Task
---@param cwd string
---@param known_session_ids table<string, true>
---@return Promise
local function async_watch_new_session(task, cwd, known_session_ids)
  local ids = {}
  for id in pairs(known_session_ids) do
    table.insert(ids, id)
  end

  local cmd = codex_session_store_cmd(
    "watch-new",
    cwd,
    vim.json.encode(ids),
    tostring(SESSION_LINK_TIMEOUT_MS / 1000),
    tostring(SESSION_LINK_POLL_INTERVAL_MS / 1000),
    tostring(SESSION_TITLE_TIMEOUT_MS / 1000)
  )
  if not cmd then return require("promise").reject("codex-session-store executable not found") end

  return watch_new_session_job(task, cmd)
end

---@param session CodexStoredSession
---@return number?
local function session_epoch_seconds(session)
  local compact_id = type(session.id) == "string" and session.id:gsub("%-", "") or nil
  local timestamp_hex = compact_id and compact_id:match("^([0-9a-fA-F]+)") or nil
  if not timestamp_hex or #timestamp_hex < 12 then return nil end

  return tonumber(timestamp_hex:sub(1, 12), 16) / 1000
end

---@param task overseer.Task
---@return boolean
local function is_unlinked_plain_codex_task(task)
  if task.status ~= require("overseer.constants").STATUS.RUNNING then return false end
  if task.metadata and task.metadata[CODEX_SESSION_ID_METADATA] then return false end
  if task.cmd ~= "codex" then return false end
  return type(task.args) ~= "table" or #task.args == 0
end

---@param task overseer.Task
---@param session CodexStoredSession
---@param known_session_ids? table<string, true>
---@return number?
local function unlinked_task_session_delta(task, session, known_session_ids)
  if known_session_ids and known_session_ids[session.id] then return nil end
  if not is_unlinked_plain_codex_task(task) then return nil end
  if task.cwd ~= session.cwd then return nil end
  if type(task.time_start) ~= "number" then return nil end

  local session_start = session_epoch_seconds(session)
  if not session_start then return nil end

  local delta = math.abs(session_start - task.time_start)
  if delta > SESSION_ORPHAN_MATCH_WINDOW_SECONDS then return nil end
  return delta
end

---@param task overseer.Task
---@param sessions CodexStoredSession[]
---@param known_session_ids? table<string, true>
---@return CodexStoredSession?
local function matching_unlinked_task_session(task, sessions, known_session_ids)
  local best_session
  local best_delta

  for _, session in ipairs(sessions) do
    local delta = unlinked_task_session_delta(task, session, known_session_ids)
    if delta and (not best_delta or delta < best_delta) then
      best_session = session
      best_delta = delta
    end
  end

  return best_session
end

---@param session CodexStoredSession
---@param tasks overseer.Task[]
---@return overseer.Task?
local function matching_unlinked_session_task(session, tasks)
  local best_task
  local best_delta

  for _, task in ipairs(tasks) do
    local delta = unlinked_task_session_delta(task, session)
    if delta and (not best_delta or delta < best_delta) then
      best_task = task
      best_delta = delta
    end
  end

  return best_task
end

---@param task overseer.Task
---@param cwd string
---@param known_session_ids table<string, true>
---@return Promise
local function async_link_task_to_recent_session(task, cwd, known_session_ids)
  return async_sessions(cwd):thenCall(function(sessions)
    local session = matching_unlinked_task_session(task, sessions, known_session_ids)
    if session then link_task_to_session(task, session) end
    return session
  end)
end

---@param task overseer.Task
---@return boolean
local function task_has_session_id(task)
  return type(task.metadata) == "table" and type(task.metadata[CODEX_SESSION_ID_METADATA]) == "string"
end

---@param task overseer.Task
---@return boolean
local function should_retry_session_link(task)
  if task_has_session_id(task) then return false end
  if type(task.is_disposed) ~= "function" then return true end

  local ok, disposed = pcall(task.is_disposed, task)
  return not ok or not disposed
end

---@param task overseer.Task
---@param cwd string
---@param known_session_ids table<string, true>
local function retry_link_task_until_session_id(task, cwd, known_session_ids)
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

    async_link_task_to_recent_session(task, cwd, known_session_ids)
      :thenCall(function()
        session_link_retry_tasks[task] = nil
        if should_retry_session_link(task) then retry_link_task_until_session_id(task, cwd, known_session_ids) end
      end)
      :catch(function()
        session_link_retry_tasks[task] = nil
        if should_retry_session_link(task) then retry_link_task_until_session_id(task, cwd, known_session_ids) end
      end)
  end

  vim.defer_fn(retry, SESSION_LINK_RETRY_INTERVAL_MS)
end

---@param timestamp string
---@return string
local function format_timestamp(timestamp) return timestamp:gsub("T", " "):gsub("%..+$", ""):gsub("Z$", "") end

---@param winid integer
---@return boolean
local function is_floating_win(winid)
  return vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_config(winid).relative ~= ""
end

---@param preferred_win integer?
---@return integer?
local function non_floating_win(preferred_win)
  if preferred_win and vim.api.nvim_win_is_valid(preferred_win) and not is_floating_win(preferred_win) then
    return preferred_win
  end

  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(winid) and not is_floating_win(winid) then return winid end
  end
end

---@param preferred_win integer?
local function restore_non_floating_win(preferred_win)
  local winid = non_floating_win(preferred_win)
  if winid then pcall(vim.api.nvim_set_current_win, winid) end
end

---@param task overseer.Task
---@param preferred_win integer?
local function ensure_overseer_terminal(task, preferred_win)
  ---@diagnostic disable-next-line: invisible
  local strategy = task.strategy
  if not strategy or strategy.term_id or type(strategy._create_terminal) ~= "function" then return end

  restore_non_floating_win(preferred_win)
  strategy:_create_terminal()
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
---@param session CodexStoredSession
function link_task_to_session(task, session)
  task.metadata = task.metadata or {}
  task.metadata[CODEX_TASK_METADATA] = true
  task.metadata[CODEX_SESSION_ID_METADATA] = session.id
  task.metadata[CODEX_SESSION_PATH_METADATA] = session.path
  task.metadata[CODEX_SESSION_UPDATED_AT_METADATA] = session.updated_at
  update_task_title(task, session)
end

---@param task overseer.Task
---@return integer?
function M.task_session_mtime(task)
  local path = task.metadata and task.metadata[CODEX_SESSION_PATH_METADATA] or nil
  if type(path) ~= "string" then return nil end

  local stat = vim.uv.fs_stat(path)
  return stat and stat.mtime and stat.mtime.sec or nil
end

---@param session CodexStoredSession
---@return overseer.Task?
local function running_task_for_session(session)
  local STATUS = require("overseer.constants").STATUS
  local tasks = require("overseer").list_tasks({ status = STATUS.RUNNING })
  for _, task in ipairs(tasks) do
    if task.metadata and task.metadata[CODEX_SESSION_ID_METADATA] == session.id then
      link_task_to_session(task, session)
      return task
    end
    if task_references_session_id(task, session.id) then
      link_task_to_session(task, session)
      return task
    end
  end

  local task = matching_unlinked_session_task(session, tasks)
  if task then
    link_task_to_session(task, session)
    return task
  end
end

---@param output string
---@param cwd? string
---@return boolean
local function codex_ready(output, cwd)
  local text = output:gsub("[\27\155][][()#;?%d]*[A-PRZcf-ntqry=><~]", "")
  return text:find("OpenAI Codex", 1, true) ~= nil
    or (text:find("model:", 1, true) ~= nil and text:find("directory:", 1, true) ~= nil)
    or (cwd ~= nil and text:find(vim.fn.fnamemodify(cwd, ":~"), 1, true) ~= nil)
end

---@class CodexSessionOpts
---@field visual? boolean
---@field wait_for_codex_ready? boolean
---@field all? boolean

---@param opts? CodexSessionOpts
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
local function prompt_from_codex_task_under_cursor()
  local task = current_overseer_task()
  local session_id = task and task.metadata and task.metadata[CODEX_SESSION_ID_METADATA] or nil
  if type(session_id) ~= "string" or session_id == "" then return nil end

  return ("continuando con esta conversación de codex con id: %s\n\n"):format(session_id)
end

---@param opts? CodexSessionOpts
---@return string? prompt
---@return string? label
local function prompt_from_context(opts)
  local prompt_parts = {}
  local continuation_prompt = prompt_from_codex_task_under_cursor()
  if continuation_prompt then table.insert(prompt_parts, continuation_prompt) end

  local visual_prompt, label = prompt_from_visual_selection(opts)
  if visual_prompt then table.insert(prompt_parts, visual_prompt) end

  if #prompt_parts == 0 then return nil, label end
  return table.concat(prompt_parts), label
end

---@param task overseer.Task
---@param prompt? string
local function paste_prompt(task, prompt)
  if not prompt or prompt == "" then return end

  local function send()
    local job_id = task_job_id(task)
    if not job_id then return false end

    local ok, err = pcall(vim.api.nvim_chan_send, job_id, "\27[200~" .. prompt .. "\27[201~")
    if not ok then vim.notify("Could not paste selection into Codex: " .. err, vim.log.levels.ERROR) end
    return ok
  end

  if not task.metadata.wait_for_codex_ready then
    send()
    return
  end

  local sent = false
  local output_tail = ""
  task:subscribe("on_output", function(_, data)
    output_tail = (output_tail .. output_to_string(data)):sub(-4000)
    if sent or not codex_ready(output_tail, task.cwd) then return end
    sent = send()
  end)
end

---@param task overseer.Task
---@param cwd string
---@param known_session_ids table<string, true>
local function link_new_task_to_session_id(task, cwd, known_session_ids)
  async_watch_new_session(task, cwd, known_session_ids)
    :thenCall(function()
      if task_has_session_id(task) then return end
      retry_link_task_until_session_id(task, cwd, known_session_ids)
    end)
    :catch(function(err)
      vim.notify(tostring(err), vim.log.levels.ERROR)
      retry_link_task_until_session_id(task, cwd, known_session_ids)
    end)
end

---@param task overseer.Task
---@param prompt? string
---@param opts? CodexSessionOpts
local function open_task(task, prompt, opts)
  opts = opts or {}
  task.metadata = task.metadata or {}
  task.metadata.wait_for_codex_ready = opts.wait_for_codex_ready == true
  utils.attach_keymaps(task)
  utils.force_very_fullscreen_float(task)
  utils.start_insert_mode(task)
  utils.schedule_open_overseer_task_float(task)
  utils.refresh_task_terminal_window(task)
  paste_prompt(task, prompt)
end

---@param session CodexStoredSession
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

---@param sessions CodexStoredSession[]
---@param opts CodexSessionOpts
---@param loading? boolean
---@return string[]
local function session_fzf_entries(sessions, opts, loading)
  if loading then return { "__codex-loading\tLoading Codex sessions..." } end

  if #sessions == 0 then
    local scope = opts.all and "any working directory" or vim.fn.getcwd()
    return { "__codex-empty\tNo Codex sessions found for " .. fzf_field(scope) }
  end

  local entries = {}
  for _, session in ipairs(sessions) do
    table.insert(entries, ("%s\t%s"):format(session.id, fzf_field(format_session(session, opts.all))))
  end
  return entries
end

---@param sessions CodexStoredSession[]
---@return table<string, CodexStoredSession>
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

---@param session CodexStoredSession
---@param prompt? string
---@param start_win integer
local function resume_session(session, prompt, start_win)
  restore_non_floating_win(start_win)

  local existing_task = running_task_for_session(session)
  if existing_task then
    open_task(existing_task, prompt)
    ensure_overseer_terminal(existing_task, start_win)
    return
  end

  local task = require("overseer").new_task({
    name = "codex resume: " .. session_display_title(session),
    cmd = "codex",
    args = { "resume", "--no-alt-screen", "-C", session.cwd, session.id },
    cwd = session.cwd,
    metadata = {
      [CODEX_TASK_METADATA] = true,
      [CODEX_SESSION_ID_METADATA] = session.id,
      [CODEX_SESSION_PATH_METADATA] = session.path,
      [CODEX_SESSION_UPDATED_AT_METADATA] = session.updated_at,
    },
    components = {
      { "open_output", direction = "float", on_start = "always", focus = true },
      "defaults_without_notification",
    },
  })

  open_task(task, prompt, { wait_for_codex_ready = true })
  task:start()
  ensure_overseer_terminal(task, start_win)
end

---@param session_id string?
---@param active_sessions_by_id table<string, CodexStoredSession>
---@param prompt? string
---@param start_win integer
---@return boolean
local function resume_selected_session_id(session_id, active_sessions_by_id, prompt, start_win)
  session_id = agent_session_id(session_id)
  local session = session_id and active_sessions_by_id[session_id] or nil
  if not session then return false end

  vim.schedule(function() resume_session(session, prompt, start_win) end)
  return true
end

---@param opts? CodexSessionOpts
function M.select(opts)
  opts = opts or {}
  local prompt = prompt_from_context(opts)
  local cached_sessions = read_session_cache()
  local sessions = scoped_sessions(cached_sessions, nil, { all = opts.all == true })
  local has_cache = cached_sessions ~= nil
  local active_sessions_by_id = sessions_by_id(sessions)
  local start_win = vim.api.nvim_get_current_win()

  utils.fzf({
    source = session_fzf_entries(sessions, opts, not has_cache),
    prompt = opts.all and "Codex sessions (all cwd)" or "Codex sessions",
    options = {
      "--delimiter='\t'",
      "--with-nth=2..",
    },
    refresh = function(reload)
      refresh_session_cache({
        silent = true,
        callback = function(refreshed_sessions, ok)
          if not ok then return end

          sessions = scoped_sessions(refreshed_sessions, nil, { all = opts.all == true })
          active_sessions_by_id = sessions_by_id(sessions)
          reload(session_fzf_entries(sessions, opts))
        end,
      })
    end,
    sink = function(entry)
      local session_id = entry:match("^([^\t]+)\t")
      resume_selected_session_id(session_id, active_sessions_by_id, prompt, start_win)
    end,
  })
end

---@param opts? CodexSessionOpts
function M.open_new(opts)
  if vim.fn.executable("codex") ~= 1 then
    vim.api.nvim_echo({ { "codex executable not found", "DiagnosticError" } }, false, {})
    return
  end

  local prompt, label = prompt_from_context(opts)
  local cwd = vim.fn.getcwd()
  local label_or_source = label or current_source_label()

  require("async")(function()
    local known_session_ids = await(async_session_ids(cwd))
    local task = require("overseer").new_task({
      name = task_name(cwd, label_or_source),
      cmd = "codex",
      cwd = cwd,
      metadata = {
        [CODEX_TASK_METADATA] = true,
      },
      components = {
        { "open_output", direction = "float", on_start = "always", focus = true },
        "defaults_without_notification",
      },
    })

    open_task(task, prompt, { wait_for_codex_ready = true })
    task:start()
    link_new_task_to_session_id(task, cwd, known_session_ids)
  end):catch(function(err) vim.notify(tostring(err), vim.log.levels.ERROR) end)
end

function M.keys()
  local module = "serranomorante.plugins.jobs.codex_sessions"

  vim.api.nvim_create_user_command("CodexResumeById", function(command_args)
    local session_id = agent_session_id(command_args.args)
    if not session_id then return vim.notify("Codex session id is required", vim.log.levels.ERROR) end

    local start_win = vim.api.nvim_get_current_win()
    local cached_sessions = read_session_cache()
    if cached_sessions and resume_selected_session_id(session_id, sessions_by_id(cached_sessions), nil, start_win) then
      return
    end

    refresh_session_cache({
      silent = true,
      callback = function(refreshed_sessions, ok)
        if ok and resume_selected_session_id(session_id, sessions_by_id(refreshed_sessions or {}), nil, start_win) then
          return
        end
        vim.notify("Codex session not found: " .. session_id, vim.log.levels.ERROR)
      end,
    })
  end, {
    force = true,
    nargs = 1,
    desc = "Resume a Codex session in Overseer by id",
  })

  vim.keymap.set("n", "<leader>cl", function() require(module).select() end, { desc = "Codex: Resume project session" })
  vim.keymap.set(
    "n",
    "<leader>cL",
    function() require(module).select({ all = true }) end,
    { desc = "Codex: Resume any session" }
  )
  vim.keymap.set(
    "x",
    "<leader>cl",
    function() require(module).select({ visual = true }) end,
    { desc = "Codex: Resume project session" }
  )
  vim.keymap.set(
    "x",
    "<leader>cL",
    function() require(module).select({ visual = true, all = true }) end,
    { desc = "Codex: Resume any session" }
  )
  vim.keymap.set("n", "<leader>cn", function() require(module).open_new() end, { desc = "Codex: New Overseer session" })
  vim.keymap.set(
    "x",
    "<leader>cn",
    function() require(module).open_new({ visual = true }) end,
    { desc = "Codex: New Overseer session" }
  )
end

return M
