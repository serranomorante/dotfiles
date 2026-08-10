local task_name = "run-ansible-playbook"
local HOME = vim.env.HOME
local PLAYBOOKS_DIR = ("%s/dotfiles/playbooks"):format(HOME)

---Maps os names to sshd_config names
local HOST_TO_SSHD_CONFIG = {
  localhost = "localhost",
  cloud = "cloud",
  phone = "phone",
  phone2 = "phone2",
  macos = "macos",
}

local function trim(value) return (value:gsub("^%s+", ""):gsub("%s+$", "")) end

local function command_string(argv)
  return vim.fn.join(vim.tbl_map(function(item) return vim.fn.shellescape(item) end, argv), " ")
end

local function task_tag(item)
  item = trim(item)
  return item:match("^(%d+%-%d+)") or item:match("^([^%s:%[]+)") or item
end

local function selected_tags(task_id)
  local tags = {}
  for _, item in ipairs(vim.fn.split(task_id or "", ",")) do
    local tag = task_tag(item)
    if tag ~= "" then table.insert(tags, tag) end
  end
  return tags
end

local function ansible_tags(task_id)
  local tags = {}
  vim.list_extend(tags, selected_tags(task_id))
  return table.concat(tags, ",")
end

local function env_vars(env)
  local vars = {}
  if not env or env == "" then return vars end
  local current_key = nil
  for _, token in ipairs(vim.fn.split(env)) do
    local key = token:match("^([%w_]+)=")
    if key then
      current_key = key
      vars[key] = token:sub(#key + 2)
    elseif current_key and token ~= "" then
      vars[current_key] = vars[current_key] .. " " .. token
    end
  end
  return vars
end

local function log_scope(task_id)
  local tags = vim.tbl_filter(function(tag) return tag ~= "setup" end, selected_tags(task_id))
  if #tags == 0 or (#tags == 1 and tags[1] == "all") then return "tools" end

  return (table.concat(tags, "_"):gsub("[^%w_.-]", "_"):gsub("_+", "_"):gsub("^_+", ""):gsub("_+$", ""))
end

local function log_path(task_id) return "/tmp/ansible-" .. log_scope(task_id) .. ".log" end

local function logged_command(argv, cwd, path)
  local header = {
    "ansible-log-version: 1",
    "cwd: " .. cwd,
    "command: " .. command_string(argv),
    "log_path: " .. path,
    "started_at_utc: " .. os.date("!%Y-%m-%dT%H:%M:%SZ"),
    "",
  }

  return string.format(
    "{ printf '%%s\\n' %s; %s 2>&1; } | tee %s",
    command_string(header),
    command_string(argv),
    vim.fn.shellescape(path)
  )
end

---@type overseer.TemplateDefinition
return {
  name = task_name,
  desc = "Run ansible playbook",
  params = {
    pass = {
      desc = "Password",
      type = "string",
      conceal = true,
      order = 1,
    },
    task_id = {
      desc = "Task id",
      type = "string",
      default = "all",
      order = 2,
    },
    host = {
      desc = "Host",
      type = "enum",
      choices = vim.tbl_values(HOST_TO_SSHD_CONFIG),
      optional = false,
      default = HOST_TO_SSHD_CONFIG.localhost,
      order = 3,
    },
    force_handlers = {
      desc = "Force running handlers",
      type = "boolean",
      optional = true,
      order = 4,
    },
    skip_tags = {
      desc = "Ignore the ansible always tag",
      type = "enum",
      choices = {
        "setup",
        "never",
        "always",
        nil,
      },
      default = nil,
      optional = true,
      order = 5,
    },
    verbose = {
      desc = "Verbose",
      type = "enum",
      choices = { "v", "vv", "vvv", "vvvv", "vvvvv" },
      optional = true,
      order = 6,
    },
    playbook = {
      desc = "Verbose",
      type = "enum",
      default = "tools.yml",
      choices = {
        "tools.yml",
        "gocr.yml",
        "arch-realtime-migration.yml",
        "arch-chroot-setup.yml",
        "testing.yml",
        "arch-user-setup.yml",
        "facts_refresh.yml",
      },
      optional = false,
      order = 7,
    },
    env = {
      desc = "Environment variables (e.g. DOTFILES_MUSIC_PRODUCTION_PLUGINS=fortin)",
      type = "string",
      optional = true,
      order = 8,
    },
  },
  builder = function(params)
    local ansible_argv = {
      "ansible-playbook",
      "-K",
      string.format("%s/dotfiles/playbooks/%s", HOME, params.playbook),
      "-l",
      HOST_TO_SSHD_CONFIG[params.host],
      "-i",
      string.format("%s/dotfiles/playbooks/inventory.ini", HOME),
      "--tags",
      ansible_tags(params.task_id),
    }
    if params.skip_tags then vim.list_extend(ansible_argv, { "--skip-tags", params.skip_tags }) end
    if params.force_handlers then table.insert(ansible_argv, "--force-handlers") end
    if params.verbose then table.insert(ansible_argv, "-" .. params.verbose) end
    if params.pass then vim.g.pass = params.pass end
    local components = {
      { "on_complete_notify", system = "always" },
      "defaults_without_dispose",
    }
    if params.pass and params.pass ~= "" then
      table.insert(components, 1, { "system-components.COMPONENT__send_become_password", password = params.pass })
    end
    local path = log_path(params.task_id)
    return {
      name = task_name .. string.format(" %s", params.task_id),
      cmd = "bash",
      args = { "-o", "pipefail", "-c", logged_command(ansible_argv, PLAYBOOKS_DIR, path) },
      cwd = PLAYBOOKS_DIR,
      env = env_vars(params.env),
      metadata = {
        PREVENT_QUIT = true,
        ansible_log_path = path,
      },
      components = components,
    }
  end,
}
