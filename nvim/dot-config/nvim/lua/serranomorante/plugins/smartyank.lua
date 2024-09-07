local M = {}

local opts = function()
  return {
    highlight = {
      timeout = 100,
    },
  }
end

M.config = function() require("smartyank").setup(opts()) end

return M
