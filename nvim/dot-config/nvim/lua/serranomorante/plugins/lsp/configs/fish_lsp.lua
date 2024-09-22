local binaries = require("serranomorante.binaries")

return {
  ---@param bufnr integer
  ---@return vim.lsp.ClientConfig
  config = function(bufnr)
    return {
      name = "fish-lsp",
      cmd = { binaries.fish_lsp(), "start" },
      cmd_env = { fish_lsp_show_client_popups = false },
      root_dir = vim.fs.root(bufnr, {
        ".fish",
        ".git",
      }),
    }
  end,
}
