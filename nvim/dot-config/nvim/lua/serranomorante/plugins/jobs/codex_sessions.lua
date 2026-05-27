local utils = require("serranomorante.utils")

local M = {}

local CODEX_TASK_METADATA = "codex_session"
local CODEX_SESSION_ID_METADATA = "codex_session_id"
local CODEX_SESSIONS_DIR = vim.fn.expand("~/.codex/sessions")
local SESSION_CACHE_VERSION = 1
local SESSION_CACHE_NAMESPACE = "nvim"
local SESSION_CACHE_KEY = "codex-sessions-v1"
local SESSION_CACHE_TTL_SECONDS = 7 * 24 * 60 * 60
local SESSION_LINK_POLL_INTERVAL_MS = 500
local SESSION_LINK_TIMEOUT_MS = 60 * 1000
local SESSION_TITLE_TIMEOUT_MS = 10 * 60 * 1000

local session_cache = {
  loaded = false,
  sessions = nil,
  refresh_job = nil,
  waiters = {},
}

local CODEX_SESSION_REFRESH_SCRIPT = [=[
import json
import os
import sys
import time

root = sys.argv[1]


def compact_text(text):
    if not text:
        return None
    text = " ".join(str(text).split())
    return text or None


def is_generated_context_message(text):
    text = compact_text(text)
    if not text:
        return False
    return (
        text.startswith("# AGENTS.md instructions for ")
        or text.startswith("<environment_context>")
        or text.startswith("<permissions instructions>")
        or text.startswith("<collaboration_mode>")
        or text.startswith("<skills_instructions>")
    )


def normalize_title(text):
    text = compact_text(text)
    if not text or is_generated_context_message(text):
        return None
    return text


def content_text(content):
    if isinstance(content, str):
        return content
    if not isinstance(content, list):
        return None

    parts = []
    for item in content:
        if isinstance(item, str):
            parts.append(item)
        elif isinstance(item, dict) and isinstance(item.get("text"), str):
            parts.append(item["text"])
    return " ".join(parts)


def user_message_title(payload):
    if payload.get("type") == "user_message":
        return normalize_title(payload.get("message"))
    if payload.get("type") == "message" and payload.get("role") == "user":
        return normalize_title(content_text(payload.get("content")))
    return None


def parse_session(path):
    session = {"path": path}
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            data = handle.read(512 * 1024)
    except OSError:
        return None

    for line in data.splitlines():
        try:
            item = json.loads(line)
        except json.JSONDecodeError:
            continue

        payload = item.get("payload")
        if not isinstance(payload, dict):
            continue

        if item.get("type") == "session_meta":
            session["id"] = payload.get("id")
            session["cwd"] = payload.get("cwd")
            session["timestamp"] = payload.get("timestamp")
            session["originator"] = payload.get("originator")

        if not session.get("title"):
            session["title"] = user_message_title(payload)

        if session.get("id") and session.get("cwd") and session.get("timestamp") and session.get("title"):
            break

    if not (
        session.get("id")
        and session.get("cwd")
        and session.get("timestamp")
        and session.get("originator") == "codex-tui"
    ):
        return None

    session["title"] = session.get("title") or "Untitled session"
    return session


sessions = []
for dirpath, _dirnames, filenames in os.walk(root):
    for filename in filenames:
        if not filename.endswith(".jsonl"):
            continue
        session = parse_session(os.path.join(dirpath, filename))
        if session:
            sessions.append(session)

sessions.sort(key=lambda item: item.get("timestamp", ""), reverse=True)
print(json.dumps({"version": 1, "generated_at": int(time.time()), "sessions": sessions}, separators=(",", ":")))
]=]

