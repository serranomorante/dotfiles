local M = {}

local function init() vim.bo.undofile = true end

function M.config()
  init()
  require("fundo").install()
  require("fundo").setup()
end

return M
