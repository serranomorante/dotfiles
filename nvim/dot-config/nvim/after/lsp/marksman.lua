local constants = require("serranomorante.constants")
local publish_diagnostics = "textDocument/publishDiagnostics"
local default_publish_diagnostics = vim.lsp.handlers[publish_diagnostics]

if not constants.BINARIES.marksman then return {} end

---@type vim.lsp.Config
return {
  cmd = { constants.BINARIES.marksman(), "server" },
  filetypes = constants.markdown_aliases,
  handlers = {
    [publish_diagnostics] = function(err, result, ctx, config)
      require("serranomorante.markdown_block_ids").filter_marksman_diagnostics(result)
      return default_publish_diagnostics(err, result, ctx, config)
    end,
  },
  root_markers = { ".marksman.toml", ".git" },
}
