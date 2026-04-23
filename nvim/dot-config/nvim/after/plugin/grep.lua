---You must escape single qoutes and pipes `:Grep 'id=(\'\|")' ...`

local utils = require("serranomorante.utils")

local active_grep

---@param command_args vim.api.keyset.create_user_command.command_args
local function grep(command_args)
  if active_grep then active_grep.cancel() end
  active_grep = utils.grep_with_rg_to_qflist(command_args.args, {
    context = { name = "user.grep" },
    title_prefix = "Grep",
    on_finish = function() active_grep = nil end,
  })
end

vim.api.nvim_create_user_command(
  "Grep",
  grep,
  { force = true, nargs = "*", complete = "file", desc = "Send grep to qf list" }
)
