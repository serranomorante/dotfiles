---You must escape single qoutes and pipes `:Grep 'id=(\'\|")' ...`

local utils = require("serranomorante.utils")

---@param command_args vim.api.keyset.create_user_command.command_args
local function grep(command_args)
  local args = command_args.args:gsub("\\'", "\\x27") -- escape single quotes
  local content = vim.fn.join(vim.fn.systemlist(string.format("rg -e %s --json", args)), ",")
  local json_content = vim.json.decode(string.format("[%s]", content), { luanil = { object = true } })

  local items, count = utils.rg_json_to_qfitems(json_content)
  if count == 0 then
    local msg = "[Grep] No results: %s"
    return vim.api.nvim_echo({ { msg:format(args) } }, false, { err = true })
  end

  local msg = "[Grep] %d results: %s"
  vim.api.nvim_echo({ { msg:format(count, args), "DiagnosticOk" } }, false, {})
  vim.fn.setqflist({}, " ", { title = msg:format(count, args), items = items, context = { name = "user.grep" } })
  vim.cmd.cfirst({ mods = { emsg_silent = true } })
end

vim.api.nvim_create_user_command(
  "Grep",
  grep,
  { force = true, nargs = "*", complete = "file", desc = "Send grep to qf list" }
)
