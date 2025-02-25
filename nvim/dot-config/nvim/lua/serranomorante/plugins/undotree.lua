local M = {}

local init = function()
  ---undotree window width
  vim.g.undotree_SplitWidth = 30
  ---if set, let undotree window get focus after being opened, otherwise
  ---focus will stay in current window.
  vim.g.undotree_SetFocusWhenToggle = 1
end

local keys = function() vim.keymap.set("n", "<leader>uu", vim.cmd.UndotreeToggle, { desc = "Toggle undotree" }) end

M.config = function()
  init()
  keys()
end

return M
