local M = {}

local function task_recent_activity_time(task)
  local codex_mtime = require("serranomorante.plugins.jobs.codex_sessions").task_session_mtime(task)
  if codex_mtime then return codex_mtime end

  return task.time_end or task.time_start
end

local function task_action_sort(a, b)
  local a_recent = task_recent_activity_time(a)
  local b_recent = task_recent_activity_time(b)
  if a_recent and b_recent and a_recent ~= b_recent then return a_recent > b_recent end
  if (a_recent == nil) ~= (b_recent == nil) then return a_recent ~= nil end

  return require("overseer.task_list").sort_finished_recently(a, b)
end

function M.run_recent_task_action()
  local task_list = require("overseer.task_list")
  local tasks = task_list.list_tasks({
    unique = true,
    sort = task_action_sort,
    include_ephemeral = true,
  })
  if #tasks == 0 then
    vim.notify("No tasks available", vim.log.levels.WARN)
    return
  end

  local task_summaries = vim.tbl_map(function(task) return { name = task.name, id = task.id } end, tasks)

  vim.ui.select(task_summaries, {
    prompt = "Select task",
    kind = "overseer_task",
    format_item = function(task) return task.name end,
  }, function(task_summary)
    if not task_summary then return end

    local task = assert(task_list.get(task_summary.id))
    require("overseer.action_util").run_task_action(task)
  end)
end

return M
