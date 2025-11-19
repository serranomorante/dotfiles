local utils = require("serranomorante.utils")

local cache = {}
local function random_thought()
  local flags = " --type md --iglob **/journal/**"
  local items, count = utils.rg_json_to_qfitems(utils.grep_with_rg("'^\\w[a-zA-Z\\s]{100,}'" .. flags, { json = true }))
  if count == 0 then return vim.api.nvim_echo({ { "No thoughts" } }, false, { err = true }) end
  local random_count = math.random(count)
  local cache_full = vim.tbl_count(cache) == vim.tbl_count(items)
  while vim.list_contains(cache, items[random_count].text) and not cache_full do
    random_count = math.random(count)
    cache_full = vim.tbl_count(cache) == vim.tbl_count(items)
  end
  if cache_full then return vim.api.nvim_echo({ { "No more thoughts!" } }, false, { err = true }) end
  table.insert(cache, items[random_count].text)
  vim.fn.setqflist({}, " ", { title = "Go to random thought", items = items })
  vim.cmd.cc({ args = { random_count }, mods = { silent = true } })
  vim.cmd.normal({ "zz", bang = true })
end

vim.api.nvim_create_user_command(
  "RandomThought",
  random_thought,
  { force = true, nargs = "*", desc = "Go to random thought" }
)

vim.keymap.set("n", "<leader>te", "<cmd>RandomThought<CR>", { desc = "Go to workspace's random thought item" })
