local M = {}

local function keys()
  vim.keymap.set(
    "n",
    "<leader>cc",
    function()
      require("osv").launch({
        port = 8086,
        log = vim.env.DAP_LOG_LEVEL == "TRACE",
      })
    end,
    { desc = "DAP: Launch one small step for vimkind" }
  )
end

function M.config()
  keys()
  local dap = require("dap")
  dap.configurations.lua = {
    {
      type = "nlua",
      request = "attach",
      name = "Attach to running Neovim instance",
    },
  }

  function dap.adapters.nlua(callback, config)
    callback({ type = "server", host = config.host or "127.0.0.1", port = config.port or 8086 })
  end

  if Init_debug then require("osv").launch({ port = 8086, blocking = true }) end
  Init_debug = false
end

return M
