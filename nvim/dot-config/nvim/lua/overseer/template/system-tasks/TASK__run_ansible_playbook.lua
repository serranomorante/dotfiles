local utils = require("serranomorante.utils")
local task_name = "run-ansible-playbook"
local HOME = vim.env.HOME

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
      type = "string",
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
      choices = { "setup", "never", "always" },
      default = "setup",
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
      conceal = true,
      order = 6,
    },
  },
  builder = function(params)
    local args = {
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
      cmd = "vansible-playbook",
      args = args,
      cwd = ("%s/dotfiles/playbooks"):format(HOME),
      metadata = {
        PREVENT_QUIT = true,
      },
      components = {
        { "open_output", direction = "tab", on_start = "always", focus = true },
        "defaults_without_dispose",
      },
    }
  end,
}
