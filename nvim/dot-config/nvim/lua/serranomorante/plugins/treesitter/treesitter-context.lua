local M = {}

local opts = function()
  return {
    max_lines = 1,
    trim_scope = "inner", -- outer
    on_attach = function(bufnr)
      if vim.b[bufnr].large_buf then return false end
      return nil
    end,
  }
end

M.config = function() require("treesitter-context").setup(opts()) end

return M
