local M = {}

function M.config()
  if not require("serranomorante.utils").should_persist_local_state() then return end

  require("fundo").install()
  require("fundo").setup()
end

return M
