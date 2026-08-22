---You must escape single qoutes and pipes `:Grep 'id=(\'\|")' ...`

local utils = require("serranomorante.utils")

local active_grep

local MIN_SEARCH_LEN = 5

---@param command_args vim.api.keyset.create_user_command.command_args
local function grep(command_args)
  local args = command_args.args
  if args == "''" then
    vim.api.nvim_echo({ { "Empty search pattern" } }, false, { err = true })
    return
  end
  local term = utils.search_term_from_args(args)
  if #term < MIN_SEARCH_LEN then
    vim.api.nvim_echo({
      { ("Grep search blocked: '%s' has fewer than %d chars"):format(term, MIN_SEARCH_LEN), "DiagnosticWarn" },
    }, false, {})
    return
  end
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
