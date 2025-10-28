local utils = require("serranomorante.utils")
local task_name = "run-ansible-playbook"
local HOME = vim.env.HOME

local PLAYS = {
  SETUP_DESKTOP = "10-10 [Setup desktop]",
  SETUP_KEYBOARD_TOOLS = "10-40 [Setup keyboard tools]",
  SETUP_WINE_TOOLS = "10-120 [Setup wine tools]",
  SETUP_BROWSER_TOOLS = "10-170 [Setup browser tools]",
  SETUP_BACKUP_TOOLS = "10-180,10-181 [Setup backup tools]",
  SETUP_COMPOSITOR = "10-100 [Setup compositor]",
  SETUP_DOTFILES = "10-30 [Setup dotfiles]",
  SETUP_VIRTUALBOX = "10-140 [Setup virtualbox]",
  SETUP_PERSISTENCE_TOOLS = "10-150 [Setup persistence tools]",
  SETUP_OTHER_TOOLS = "10-160 [Setup other tools]",
  SETUP_VIDEO_TOOLS = "10-220 [Setup video tools]",
  SETUP_NEOVIM = "20-50 [Setup neovim]",
  SETUP_EDITOR_TOOLS = "20-60 [Setup editor tools]",
  SETUP_FULL_EDITOR = "20-50,20-60 [Setup full editor + plugins]",
  SETUP_MARKDOWN_TOOLS = "30-100 [Setup markdown tools]",
  SETUP_HPI = "40-20 [Setup HPI]",
  SETUP_EXPORTS = "40-30 [Setup exports]",
  SETUP_AI_TOOLS = "20-170 [Setup AI tools]",
  SETUP_CODE_GENERATION = "30-999 [Setup Code Generation]",
  SETUP_ALL_NODE = "20-10,20-50,20-60,20-170,30-30,30-100,30-999 [Setup all node]", -- safe node playbook execution
  ALL = "all",
  NEVER = "never",
  FOR_MY_EYES_ONLY_60_10 = "60-10 [for-my-eyes-only]",
  FOR_MY_EYES_ONLY_60_20 = "60-20 [for-my-eyes-only]",
  FOR_MY_EYES_ONLY_60_30 = "60-30 [for-my-eyes-only]",
  FOR_MY_EYES_ONLY_60_40 = "60-40 [for-my-eyes-only]",
  FOR_MY_EYES_ONLY_70_10 = "70-10 [for-my-eyes-only]",
  ALWAYS = "always",
}

---Maps os names to sshd_config names
local OS_TO_SSHD_CONFIG = {
  archlinux = "localhost",
  debian = "cloud",
  otherlinux = "phone",
  macosx = "macos",
}

---@type overseer.TemplateDefinition
return {
  name = task_name,
  desc = "Run ansible playbook",
  params = {
    task_id = {
      desc = "Task id",
      type = "enum",
      choices = vim.tbl_values(PLAYS),
      optional = false,
      order = 1,
    },
    os = {
      desc = "OS",
      type = "enum",
      choices = { "archlinux", "debian", "otherlinux" },
      optional = false,
      default = "archlinux",
      order = 2,
    },
    force_handlers = {
      desc = "Force running handlers",
      type = "boolean",
      optional = true,
      order = 3,
    },
    skip_tags = {
      desc = "Ignore the ansible always tag",
      type = "enum",
      choices = { PLAYS.ALWAYS, PLAYS.NEVER },
      optional = true,
      order = 4,
    },
    verbose = {
      desc = "Verbose",
      type = "enum",
      choices = { "v", "vv", "vvv", "vvvv", "vvvvv" },
      optional = true,
      order = 5,
    },
    pass = {
      desc = "Password",
      type = "string",
      optional = true,
      conceal = true,
      order = 6,
    },
  },
  builder = function(params)
    local args = {
      "vansible-playbook",
      "-K",
      ("%s/dotfiles/playbooks/tools.yml"):format(HOME),
      "-l",
      OS_TO_SSHD_CONFIG[params.os],
      "--tags",
      utils.wrap_in_single_quotes(
        vim.fn.join(
          vim.tbl_map(function(item) return (item:match("^(%d+-%d+)") or item) end, vim.fn.split(params.task_id, ",")),
          ","
        )
      ),
    }
    if params.skip_tags then vim.list_extend(args, { "--skip-tags", params.skip_tags }) end
    if params.force_handlers then table.insert(args, "--force-handlers") end
    if params.verbose then table.insert(args, params.verbose) end
    if params.pass then vim.g.pass = params.pass end
    utils.write_password({ delay = 1000 })
    return {
      name = task_name .. string.format(" %s", params.task_id),
      cmd = vim.fn.join(args, " "),
      cwd = ("%s/dotfiles/playbooks"):format(HOME),
      components = {
        { "open_output", direction = "float", on_start = "always", focus = true },
        "default",
      },
    }
  end,
}
