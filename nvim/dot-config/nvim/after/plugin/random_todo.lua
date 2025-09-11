local utils = require("serranomorante.utils")

local function random_todo()
  local items, count = utils.rg_json_to_qfitems(utils.grep_with_rg("'^- \\[ \\]'", { json = true }))
  if count == 0 then return vim.api.nvim_echo({ { "No pending TODOs" } }, false, { err = true }) end
  vim.fn.setqflist({}, " ", { title = "Go to random TODO", items = items })
  vim.cmd.cc(math.random(count + 1))
end

vim.api.nvim_create_user_command("RandomTodo", random_todo, { force = true, nargs = "*", desc = "Go to random TODO" })
