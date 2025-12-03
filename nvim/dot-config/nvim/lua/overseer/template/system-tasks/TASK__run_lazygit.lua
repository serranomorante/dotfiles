local constants = require("serranomorante.constants")

local task_name = "run-lazygit"

---@type overseer.TemplateDefinition
return {
  name = task_name,
  desc = "Run Lazygit",
  hide = true,
  builder = function()
    return {
      name = task_name,
      cmd = "lazygit",
      env = {
        NVIM_KITTY_LISTEN_ADDRESS = vim.v.servername,
        TERM = "xterm-256color",
      },
      strategy = constants.fullscreen_jobstart_opts,
      components = {
        { "open_output", direction = "float", on_start = "always", focus = true },
        { "on_complete_dispose", timeout = 1, statuses = { require("overseer.constants").STATUS.SUCCESS } },
        "unique",
        "default",
      },
    }
  end,
}
