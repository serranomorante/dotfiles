local M = {}

local function init()
  vim.g.sleuth_gitcommit_heuristics = 0
  vim.g.sleuth_oil_heuristics = 0
end

function M.config() init() end

return M
