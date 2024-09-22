local M = {}

local keys = function()
  vim.keymap.set("n", "<leader>cc", function()
    ---osv uses `nvim --headless --embed` so we cannot start neovim with `--listen`
    ---https://github.com/jbyuki/one-small-step-for-vimkind/issues/14#issuecomment-1105938997
    if vim.env.CUSTOM_NVIM_LISTEN_ADDRESS == vim.v.servername then
      return vim.notify("Please start nvim without any arguments", vim.log.levels.ERROR)
    end
    require(".osv").launch({ port = 8086 })
  end, { desc = "DAP: Launch one small step for vimkind" })
end

M.config = function()
  keys()
  local dap = require("dap")
  dap.configurations.lua = {
    {
      type = "nlua",
      request = "attach",
      name = "Attach to running Neovim instance",
    },
  }

  dap.adapters.nlua = function(callback, config)
    ---@diagnostic disable-next-line: undefined-field
    callback({ type = "server", host = config.host or "127.0.0.1", port = config.port or 8086 })
  end
end

return M
