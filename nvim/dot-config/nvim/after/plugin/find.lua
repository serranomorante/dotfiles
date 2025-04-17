---You must escape pipes `:Find 'file(-\|_)one' ...`

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
  local files_count = vim.tbl_count(files)
  if files_count > 0 then
    local message = string.format("[Find] %d results: %s", files_count, cmd_arg)
    vim.schedule(function()
      local items = vim.tbl_map(function(item) return { filename = item } end, files)
      vim.fn.setqflist({}, " ", { title = message, items = items or {} })
    end)
    vim.notify(message, vim.log.levels.INFO)
  end
  return files
end

if vim.fn.exists("&findfunc") > 0 then vim.o.findfunc = "v:lua.user.findfunc" end
