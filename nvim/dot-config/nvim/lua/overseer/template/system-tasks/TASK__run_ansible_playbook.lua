local utils = require("serranomorante.utils")

local task_name = "run-ansible-playbook"
local HOME = vim.env.HOME
local CWD = vim.fn.getcwd()
local CHOICES = {
  ---These choices will only show get cwd is assets
  [HOME .. "/dotfiles/assets"] = {
    "10-40-setup-keyboard-tools",
    "10-170-setup-browser-tools",
    "10-180-setup-backup-tools,10-181-setup-root-backup-tools",
  },
  [HOME .. "/dotfiles/playbooks"] = {
    "20-60-setup-editor-tools",
  },
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
  },
  builder = function(params)
    local args = {
      "vansible-playbook",
      "-K",
      ("%s/dotfiles/playbooks/tools.yml"):format(HOME),
      "-l",
      "localhost",
      "--tags",
      string.format(
        '"%s"',
        vim.fn.join(
          vim.tbl_map(function(item) return item:gsub("([^-]*-[^-]*).*", "%1") end, vim.fn.split(params.task_id, ",")),
          ","
        )
      ),
    }
    return {
      cmd = vim.fn.join(
        utils.wrap_overseer_args_with_tmux(args, { session_name = task_name, include_binary = true }),
        " "
      ),
      cwd = ("%s/dotfiles/playbooks"):format(HOME),
    }
  end,
}
