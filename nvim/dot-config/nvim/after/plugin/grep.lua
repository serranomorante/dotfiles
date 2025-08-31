---You must escape single qoutes and pipes `:Grep 'id=(\'\|")' ...`

local utils = require("serranomorante.utils")

---@param command_args vim.api.keyset.create_user_command.command_args
local function grep(command_args)
  local items, count = utils.rg_json_to_qfitems(utils.grep_with_rg(command_args.args))
  if count == 0 then
    local msg = "[Grep] No results: %s"
    return vim.api.nvim_echo({ { msg:format(command_args.args) } }, false, { err = true })
  end

  local msg = "[Grep] %d results: %s"
  vim.api.nvim_echo({ { msg:format(count, command_args.args), "DiagnosticOk" } }, false, {})
  vim.fn.setqflist(
    {},
    " ",
    { title = msg:format(count, command_args.args), items = items, context = { name = "user.grep" } }
  )
  vim.cmd.cfirst({ mods = { emsg_silent = true } })
end

vim.api.nvim_create_user_command(
  "Grep",
  grep,
  { force = true, nargs = "*", complete = "file", desc = "Send grep to qf list" }
)
