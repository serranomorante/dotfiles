---You must escape single qoutes and pipes `:Helpgrep 'id=(\'\|")' ...`

local utils = require("serranomorante.utils")

---@param command_args vim.api.keyset.create_user_command.command_args
local function helpgrep(command_args)
  local args = command_args.args:gsub("\\'", "\\x27") -- escape single quotes
  local dirs = string.format("%s/repos/neovim/runtime/doc %s/site/pack/plugins", vim.env.HOME, vim.fn.stdpath("data"))
  local content = vim.fn.join(vim.fn.systemlist(string.format("rg -e %s %s -g '*.txt' --json", args, dirs)), ",")
  local json_content = vim.json.decode(string.format("[%s]", content), { luanil = { object = true } })

  local items, count = utils.rg_json_to_qfitems(json_content)
  if count == 0 then return vim.notify(string.format("[Helpgrep] No results: %s", args), vim.log.levels.ERROR) end

  local message = string.format("[Helpgrep] %d results: %s", count, args)
  vim.notify(message, vim.log.levels.INFO)
  vim.fn.setqflist({}, " ", { title = message, items = items })
  vim.cmd.cfirst({ mods = { emsg_silent = true } })
end

vim.api.nvim_create_user_command(
  "Helpgrep",
  helpgrep,
  { force = true, nargs = "*", desc = "Send helpgrep to quickfix list" }
)
