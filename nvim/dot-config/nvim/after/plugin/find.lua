---@param items string[]
local function send_to_qf(items)
  local files = vim.tbl_map(function(item) return { filename = item } end, items)
  vim.fn.setqflist({}, "r", { title = "Find results", items = files or {} })
end

local function complete(arg_lead)
  local result = vim.fn.system("fd --type file --follow --full-path " .. arg_lead)
  return vim.split(result or "", "\n", { trimempty = true })
end

vim.api.nvim_create_user_command("Find", "find <args>", { force = true, nargs = "?", complete = complete })

_G.user.findfunc = function(cmd_arg)
  local files = complete(cmd_arg)
  vim.schedule(function() send_to_qf(files) end)
  return files
end

if vim.fn.exists("&findfunc") > 0 then vim.o.findfunc = "v:lua.user.findfunc" end
