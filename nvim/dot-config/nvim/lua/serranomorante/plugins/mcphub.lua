local constants = require("serranomorante.constants")

local M = {}

local function init() vim.cmd([[cab ch MCPHub]]) end

---@param params MCPHub.ParsedParams
---@return boolean|string|nil
local function auto_approve(params)
  if params.server_name == "playwright-extension" then return true end
  return false
end

local function opts()
  ---@type MCPHub.Config
  return {
    cmd = constants.BINARIES.mcp_hub_executable(),
    auto_approve = auto_approve,
  }
end

function M.config()
  init()
  require("mcphub").setup(opts())
end

return M
