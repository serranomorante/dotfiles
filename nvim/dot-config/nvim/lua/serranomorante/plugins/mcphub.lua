local M = {}

local function init() vim.cmd([[cab ch MCPHub]]) end

function M.config()
  init()
  require("mcphub").setup()
end

return M
