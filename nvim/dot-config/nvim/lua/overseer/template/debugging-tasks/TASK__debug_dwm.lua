local utils = require("serranomorante.utils")

local task_name = "debugging-tasks: prepare DWM debugging session"

---@type overseer.TemplateDefinition
return {
  name = task_name,
  builder = function()
    local prepare_dwm = utils.wrap_overseer_args_with_tmux(
      "Xephyr -br -ac -noreset -screen 800x600 :2",
      { include_binary = true, detach = true }
    )
    local prepare_st = utils.wrap_overseer_args_with_tmux("st", { include_binary = true, detach = true })
    return {
      name = task_name,
      strategy = {
        "orchestrator",
        tasks = {
          {
            "shell",
            cmd = prepare_dwm,
          },
          {
            "shell",
            cmd = "sleep 1",
          },
          {
            "shell",
            cmd = prepare_st,
            env = {
              DISPLAY = ":2",
            },
          },
          {
            "shell",
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
    callback = function() return vim.fn.executable("Xephyr") == 1 and utils.cwd_is_dwm() end,
  },
}
