---@type resession.Extension
local M = {}

function M.on_save()
  local dap_utils = require("serranomorante.plugins.dap.dap-utils")
  local breakpoints = {}
  dap_utils.breakpoints_iter(function(buf, breakpoint)
    local fname = vim.api.nvim_buf_get_name(buf)
    table.insert(breakpoints, {
      filename = fname,
      line = breakpoint.line,
      condition = breakpoint.condition,
      logMessage = breakpoint.logMessage,
      hitCondition = breakpoint.hitCondition,
    })
  end)

  return {
    breakpoints = breakpoints,
  }
end

function M.on_post_load(data)
  if data.breakpoints == nil or #data.breakpoints == 0 then
    return -- No breakpoints to load, no need to load dap plugin
  end

  local bufs_by_name = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    bufs_by_name[vim.api.nvim_buf_get_name(buf)] = buf
  end

  for _, breakpoint in pairs(data.breakpoints or {}) do
    local buf = bufs_by_name[breakpoint.filename]
    if buf and vim.api.nvim_buf_is_valid(buf) then
      local bopts = {}
      if breakpoint.condition then bopts.condition = breakpoint.condition end
      if breakpoint.logMessage then bopts.log_message = breakpoint.logMessage end
      if breakpoint.hitCondition then bopts.hit_condition = breakpoint.hitCondition end
      require("dap.breakpoints").set(bopts, buf, breakpoint.line)
      local msg = "Restoring breakpoint at buf %s line %s"
      vim.api.nvim_echo({ { msg:format(buf, breakpoint.line), "Comment" } }, false, {})
    else
      local msg = "Could not restore breakpoint at buf %s line %s"
      vim.api.nvim_echo({ { msg:format(buf, breakpoint.line) } }, false, { err = true })
    end
  end
end

return M
