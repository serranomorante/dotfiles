local utils = require("serranomorante.utils")

local M = {}

local PLAYBOOKS_DIR = vim.env.HOME .. "/dotfiles/playbooks"
local TASK_CACHE_VERSION = 1
local TASK_CACHE_NAMESPACE = "nvim"
local TASK_CACHE_KEY = "ansible-task-picker"
local TASK_CACHE_TTL_SECONDS = 7 * 24 * 60 * 60

local task_cache = {
  loaded = false,
  public_items = nil,
  source_mtime = 0,
  refresh_job = nil,
  waiters = {},
}

local MANUAL_TASK_ITEMS = {
  "all", -- all tasks
  "setup", -- base tasks like running stow
  "never", -- very slow tasks that I rarely need to perform
  "always", -- tasks that should always be executed
  "20-50,20-60 [Full editor setup]",
  "10-170,20-170 [Full AI setup]",
  "10-170,40-20 [Full browser extensions]",
  "10-180,10-181 [Full borg backup setup]",
  "10-system-tools,20-dev-tools,30-lang-tools,40-PKM,80-for-my-eyes-only [Base setup]",
}

local function cachectl_bin()
  local configured_bin = vim.env.CACHECTL_BIN
  if configured_bin and configured_bin ~= "" and vim.fn.executable(configured_bin) == 1 then return configured_bin end

  local repo_bin = utils.join_paths(vim.env.HOME, "dotfiles", "utilities", "bin", "cachectl")
  if vim.fn.executable(repo_bin) == 1 then return repo_bin end
  if vim.fn.executable("cachectl") == 1 then return "cachectl" end
end

local function cachectl_cmd(...)
  local bin = cachectl_bin()
  if not bin then return end

  return vim.list_extend({ bin }, { ... })
end

local function latest_playbook_mtime()
  local latest = 0
  for _, pattern in ipairs({ PLAYBOOKS_DIR .. "/**/*.yml", PLAYBOOKS_DIR .. "/**/*.yaml" }) do
    for _, path in ipairs(vim.fn.glob(pattern, false, true)) do
      local stat = (vim.uv or vim.loop).fs_stat(path)
      if stat and stat.mtime and stat.mtime.sec > latest then latest = stat.mtime.sec end
    end
  end
  return latest
end

local function dedupe_items(items)
  local unique_items = {}
  local seen = {}
  for _, item in ipairs(items) do
    if not seen[item] then
      table.insert(unique_items, item)
      seen[item] = true
    end
  end
  return unique_items
end

local function append_private_tasks(items)
  local ok, private_tasks = pcall(require, "serranomorante.private-tasks")
  if ok and type(private_tasks) == "table" then vim.list_extend(items, private_tasks) end
end

local function picker_items(public_items)
  local items = vim.deepcopy(public_items or {})
  vim.list_extend(items, MANUAL_TASK_ITEMS)
  append_private_tasks(items)
  return dedupe_items(items)
end

local function parse_task_items(lines)
  local items = {}

  for _, line in ipairs(lines) do
    -- Look for lines that contain tasks (have leading spaces and contain TAGS:)
    if line:match("^%s+.*TAGS:") then
      -- Extract task name (before TAGS:)
      local task_part = line:match("^%s+(.-)%s+TAGS:")
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

  return dedupe_items(items)
end

local function read_task_cache()
  if task_cache.loaded then return task_cache.public_items, task_cache.source_mtime end
  task_cache.loaded = true

  local cmd = cachectl_cmd("get", TASK_CACHE_NAMESPACE, TASK_CACHE_KEY)
  if not cmd then return nil, 0 end

  local result = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 or result == "" then return nil, 0 end

  local decoded_ok, decoded = pcall(vim.json.decode, result)
  if
    not decoded_ok
    or type(decoded) ~= "table"
    or decoded.version ~= TASK_CACHE_VERSION
    or type(decoded.public_items) ~= "table"
  then
    return nil, 0
  end

  task_cache.public_items = decoded.public_items
  task_cache.source_mtime = tonumber(decoded.source_mtime) or 0
  return task_cache.public_items, task_cache.source_mtime
end

