local utils = require("serranomorante.utils")

local function tasks_running()
  local result = unpack(require("overseer").list_tasks({
    status = require("overseer.parser").STATUS.RUNNING,
    filter = function(task) return task.metadata.PREVENT_QUIT end,
  }))
  utils.write_file(vim.v.servername .. ".tasks_running", result and "tasks are running\n" or "no running tasks\n")
end

vim.api.nvim_create_user_command("TasksRunning", tasks_running, {
  force = true,
  nargs = "*",
  desc = "Check no tasks are running",
})
