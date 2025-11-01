local task_name = "run-lazygit"

---@type overseer.TemplateDefinition
return {
  name = task_name,
  desc = "Run Lazygit",
  builder = function()
    return {
      name = task_name,
      cmd = "lazygit",
      env = {
        NVIM_KITTY_LISTEN_ADDRESS = vim.v.servername,
        TERM = "xterm-256color",
      },
      components = {
        { "system-components/COMPONENT__start_insert_mode" },
        { "system-components/COMPONENT__force_very_fullscreen_float" },
        { "open_output", direction = "float", on_start = "always", focus = true },
        { "on_complete_dispose", timeout = 1, statuses = { require("overseer.parser").STATUS.SUCCESS } },
        "unique",
        "default",
      },
    }
  end,
}
