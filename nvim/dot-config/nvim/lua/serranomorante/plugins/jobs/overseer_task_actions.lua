local M = {}

local function task_recent_activity_time(task)
  local agent_mtime = require("serranomorante.plugins.jobs.agent_sessions").task_session_mtime(task)
  if agent_mtime then return agent_mtime end

  return task.time_end or task.time_start
end

local function task_action_sort(a, b)
  local a_recent = task_recent_activity_time(a)
  local b_recent = task_recent_activity_time(b)
  if a_recent and b_recent and a_recent ~= b_recent then return a_recent > b_recent end
  if (a_recent == nil) ~= (b_recent == nil) then return a_recent ~= nil end

  return require("overseer.task_list").sort_finished_recently(a, b)
end

---@param opts? { visual?: boolean, action_name?: string, noop_task_id?: integer }
function M.run_recent_task_action(opts)
  opts = opts or {}
  local task_list = require("overseer.task_list")
  local agent_sessions = require("serranomorante.plugins.jobs.agent_sessions")
  local agent_prompt_context = nil
  if not opts.action_name or opts.action_name == "open" then
    agent_prompt_context = agent_sessions.capture_task_action_prompt_context(opts.visual and { visual = true } or nil)
  end
  local start_win = agent_prompt_context and vim.api.nvim_get_current_win() or nil
  local tasks = task_list.list_tasks({
    unique = true,
    sort = task_action_sort,
    include_ephemeral = true,
    filter = function(task) return not task.metadata.hide_from_task_list end,
  })
  if #tasks == 0 then
    vim.notify("No tasks available", vim.log.levels.WARN)
    return
  end
  if opts.noop_task_id and #tasks == 1 and tasks[1].id == opts.noop_task_id then return end

  -- Only the <leader>od "open" listing pins the task it was invoked from: when
  -- the current buffer is an Overseer task output, that task becomes the first
  -- entry instead of following the recent-activity order. The capture above
  -- already resolved that task as the action prompt context source.
  local pinned_task_id = opts.noop_task_id
  if opts.action_name == "open" and not pinned_task_id and agent_prompt_context then
    local source_task = agent_prompt_context.source_task
    pinned_task_id = source_task and source_task.id or nil
  end
  if pinned_task_id then
    for index, task in ipairs(tasks) do
      if task.id == pinned_task_id then
        if index ~= 1 then
          table.remove(tasks, index)
          table.insert(tasks, 1, task)
        end
        break
      end
    end
  end

  local task_summaries = vim.tbl_map(function(task) return { name = task.name, id = task.id } end, tasks)

  vim.ui.select(task_summaries, {
    prompt = "Select task",
    kind = "overseer_task",
    format_item = function(task) return task.name end,
  }, function(task_summary)
    if not task_summary then return end

    local task = assert(task_list.get(task_summary.id))
    if opts.noop_task_id and task.id == opts.noop_task_id then return end
    local agent_prompt = agent_sessions.prompt_from_task_action_context(agent_prompt_context, task)
    if agent_prompt and agent_sessions.open_task_with_prompt(task, agent_prompt, { start_win = start_win }) then
      return
    end

    require("overseer.action_util").run_task_action(task, opts.action_name)
  end)
end

---@param opts? { noop_task_id?: integer }
function M.open_recent_task(opts)
  opts = opts or {}
  opts.action_name = "open"
  M.run_recent_task_action(opts)
end

return M
