local binaries = require("serranomorante.binaries")

return {
  ---@param bufnr integer
  ---@return vim.lsp.ClientConfig
  config = function(bufnr)
    return {
      cmd = { binaries.marksman(), "server" },
      root_dir = vim.fs.root(bufnr, {
        ".git",
      }),
    }
  end,
}
