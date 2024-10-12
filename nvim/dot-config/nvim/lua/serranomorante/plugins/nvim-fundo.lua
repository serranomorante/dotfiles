local M = {}

local function init() vim.opt.undofile = true end

function M.config()
  init()
  require("fundo").install()
  require("fundo").setup()
end

return M
