local M = {}

local function init()
  vim.lsp.config("*", {
    roor_markers = {
      ".git",
    },
  })

  ---See: https://github.com/VonHeikemen/lsp-zero.nvim/blob/dev-v3/doc/md/guides/under-the-hood.md
  ---See: https://github.com/mfussenegger/nvim-lint/issues/340#issuecomment-1676438571
  vim.diagnostic.config({
    signs = {
      text = {
        [vim.diagnostic.severity.INFO] = "",
        [vim.diagnostic.severity.HINT] = "",
        [vim.diagnostic.severity.WARN] = "",
        [vim.diagnostic.severity.ERROR] = "",
      },
    },
    virtual_text = { source = true },
    float = { border = "single", source = true },
    jump = { float = { scope = "line" } },
  })
end

function M.config()
  init()

  local group = vim.api.nvim_create_augroup("personal-lsp", { clear = true })
  vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function(args)
      local client_id = args.data.client_id
      local client = vim.lsp.get_client_by_id(client_id)
      if client then
        require("serranomorante.plugins.lsp.event_handlers").attach(client, args.buf)
      else
        require("serranomorante.plugins.nvim-ufo").config()
        vim.notify("Cannot find client " .. client_id, vim.log.levels.ERROR)
      end
    end,
  })

  vim.api.nvim_create_autocmd("LspDetach", {
    group = group,
    callback = function(args)
      local client_id = args.data.client_id
      local client = vim.lsp.get_client_by_id(client_id)
      if client then
        require("serranomorante.plugins.lsp.event_handlers").detach(client, args.buf)
      else
        vim.notify("Cannot find client " .. client_id, vim.log.levels.ERROR)
      end
    end,
  })
end

return M
