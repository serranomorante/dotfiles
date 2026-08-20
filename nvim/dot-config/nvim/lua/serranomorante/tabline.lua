local M = {}

local SUB_AGENT_TASK_PREFIX = "task://SUB-"
local UNFIREJAILED_AGENT_TASK_PREFIX = "task://UNFIREJAILED-"
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
  local name = vim.api.nvim_buf_get_name(bufnr)
  return vim.startswith(name, SUB_AGENT_TASK_PREFIX) or vim.startswith(name, UNFIREJAILED_AGENT_TASK_PREFIX .. "SUB-")
end

---@param tabnr integer
---@return boolean
local function tab_is_unfirejailed_agent_task(tabnr)
  local bufnr = tab_current_bufnr(tabnr)
  if type(bufnr) ~= "number" or not vim.api.nvim_buf_is_valid(bufnr) then return false end
  return vim.startswith(vim.api.nvim_buf_get_name(bufnr), UNFIREJAILED_AGENT_TASK_PREFIX)
end

---@param tabnr integer
---@return string
local function tab_highlight(tabnr)
  local is_current = tabnr == vim.fn.tabpagenr()
  if tab_is_unfirejailed_agent_task(tabnr) then
    return is_current and "CustomAgentUnfirejailedTabLineSel" or "CustomAgentUnfirejailedTabLine"
  end
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

---@param tabnr integer
---@return string
local function tab_render_piece(tabnr)
  return ("%%#%s#%%%dT%s"):format(tab_highlight(tabnr), tabnr, escaped_label(tab_label(tabnr)))
end

---@param tab_count integer
---@param current_tab integer
---@param widths integer[]
---@param budget integer
---@return integer first
---@return integer last
local function visible_tab_window(tab_count, current_tab, widths, budget)
  local left, right = current_tab, current_tab
  local used = widths[current_tab]
  while true do
    local left_add = left > 1 and widths[left - 1] or math.huge
    local right_add = right < tab_count and widths[right + 1] or math.huge
    local add = math.min(left_add, right_add)
    if used + add > budget then break end
    if left_add < right_add then
      left = left - 1
    elseif right_add < left_add then
      right = right + 1
    else
      if left - 1 >= tab_count - right then left = left - 1 else right = right + 1 end
    end
    used = used + add
  end
  return left, right
end

function M.render()
  local pieces = {}
  local tab_count = vim.fn.tabpagenr("$")
  local current_tab = vim.fn.tabpagenr()

  local widths = {}
  local total = 0
  for tabnr = 1, tab_count do
    widths[tabnr] = vim.fn.strdisplaywidth(tab_label(tabnr))
    total = total + widths[tabnr]
  end

  local columns = vim.o.columns
  local close_button = tab_count > 1 and 2 or 0
  local first, last = 1, tab_count

  if total + close_button > columns then
    local budget = math.max(1, columns - close_button - 2)
    first, last = visible_tab_window(tab_count, current_tab, widths, budget)
  end

  if first > 1 then table.insert(pieces, ("%%#TabLine#%%%dT%s"):format(first - 1, "‹")) end
  for tabnr = first, last do
    table.insert(pieces, tab_render_piece(tabnr))
  end
  if last < tab_count then table.insert(pieces, ("%%#TabLine#%%%dT%s"):format(last + 1, "›")) end

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