local CODEX_SESSION_WATCH_SCRIPT = [=[
import json
import os
import sys
import time

root = sys.argv[1]
mode = sys.argv[2]
cwd = sys.argv[3]


def compact_text(text):
    if not text:
        return None
    text = " ".join(str(text).split())
    return text or None


def is_generated_context_message(text):
    text = compact_text(text)
    if not text:
        return False
    return (
        text.startswith("# AGENTS.md instructions for ")
        or text.startswith("<environment_context>")
        or text.startswith("<permissions instructions>")
        or text.startswith("<collaboration_mode>")
        or text.startswith("<skills_instructions>")
    )


def normalize_title(text):
    text = compact_text(text)
    if not text or is_generated_context_message(text):
        return None
    return text


def content_text(content):
    if isinstance(content, str):
        return content
    if not isinstance(content, list):
        return None

    parts = []
    for item in content:
        if isinstance(item, str):
            parts.append(item)
        elif isinstance(item, dict) and isinstance(item.get("text"), str):
            parts.append(item["text"])
    return " ".join(parts)


def user_message_title(payload):
    if payload.get("type") == "user_message":
        return normalize_title(payload.get("message"))
    if payload.get("type") == "message" and payload.get("role") == "user":
        return normalize_title(content_text(payload.get("content")))
    return None


def parse_session(path):
    session = {"path": path}
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as handle:
            data = handle.read(512 * 1024)
    except OSError:
        return None

    for line in data.splitlines():
        try:
            item = json.loads(line)
        except json.JSONDecodeError:
            continue

        payload = item.get("payload")
        if not isinstance(payload, dict):
            continue

        if item.get("type") == "session_meta":
            session["id"] = payload.get("id")
            session["cwd"] = payload.get("cwd")
            session["timestamp"] = payload.get("timestamp")
            session["originator"] = payload.get("originator")

        if not session.get("title"):
            session["title"] = user_message_title(payload)

        if session.get("id") and session.get("cwd") and session.get("timestamp") and session.get("title"):
            break

    if (
        not session.get("id")
        or session.get("cwd") != cwd
        or session.get("originator") != "codex-tui"
    ):
        return None

    return session


def sessions_for_cwd():
    sessions = []
    for dirpath, _dirnames, filenames in os.walk(root):
        for filename in filenames:
            if not filename.endswith(".jsonl"):
                continue
            session = parse_session(os.path.join(dirpath, filename))
            if session:
                sessions.append(session)
    sessions.sort(key=lambda item: item.get("timestamp", ""), reverse=True)
    return sessions


def emit(payload):
    print(json.dumps(payload, separators=(",", ":")), flush=True)


if mode == "ids":
    emit({"version": 1, "ids": [item["id"] for item in sessions_for_cwd()]})
elif mode == "wait-new":
    known_ids = set(json.loads(sys.argv[4]))
    timeout_seconds = float(sys.argv[5])
    interval_seconds = float(sys.argv[6])
    deadline = time.monotonic() + timeout_seconds

    while True:
        for session in sessions_for_cwd():
            if session["id"] not in known_ids:
                emit({"version": 1, "session": session})
                sys.exit(0)

        if time.monotonic() >= deadline:
            emit({"version": 1, "session": None})
            sys.exit(0)

        time.sleep(interval_seconds)
elif mode == "watch-new":
    known_ids = set(json.loads(sys.argv[4]))
    timeout_seconds = float(sys.argv[5])
    interval_seconds = float(sys.argv[6])
    title_timeout_seconds = float(sys.argv[7])
    deadline = time.monotonic() + timeout_seconds
    new_session = None

    while True:
        for session in sessions_for_cwd():
            if session["id"] not in known_ids:
                new_session = session
                emit({"version": 1, "event": "session", "session": session})
                break

        if new_session:
            break

        if time.monotonic() >= deadline:
            emit({"version": 1, "event": "timeout"})
            sys.exit(0)

        time.sleep(interval_seconds)

    if new_session.get("title"):
        emit({"version": 1, "event": "title", "session": new_session})
        sys.exit(0)

    title_deadline = time.monotonic() + title_timeout_seconds
    while True:
        for session in sessions_for_cwd():
            if session["id"] == new_session["id"] and session.get("title"):
                emit({"version": 1, "event": "title", "session": session})
                sys.exit(0)

        if time.monotonic() >= title_deadline:
            sys.exit(0)

        time.sleep(interval_seconds)
else:
    print("unknown mode: " + mode, file=sys.stderr)
    sys.exit(2)
]=]

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
    if
      type(session) == "table"
      and type(session.id) == "string"
      and type(session.cwd) == "string"
      and type(session.timestamp) == "string"
      and type(session.title) == "string"
      and type(session.path) == "string"
      and (session.originator == nil or type(session.originator) == "string")
    then
      table.insert(valid, session)
    end
  end

  table.sort(valid, function(a, b) return a.timestamp > b.timestamp end)
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

