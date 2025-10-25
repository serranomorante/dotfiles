local constants = require("serranomorante.constants")

local M = {}

local function init() vim.cmd([[cab ch MCPHub]]) end

local function opts()
  ---@type MCPHub.Config
  return {
    cmd = constants.BINARIES.mcp_hub_executable(),
  }
end

function M.config()
  init()
  require("mcphub").setup(opts())
end

return M
