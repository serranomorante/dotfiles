local binaries = require("serranomorante.binaries")

return {
  ---@param bufnr integer
  ---@return vim.lsp.ClientConfig
  config = function(bufnr)
    return {
      name = "html-lsp",
      cmd = { binaries.vscode_html_language_server(), "--stdio" },
      root_dir = vim.fs.root(bufnr, {
        ".fish",
        ".git",
      }),
    }
  end,
}
