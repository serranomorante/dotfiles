local M = {}

local SUB_AGENT_TASK_PREFIX = "task://SUB-"

local function escaped_label(label) return label:gsub("%%", "%%%%") end

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
  local buflist = vim.fn.tabpagebuflist(tabnr)
  local winnr = vim.fn.tabpagewinnr(tabnr)
  return buflist[winnr]
end

---@param tabnr integer
---@return boolean
local function tab_has_modified_buffer(tabnr)
  for _, bufnr in ipairs(vim.fn.tabpagebuflist(tabnr)) do
    if buffer_is_modified(bufnr) then return true end
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
  local win_count = vim.fn.tabpagewinnr(tabnr, "$")
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

function M.setup() vim.go.tabline = "%!v:lua.require('serranomorante.tabline').render()" end

return M
