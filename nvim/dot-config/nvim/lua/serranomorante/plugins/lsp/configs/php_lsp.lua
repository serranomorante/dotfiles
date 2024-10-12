local binaries = require("serranomorante.binaries")

return {
  ---@param bufnr integer
  ---@return vim.lsp.ClientConfig
  config = function(bufnr)
    ---@type vim.lsp.ClientConfig
    return {
      name = "php-lsp",
      cmd = { binaries.phpactor(), "language-server" },
      root_dir = vim.fs.root(bufnr, {
        "composer.json",
        ".git",
      }),
    }
  end,
}
