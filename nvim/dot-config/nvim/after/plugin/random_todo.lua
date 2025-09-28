local utils = require("serranomorante.utils")

local cache = {}
local function random_todo()
  local items, count = utils.rg_json_to_qfitems(utils.grep_with_rg("'^- \\[ \\]'", { json = true }))
  if count == 0 then return vim.api.nvim_echo({ { "No pending TODOs" } }, false, { err = true }) end
  local random_count = math.random(count)
  local cache_full = vim.tbl_count(cache) == vim.tbl_count(items)
  while vim.list_contains(cache, items[random_count].text) and not cache_full do
    random_count = math.random(count)
    cache_full = vim.tbl_count(cache) == vim.tbl_count(items)
  end
  if cache_full then return vim.api.nvim_echo({ { "All random todos exhausted!" } }, false, { err = true }) end
  table.insert(cache, items[random_count].text)
  vim.fn.setqflist({}, " ", { title = "Go to random TODO", items = items })
  vim.cmd.cc({ args = { random_count }, mods = { silent = true } })
  vim.cmd.normal({ "zz", bang = true })
end

vim.api.nvim_create_user_command("RandomTodo", random_todo, { force = true, nargs = "*", desc = "Go to random TODO" })