local function write_task_cache(public_items, source_mtime)
  local cmd = cachectl_cmd("set", TASK_CACHE_NAMESPACE, TASK_CACHE_KEY, tostring(TASK_CACHE_TTL_SECONDS))
  if not cmd then return end

  local payload = {
    version = TASK_CACHE_VERSION,
    source_mtime = source_mtime,
    public_items = public_items,
  }

  pcall(vim.fn.system, cmd, vim.json.encode(payload))
end

local function finish_task_cache_refresh(public_items, ok)
  local waiters = task_cache.waiters
  task_cache.waiters = {}

  for _, callback in ipairs(waiters) do
    callback(public_items, ok)
  end
end

local function refresh_task_cache(opts)
  opts = opts or {}
  if opts.callback then table.insert(task_cache.waiters, opts.callback) end
  if task_cache.refresh_job then return end

  local lines = {}
  local stderr = {}

  local job = vim.fn.jobstart({ "ansible-playbook", "tools.yml", "-l", "localhost", "--list-tasks" }, {
    cwd = PLAYBOOKS_DIR,
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, result)
      for _, line in ipairs(result) do
        if line ~= "" then table.insert(lines, line) end
      end
    end,
    on_stderr = function(_, result)
      for _, line in ipairs(result) do
        if line ~= "" then table.insert(stderr, line) end
      end
    end,
    on_exit = vim.schedule_wrap(function(_, exit_code)
      task_cache.refresh_job = nil

      if exit_code ~= 0 then
        if not opts.silent then
          local msg = stderr[1] and table.concat(stderr, "\n") or ("Command failed with exit code: " .. exit_code)
          vim.notify(msg, vim.log.levels.ERROR)
        end
        finish_task_cache_refresh(task_cache.public_items, false)
        return
      end

      local public_items = parse_task_items(lines)
      if #public_items == 0 then
        if not opts.silent then vim.notify("No tasks with numeric tags found", vim.log.levels.WARN) end
        finish_task_cache_refresh(task_cache.public_items, false)
        return
      end

      task_cache.loaded = true
      task_cache.public_items = public_items
      task_cache.source_mtime = opts.source_mtime or latest_playbook_mtime()
      write_task_cache(public_items, task_cache.source_mtime)
      finish_task_cache_refresh(public_items, true)
    end),
  })

  if job <= 0 then
    task_cache.refresh_job = nil
    if not opts.silent then vim.notify("Failed to start ansible-playbook", vim.log.levels.ERROR) end
    finish_task_cache_refresh(task_cache.public_items, false)
    return
  end

  task_cache.refresh_job = job
end

local function refresh_task_cache_if_stale(cache_mtime)
  vim.defer_fn(function()
    local source_mtime = latest_playbook_mtime()
    if cache_mtime < source_mtime then refresh_task_cache({ silent = true, source_mtime = source_mtime }) end
  end, 10)
end

local function run_selected_playbook_task(choice, opts)
  if not choice then return end
  opts = opts or {}

  local playbooks = require("overseer.template.system-tasks.TASK__run_ansible_playbook")
  require("overseer").run_task({
    name = playbooks.name,
    params = { task_id = choice, pass = vim.g.pass },
  }, function(task)
    if not task then return end
    utils.attach_keymaps(task)
    utils.schedule_open_overseer_task_output(task, { winid = opts.winid })
  end)
end

local function select_playbook_task(public_items)
  local source_winid = vim.api.nvim_get_current_win()
  local items = picker_items(public_items)
  if #items == 0 then
    vim.notify("No tasks with numeric tags found", vim.log.levels.WARN)
    return
  end

  vim.ui.select(items, {
    prompt = "Ansible tasks",
    format_item = function(item) return item end,
  }, function(choice) run_selected_playbook_task(choice, { winid = source_winid }) end)
end

function M.select()
  local public_items, cache_mtime = read_task_cache()

  if public_items and #public_items > 0 then
    select_playbook_task(public_items)
    refresh_task_cache_if_stale(cache_mtime)
    return
  end

  vim.notify("Loading Ansible task list...", vim.log.levels.INFO)
  refresh_task_cache({
    callback = function(refreshed_items, ok)
      if ok then select_playbook_task(refreshed_items) end
    end,
  })
end

return M
