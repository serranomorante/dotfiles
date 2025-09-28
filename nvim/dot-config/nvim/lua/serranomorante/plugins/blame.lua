local M = {}

local function keys() vim.keymap.set("n", "<leader>lb", "<cmd>BlameToggle<CR>", { desc = "Blame: toggle blame" }) end

local function opts()
  return {
    relative_date_if_recent = true,
  }
end

function M.config()
  keys()
  require("blame").setup(opts())
end

return M
