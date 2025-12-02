local utils = require("serranomorante.utils")

local task_name = "debugging-tasks: prepare DWM debugging session"

---@type overseer.TemplateDefinition
return {
  name = task_name,
  builder = function()
    local prepare_dwm = utils.wrap_overseer_args_with_tmux(
      "Xephyr -br -ac -noreset -screen 1800x800 :2",
      { include_binary = true, detach = true }
    )
    local prepare_st = utils.wrap_overseer_args_with_tmux("st", { include_binary = true, detach = true })
    return {
      name = task_name,
      strategy = {
        "orchestrator",
        tasks = {
          {
            cmd = prepare_dwm,
          },
          {
            cmd = "sleep 1",
          },
          {
            cmd = prepare_st,
            env = {
              DISPLAY = ":2",
            },
          },
          {
            cmd = prepare_st,
            env = {
              DISPLAY = ":2",
            },
          },
        },
      },
    }
  end,
  condition = {
    dir = vim.env.HOME .. "/repos/dwm",
  },
}
