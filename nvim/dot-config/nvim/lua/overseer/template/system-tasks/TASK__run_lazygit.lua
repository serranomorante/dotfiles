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
      components = {
        { "open_output", direction = "tab", on_start = "always", focus = true },
        { "on_complete_dispose", timeout = 1, statuses = { require("overseer.constants").STATUS.SUCCESS } },
        "unique",
        "default",
      },
    }
  end,
}
