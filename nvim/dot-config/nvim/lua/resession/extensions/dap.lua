---@type resession.Extension
local M = {}

M.on_save = function()
  local breakpoints = {}

  for buf, buf_breakpoints in pairs(require("dap.breakpoints").get()) do
    for _, breakpoint in pairs(buf_breakpoints) do
      local fname = vim.api.nvim_buf_get_name(buf)
      table.insert(breakpoints, {
        filename = fname,
        line = breakpoint.line,
        condition = breakpoint.condition,
        logMessage = breakpoint.logMessage,
        hitCondition = breakpoint.hitCondition,
      })
    end
  end

  return {
    breakpoints = breakpoints,
  }
end

M.on_post_load = function(data)
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
      vim.notify(("Restoring breakpoint at buf %s line %s"):format(buf, breakpoint.line), vim.log.levels.DEBUG)
    else
      vim.notify(("Could not restore breakpoint at buf %s line %s"):format(buf, breakpoint.line), vim.log.levels.WARN)
    end
  end
end

return M
