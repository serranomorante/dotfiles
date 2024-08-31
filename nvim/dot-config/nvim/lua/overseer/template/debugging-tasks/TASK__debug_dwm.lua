local DEFAULT_XORG_DISPLAY = ":2"

---@type overseer.TemplateDefinition
local debug_dwm_orchestrator = {
  name = "debugging-tasks: prepare DWM debugging session",
  builder = function()
    vim.env.DAP_OVERRIDED_DISPLAY = DEFAULT_XORG_DISPLAY -- just like a task but on nvim itself
    return {
      name = "debug_dwm: orchestrator",
      strategy = {
        "orchestrator",
        tasks = {
          { "shell", cmd = "Xephyr -br -ac -noreset -screen 800x600 " .. DEFAULT_XORG_DISPLAY },
          ---No need for more tasks here for now, but I might in the future
        },
      },
    }
  end,
  condition = {
    callback = function() return vim.fn.executable("Xephyr") == 1 end,
  },
}

return debug_dwm_orchestrator
