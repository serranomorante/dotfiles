local binaries = require("serranomorante.binaries")

return {
  ---@param bufnr integer
  ---@return vim.lsp.ClientConfig
  config = function(bufnr)
    ---@type vim.lsp.ClientConfig
    return {
      name = "clangd",
      cmd = { binaries.clangd() },
      capabilities = {
        offsetEncoding = "utf-16",
      },
      root_dir = vim.fs.root(bufnr, {
        ".clangd",
        ".clang-tidy",
        ".clang-format",
        "compile_commands.json",
        "compile_flags.txt",
        "configure.ac",
        ".git",
      }),
    }
  end,
}
