local utils = require("serranomorante.utils")
local task_name = "run-ansible-playbook"
local HOME = vim.env.HOME
local CWD = vim.fn.getcwd()
local CHOICES = {
  ---These choices will only show get cwd is assets
  [HOME .. "/dotfiles/assets"] = {
    "10-40-setup-keyboard-tools",
    "10-120-setup-wine-tools",
    "10-170-setup-browser-tools",
    "10-180-setup-backup-tools,10-181-setup-root-backup-tools",
  },
  [HOME .. "/dotfiles/utilities"] = {
    "10-100-setup-compositor",
  },
  [HOME .. "/dotfiles/for-my-eyes-only"] = {
    "10-10-setup-desktop",
    "60-10-for-my-eyes-only",
    "60-20-for-my-eyes-only",
    "60-30-for-my-eyes-only",
    "60-40-for-my-eyes-only",
    "70-10-for-my-eyes-only",
  },
  [HOME .. "/dotfiles/playbooks"] = {
    "10-10-setup-desktop",
    "10-30-setup-dotfiles",
    "10-100-setup-compositor",
    "10-120-setup-wine-tools",
    "10-140-setup-virtualbox",
    "10-170-setup-browser-tools",
    "10-180-setup-backup-tools,10-181-setup-root-backup-tools",
    "20-50-setup-neovim",
    "20-60-setup-editor-tools",
    "40-20-setup-HPI",
    "40-30-setup-exports",
    "all",
    "never",
  },
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
      choices = CHOICES[CWD] or {},
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
      choices = { "always", "never" },
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
          vim.tbl_map(function(item) return item:gsub("([^-]*-[^-]*).*", "%1") end, vim.fn.split(params.task_id, ",")),
          ","
        )
      ),
    }
    if params.skip_tags then vim.list_extend(args, { "--skip-tags", params.skip_tags }) end
    if params.force_handlers then table.insert(args, "--force-handlers") end
    if params.verbose then table.insert(args, params.verbose) end
    local tmux_args = {
      session_name = task_name,
      include_binary = true,
      cwd = vim.env.HOME .. "/dotfiles/playbooks",
      retain_shell = true,
    }
    local final = vim.fn.join(utils.wrap_overseer_args_with_tmux(args, tmux_args), " ")
    return {
      cmd = final,
      cwd = ("%s/dotfiles/playbooks"):format(HOME),
      components = {
        { "open_output", direction = "float", on_start = "always", focus = true },
        "default",
      },
    }
  end,
}
