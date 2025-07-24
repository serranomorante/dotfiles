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
  if cmd_arg == "''" then
    vim.api.nvim_echo({ { "Empty search pattern" } }, false, { err = true })
    return {}
  end
  local files = find(cmd_arg)
  local files_count = vim.tbl_count(files)
  if files_count > 0 then
    local msg = "[Find] %d results: %s"
    vim.schedule(function()
      local items = vim.tbl_map(function(item) return { filename = item } end, files)
      vim.fn.setqflist(
        {},
        " ",
        { title = msg:format(files_count, cmd_arg), items = items or {}, context = { name = "user.find" } }
      )
    end)
    vim.api.nvim_echo({ { msg:format(files_count, cmd_arg), "DiagnosticOk" } }, false, {})
  end
  return files
end

if vim.fn.exists("&findfunc") > 0 then vim.o.findfunc = "v:lua.user.findfunc" end