---@param text string?
---@return string?
local function compact_text(text)
  if not text or text == "" then return nil end
  text = text:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then return nil end
  return text
end

---@param text string?
---@return boolean
local function is_generated_context_message(text)
  text = compact_text(text)
  if not text then return false end

  return text:find("^# AGENTS%.md instructions for ") ~= nil
    or text:find("^<environment_context>") ~= nil
    or text:find("^<permissions instructions>") ~= nil
    or text:find("^<collaboration_mode>") ~= nil
    or text:find("^<skills_instructions>") ~= nil
end

---@param text string?
---@return string?
local function normalize_title(text)
  text = compact_text(text)
  if not text or is_generated_context_message(text) then return nil end
  return text
end

---@param content any
---@return string?
local function content_text(content)
  if type(content) == "string" then return content end
  if type(content) ~= "table" then return nil end

  local parts = {}
  for _, item in ipairs(content) do
    if type(item) == "string" then
      table.insert(parts, item)
    elseif type(item) == "table" and type(item.text) == "string" then
      table.insert(parts, item.text)
    end
  end

  return table.concat(parts, " ")
end

---@param payload table
---@return string?
local function user_message_title(payload)
  if payload.type == "user_message" then return normalize_title(payload.message) end
  if payload.type == "message" and payload.role == "user" then return normalize_title(content_text(payload.content)) end
  return nil
end

---@param root string
---@return string[]
local function session_files(root)
  local files = {}

  local function scan(dir)
    local handle = vim.uv.fs_scandir(dir)
    if not handle then return end

    while true do
      local name, kind = vim.uv.fs_scandir_next(handle)
      if not name then break end

      local path = utils.join_paths(dir, name)
      if kind == "directory" then
        scan(path)
      elseif kind == "file" and name:match("%.jsonl$") then
        table.insert(files, path)
      end
    end
  end

  scan(root)
  return files
end

---@class CodexStoredSession
---@field id string
---@field cwd string
---@field timestamp string
---@field title string
---@field path string
---@field originator string?

---@param path string
---@param cwd? string
---@return CodexStoredSession?
local function parse_session(path, cwd)
  local fd = vim.uv.fs_open(path, "r", 438)
  if not fd then return nil end

  local stat = vim.uv.fs_fstat(fd)
  local data = stat and vim.uv.fs_read(fd, math.min(stat.size, 512 * 1024), 0) or nil
  vim.uv.fs_close(fd)
  if not data then return nil end

  local session = { path = path }
  for line in data:gmatch("([^\n]+)") do
    local ok, item = pcall(vim.json.decode, line)
    if ok and type(item) == "table" and type(item.payload) == "table" then
      if item.type == "session_meta" then
        session.id = item.payload.id
        session.cwd = item.payload.cwd
        session.timestamp = item.payload.timestamp
        session.originator = item.payload.originator
      end

      session.title = session.title or user_message_title(item.payload)
      if session.id and session.cwd and session.timestamp and session.title then break end
    end
  end

  if (cwd and session.cwd ~= cwd) or not session.id or not session.timestamp or session.originator ~= "codex-tui" then
    return nil
  end
  session.title = session.title or "Untitled session"
  return session
end

