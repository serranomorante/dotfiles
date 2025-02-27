local binaries = require("serranomorante.binaries")

return {
  ---@param bufnr integer
  ---@return vim.lsp.ClientConfig
  config = function(bufnr)
    return {
      name = "gopls",
      cmd = { binaries.gopls() },
      root_dir = vim.fs.root(bufnr, {
        "go.work",
        "go.mod",
        ".git",
      }),
    }
  end,
}
