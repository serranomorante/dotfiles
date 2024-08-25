local M = {}

local opts = function()
  return {
    max_lines = 1,
    trim_scope = "inner", -- outer
  }
end

M.config = function() require("treesitter-context").setup(opts()) end

return M
