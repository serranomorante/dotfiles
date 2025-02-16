local M = {}

local function keys() vim.keymap.set("n", "<leader>lb", "<cmd>BlameToggle<CR>", { desc = "Blame: toggle blame" }) end

M.config = function()
  keys()
  require("blame").setup()
end

return M
