local M = {}

local function init()
  ---undotree window width
  vim.g.undotree_SplitWidth = 30
  ---if set, let undotree window get focus after being opened, otherwise
  ---focus will stay in current window.
  vim.g.undotree_SetFocusWhenToggle = 1
end

local function keys() vim.keymap.set("n", "<leader>uu", vim.cmd.UndotreeToggle, { desc = "Toggle undotree" }) end

function M.config()
  init()
  keys()
end

return M
