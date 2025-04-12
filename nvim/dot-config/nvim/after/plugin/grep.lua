---You must escape single qoutes and pipes `:Grep 'id=(\'\|")' ...`

vim.api.nvim_create_user_command(
  "Grep",
  "silent execute v:lua.user.GenerateGrepCommand(<q-args>)",
  { force = true, nargs = "*", complete = "file", desc = "Send grep to qf list (even if zero results)" }
)

---@param args string
_G.user.GenerateGrepCommand = function(args)
  args = args:gsub("\\'", "\\x27") -- escape single quotes
  return "grep -e " .. args
end
