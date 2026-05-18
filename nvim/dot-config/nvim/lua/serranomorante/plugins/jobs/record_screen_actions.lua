local M = {}

local STATUS = require("overseer.constants").STATUS

local function metadata(task) return task.metadata and task.metadata.record_screen end

local function state(task)
  local record_screen = metadata(task)
  if not record_screen or not record_screen.status_path or vim.fn.filereadable(record_screen.status_path) ~= 1 then
    return nil
  end

  for _, line in ipairs(vim.fn.readfile(record_screen.status_path)) do
    local key, value = line:match("^([^=]+)=(.*)$")
    if key == "state" then return value end
  end
end

local function control(task, command)
  local record_screen = metadata(task)
  if not record_screen then return end

  local job_id = vim.fn.jobstart({ record_screen.script, command, "--id", record_screen.id }, { detach = true })
  if job_id <= 0 then vim.notify(string.format("Could not %s recording", command), vim.log.levels.ERROR) end
end

function M.is_record_screen_task(task) return metadata(task) ~= nil end

function M.stop(task) control(task, "stop") end

function M.actions()
  return {
    ["Pause ffmpeg recording"] = {
      desc = "Pause the current ffmpeg recording segment.",
      condition = function(task)
        return M.is_record_screen_task(task) and task.status == STATUS.RUNNING and state(task) == "recording"
      end,
      run = function(task) control(task, "pause") end,
    },
    ["Resume ffmpeg recording"] = {
      desc = "Resume a paused ffmpeg recording as a new segment.",
      condition = function(task)
        return M.is_record_screen_task(task) and task.status == STATUS.RUNNING and state(task) == "paused"
      end,
      run = function(task) control(task, "resume") end,
    },
    ["Stop & save ffmpeg recording"] = {
      desc = "Stop the recording and save the final output file.",
      condition = function(task) return M.is_record_screen_task(task) and task.status == STATUS.RUNNING end,
      run = function(task) control(task, "stop") end,
    },
  }
end

return M
