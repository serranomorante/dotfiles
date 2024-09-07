local binaries = require("serranomorante.binaries")

return {
  ---@param bufnr integer
  ---@return vim.lsp.ClientConfig
  config = function(bufnr)
    return {
      name = "pylsp",
      cmd = { binaries.pylsp() },
      settings = {
        pylsp = {
          plugins = {
            ruff = {
              enabled = true,
              formatEnabled = true,
            },
          },
        },
      },
      root_dir = vim.fs.root(bufnr, {
        "pyproject.toml",
        "setup.py",
        "setup.cfg",
        "requirements.txt",
        "Pipfile",
        "pyrightconfig.json",
        ".git",
      }),
    }
  end,
}