---@param cwd? string
---@param opts? { all?: boolean }
---@return CodexStoredSession[]
local function stored_sessions(cwd, opts)
  opts = opts or {}
  if opts.all then
    cwd = nil
  else
    cwd = cwd or vim.fn.getcwd()
  end

  local sessions = {}

  for _, path in ipairs(session_files(CODEX_SESSIONS_DIR)) do
    local session = parse_session(path, cwd)
    if session then table.insert(sessions, session) end
  end

  table.sort(sessions, function(a, b) return a.timestamp > b.timestamp end)
  return sessions
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

  if vim.fn.executable("python3") ~= 1 then
    vim.defer_fn(function()
      local sessions = stored_sessions(nil, { all = true })
      session_cache.loaded = true
      session_cache.sessions = sessions
      write_session_cache(sessions)
      finish_session_cache_refresh(sessions, true)
    end, 10)
    return
  end

  local stdout = {}
  local stderr = {}
  local job = vim.fn.jobstart({ "python3", "-c", CODEX_SESSION_REFRESH_SCRIPT, CODEX_SESSIONS_DIR }, {
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

---@param task overseer.Task
---@param session table
local function update_task_title(task, session)
  if type(session.title) ~= "string" or session.title == "" then return end
  task.name = "codex: " .. session.title
end

---@param task overseer.Task
---@param command string[]
---@return Promise
local function watch_new_session_job(task, command)
  return require("promise")(function(resolve, reject)
    local stdout_pending = ""
    local stderr = {}
    local resolved = false

    local function resolve_once()
      if resolved then return end
      resolved = true
      resolve()
    end

    local function handle_line(line)
      if line == "" then return end

      local decoded_ok, decoded = pcall(vim.json.decode, line)
      if not decoded_ok or type(decoded) ~= "table" or decoded.version ~= SESSION_CACHE_VERSION then return end

      if decoded.event == "session" and type(decoded.session) == "table" then
        link_task_to_session(task, decoded.session)
      elseif decoded.event == "title" and type(decoded.session) == "table" then
        link_task_to_session(task, decoded.session)
        resolve_once()
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
  if vim.fn.executable("python3") ~= 1 then return require("promise").reject("python3 executable not found") end

  return session_watch_job({ "python3", "-c", CODEX_SESSION_WATCH_SCRIPT, CODEX_SESSIONS_DIR, "ids", cwd }):thenCall(
    function(decoded)
      local ids = {}
      if type(decoded.ids) ~= "table" then return ids end

      for _, id in ipairs(decoded.ids) do
        if type(id) == "string" then ids[id] = true end
      end

      return ids
    end
  )
end

---@param task overseer.Task
---@param cwd string
---@param known_session_ids table<string, true>
---@return Promise
local function async_watch_new_session(task, cwd, known_session_ids)
  if vim.fn.executable("python3") ~= 1 then return require("promise").reject("python3 executable not found") end

  local ids = {}
  for id in pairs(known_session_ids) do
    table.insert(ids, id)
  end

  return watch_new_session_job(task, {
    "python3",
    "-c",
    CODEX_SESSION_WATCH_SCRIPT,
    CODEX_SESSIONS_DIR,
    "watch-new",
    cwd,
    vim.json.encode(ids),
    tostring(SESSION_LINK_TIMEOUT_MS / 1000),
    tostring(SESSION_LINK_POLL_INTERVAL_MS / 1000),
    tostring(SESSION_TITLE_TIMEOUT_MS / 1000),
  })
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
  task.metadata[CODEX_SESSION_ID_METADATA] = session.id
  update_task_title(task, session)
end

---@param session CodexStoredSession
---@return overseer.Task?
local function running_task_for_session(session)
  local STATUS = require("overseer.constants").STATUS
  for _, task in ipairs(require("overseer").list_tasks({ status = STATUS.RUNNING })) do
    if task.metadata and task.metadata[CODEX_SESSION_ID_METADATA] == session.id then
      link_task_to_session(task, session)
      return task
    end
    if task_references_session_id(task, session.id) then
      link_task_to_session(task, session)
      return task
    end
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
  async_watch_new_session(task, cwd, known_session_ids):catch(
    function(err) vim.notify(tostring(err), vim.log.levels.ERROR) end
  )
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
  paste_prompt(task, prompt)
end

---@param session CodexStoredSession
---@param include_cwd? boolean
---@return string
local function format_session(session, include_cwd)
  local label = ("%s | %s"):format(format_timestamp(session.timestamp), session.title)
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
    name = "codex resume: " .. session.title,
    cmd = "codex",
    args = { "resume", "--no-alt-screen", "-C", session.cwd, session.id },
    cwd = session.cwd,
    metadata = {
      [CODEX_TASK_METADATA] = true,
      [CODEX_SESSION_ID_METADATA] = session.id,
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

---@param opts? CodexSessionOpts
function M.select(opts)
  opts = opts or {}
  local prompt = prompt_from_visual_selection(opts)
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
      local session = session_id and active_sessions_by_id[session_id] or nil
      if not session then return end
      vim.schedule(function() resume_session(session, prompt, start_win) end)
    end,
  })
end

---@param opts? CodexSessionOpts
function M.open_new(opts)
  if vim.fn.executable("codex") ~= 1 then
    vim.api.nvim_echo({ { "codex executable not found", "DiagnosticError" } }, false, {})
    return
  end

  local prompt, label = prompt_from_visual_selection(opts)
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
