local M = {}

---Useful for example when deciding if to attach LSP client to that buffer
---@param bufnr integer buffer to check. 0 for current
---@return boolean true if the buffer represents a real, readable file
local function is_buf_readable_file(bufnr)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  return vim.fn.filereadable(bufname) == 1
end

---Same arguments as vim.lsp.start
---@param config vim.lsp.ClientConfig Configuration for the server.
---@param opts vim.lsp.start.Opts? Optional keyword arguments
---@return integer? client_id
M.start = function(config, opts)
  opts = opts or {}
  opts.bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  if not is_buf_readable_file(opts.bufnr) then return end

  local made_config = require("serranomorante.plugins.lsp.capabilities").merge_capabilities(config)
  if not made_config.root_dir then made_config.root_dir = vim.uv.os_tmpdir() end

  local client_id = vim.lsp.start(made_config, opts)
  if not client_id then vim.notify("Cannot start lsp: " .. made_config.cmd[1], vim.log.levels.WARN) end

  return client_id
end

local init = function()
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

  vim.lsp.handlers["textDocument/hover"] = vim.lsp.with(vim.lsp.handlers.hover, { border = "single" })
  vim.lsp.handlers["textDocument/signatureHelp"] = vim.lsp.with(vim.lsp.handlers.signature_help, { border = "single" })
end

M.config = function()
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
