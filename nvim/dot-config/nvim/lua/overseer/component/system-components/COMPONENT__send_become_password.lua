local PROMPT = "BECOME password:"
local utils = require("serranomorante.utils")

local function output_to_string(data)
  if type(data) == "string" then return data end
  if type(data) == "table" then return table.concat(data, "\n") end
  return ""
end

---@param task overseer.Task
---@return integer?
local function task_job_id(task)
  ---@diagnostic disable-next-line: invisible
  local strategy = task.strategy
  return strategy and strategy.job_id or nil
end

---@type overseer.ComponentFileDefinition
local comp = {
  desc = "Send Ansible become password when the prompt appears",
  editable = false,
  serializable = false,
  params = {
    password = {
      desc = "Password",
      type = "string",
      optional = false,
      order = 1,
    },
  },
  constructor = function(params)
    return {
      on_init = function(self)
        self.sent = false
        self.output_tail = ""
      end,
      on_reset = function(self)
        self.sent = false
        self.output_tail = ""
      end,
      on_output = function(self, task, data)
        if self.sent or params.password == "" then return end

        self.output_tail = (self.output_tail .. output_to_string(data)):sub(-#PROMPT * 2)
        if not self.output_tail:find(PROMPT, 1, true) then return end

        self.sent = true
        utils.schedule_open_overseer_task_float(task)

        local job_id = task_job_id(task)
        if not job_id then
          vim.notify("Could not send Ansible become password: task job is not running", vim.log.levels.ERROR)
          return
        end

        local ok, err = pcall(vim.api.nvim_chan_send, job_id, params.password .. "\r")
        if not ok then vim.notify("Could not send Ansible become password: " .. err, vim.log.levels.ERROR) end
      end,
    }
  end,
}

return comp
