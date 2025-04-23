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
  [HOME .. "/dotfiles/utilities"] = {
    "10-100-setup-compositor",
  },
  [HOME .. "/dotfiles/for-my-eyes-only"] = {
    "60-10-for-my-eyes-only",
  },
  [HOME .. "/dotfiles/playbooks"] = {
    "10-100-setup-compositor",
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
      cmd = vim.fn.join(args, " "),
      cwd = ("%s/dotfiles/playbooks"):format(HOME),
      components = {
        { "open_output", direction = "float", on_start = "always", focus = true },
        "default",
      },
    }
  end,
}
