local M = {}

local SUB_AGENT_TASK_PREFIX = "task://SUB-"
local AUGROUP = vim.api.nvim_create_augroup("serranomorante_tabline", { clear = true })
local last_regular_win_by_tab = {}

local function escaped_label(label) return label:gsub("%%", "%%%%") end

---@param tabnr integer
---@return integer?
local function tabid_for_tabnr(tabnr) return vim.api.nvim_list_tabpages()[tabnr] end

---@param winid integer
---@return boolean
local function is_float_window(winid)
  if not vim.api.nvim_win_is_valid(winid) then return false end
  local ok, config = pcall(vim.api.nvim_win_get_config, winid)
  return ok and (config.relative or "") ~= ""
end

---@param winid integer?
local function remember_regular_win(winid)
  if type(winid) ~= "number" or not vim.api.nvim_win_is_valid(winid) or is_float_window(winid) then return end
  local tabid = vim.api.nvim_win_get_tabpage(winid)
  last_regular_win_by_tab[tostring(tabid)] = winid
end

---@param tabid integer
---@return integer?
local function remembered_regular_win(tabid)
  local key = tostring(tabid)
  local winid = last_regular_win_by_tab[key]
  if
    type(winid) == "number"
    and vim.api.nvim_win_is_valid(winid)
    and vim.api.nvim_win_get_tabpage(winid) == tabid
    and not is_float_window(winid)
  then
    return winid
  end

  last_regular_win_by_tab[key] = nil
end

---@param tabnr integer
---@return integer[]
local function tab_regular_wins(tabnr)
  local tabid = tabid_for_tabnr(tabnr)
  if not tabid then return {} end

  local wins = {}
  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(tabid)) do
    if not is_float_window(winid) then table.insert(wins, winid) end
  end
  return wins
end

---@param tabnr integer
---@return integer?
local function tab_current_regular_win(tabnr)
  local tabid = tabid_for_tabnr(tabnr)
  if not tabid then return end

  local remembered_winid = remembered_regular_win(tabid)
  if remembered_winid then return remembered_winid end

  local ok, current_winid = pcall(vim.api.nvim_tabpage_get_win, tabid)
  if ok and vim.api.nvim_win_is_valid(current_winid) and not is_float_window(current_winid) then
    remember_regular_win(current_winid)
    return current_winid
  end

  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(tabid)) do
    if not is_float_window(winid) then
      remember_regular_win(winid)
      return winid
    end
  end
end

---@param bufnr integer
---@return string
local function buffer_label(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr)
  if name == "" then return "[No Name]" end

  local tail = vim.fn.fnamemodify(name, ":t")
  if tail ~= "" then return tail end
  return name
end

---@param bufnr integer
---@return boolean
local function buffer_is_modified(bufnr)
  local ok, modified = pcall(vim.api.nvim_get_option_value, "modified", { buf = bufnr })
  return ok and modified == true
end

---@param tabnr integer
---@return integer?
local function tab_current_bufnr(tabnr)
  local winid = tab_current_regular_win(tabnr)
  if type(winid) ~= "number" or not vim.api.nvim_win_is_valid(winid) then return end
  return vim.api.nvim_win_get_buf(winid)
end

---@param tabnr integer
---@return boolean
local function tab_has_modified_buffer(tabnr)
  local seen = {}
  for _, winid in ipairs(tab_regular_wins(tabnr)) do
    local bufnr = vim.api.nvim_win_get_buf(winid)
    if not seen[bufnr] then
      seen[bufnr] = true
      if buffer_is_modified(bufnr) then return true end
    end
  end
  return false
end

---@param tabnr integer
---@return boolean
local function tab_is_sub_agent_task(tabnr)
  local bufnr = tab_current_bufnr(tabnr)
  if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then return false end
  return vim.startswith(vim.api.nvim_buf_get_name(bufnr), SUB_AGENT_TASK_PREFIX)
end

---@param tabnr integer
---@return string
local function tab_highlight(tabnr)
  local is_current = tabnr == vim.fn.tabpagenr()
  if tab_is_sub_agent_task(tabnr) then return is_current and "CustomAgentSubTabLineSel" or "CustomAgentSubTabLine" end
  return is_current and "TabLineSel" or "TabLine"
end

---@param tabnr integer
---@return string
local function tab_label(tabnr)
  local bufnr = tab_current_bufnr(tabnr)
  local name = type(bufnr) == "number" and vim.api.nvim_buf_is_valid(bufnr) and buffer_label(bufnr) or "[No Name]"
  local win_count = #tab_regular_wins(tabnr)
  local prefix = ("%d:"):format(tabnr)
  if win_count > 1 then prefix = ("%s%d "):format(prefix, win_count) end
  local suffix = tab_has_modified_buffer(tabnr) and " +" or ""
  return (" %s%s%s "):format(prefix, name, suffix)
end

function M.render()
  local pieces = {}
  local tab_count = vim.fn.tabpagenr("$")

  for tabnr = 1, tab_count do
    table.insert(pieces, ("%%#%s#%%%dT%s"):format(tab_highlight(tabnr), tabnr, escaped_label(tab_label(tabnr))))
  end

  table.insert(pieces, "%#TabLineFill#%T")
  if tab_count > 1 then table.insert(pieces, "%=%#TabLine#%999X X") end
  return table.concat(pieces)
end

function M.setup()
  vim.go.tabline = "%!v:lua.require('serranomorante.tabline').render()"
  vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter", "TabEnter" }, {
    desc = "Remember the tabline's last regular window",
    group = AUGROUP,
    callback = function() remember_regular_win(vim.api.nvim_get_current_win()) end,
  })
  remember_regular_win(vim.api.nvim_get_current_win())
end

return M
