local utils = require("serranomorante.utils")

---@type overseer.ComponentFileDefinition
return {
  desc = "Open make test output when the task starts",
  editable = false,
  serializable = false,
  constructor = function()
    return {
      ---@param task overseer.Task
      on_start = function(_, task)
        if not task or task.name ~= "make test" then return end
        utils.schedule_open_overseer_task_output(task)
      end,
    }
  end,
}
