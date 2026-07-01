local M = {}

local function current_window_is_float()
  local winid = vim.api.nvim_get_current_win()
  if not vim.api.nvim_win_is_valid(winid) then return false end

  return (vim.api.nvim_win_get_config(winid).relative or "") ~= ""
end

local function move_current_buffer_to_new_tab()
  if not current_window_is_float() then return false end

  local winid = vim.api.nvim_get_current_win()
  local bufnr = vim.api.nvim_win_get_buf(winid)

  vim.api.nvim_win_close(winid, false)
  vim.cmd(("tab sbuffer %d"):format(bufnr))
  return true
end

function M.open()
  -- Undotree behaves better when the source buffer lives in a normal tab.
  move_current_buffer_to_new_tab()
  vim.cmd.Undotree()
end

return M
