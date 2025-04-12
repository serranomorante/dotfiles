local M = {}

local function keys() vim.keymap.set("n", "<leader>lb", "<cmd>BlameToggle<CR>", { desc = "Blame: toggle blame" }) end

function M.config()
  keys()
  require("blame").setup()
end

return M
