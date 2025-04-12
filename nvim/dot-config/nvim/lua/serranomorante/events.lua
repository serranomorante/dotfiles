local M = {}

--- Trigger a Custom user event
---
--- Thanks AstroNvim!!
---
---@param event string The event name to be appended to Astro
---@param delay? boolean Whether or not to delay the event asynchronously (Default: true)
function M.event(event, delay)
  local function emit_event() vim.api.nvim_exec_autocmds("User", { pattern = "Custom" .. event, modeline = false }) end
  if delay == false then
    emit_event()
  else
    vim.schedule(emit_event)
  end
end

return M
