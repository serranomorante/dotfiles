---You must escape pipes `:Find 'file(-\|_)one' ...`

---Send find results to quickfix list
---@param items string[]
local function send_to_qf(items)
  local files = vim.tbl_map(function(item) return { filename = item } end, items)
  vim.fn.setqflist({}, "r", { title = "Find results", items = files or {} })
end

---Use `fd` to perform the file and directory search
---@param arg_lead string
local function find(arg_lead)
  arg_lead = arg_lead:gsub("\\|", "|") -- fix regex pipe compatibility
  return vim.split(vim.fn.system("fd --type file --follow --full-path " .. arg_lead) or "", "\n", { trimempty = true })
end

vim.api.nvim_create_user_command(
  "Find",
  "find <args>",
  { force = true, nargs = "*", complete = "file", desc = "Send find to qf list (even if zero results)" }
)

---@param cmd_arg string
function _G.user.findfunc(cmd_arg)
  local files = find(cmd_arg)
  vim.schedule(function() send_to_qf(files) end)
  return files
end

if vim.fn.exists("&findfunc") > 0 then vim.o.findfunc = "v:lua.user.findfunc" end
