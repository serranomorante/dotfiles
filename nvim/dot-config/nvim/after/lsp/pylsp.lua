local binaries = require("serranomorante.binaries")
local constants = require("serranomorante.constants")

---@type vim.lsp.Config
return {
  cmd = { binaries.pylsp() }, -- Use to debug: "-vvv", "--log-file", "/tmp/lsp.log"
  filetypes = constants.python_aliases,
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
  root_markers = {
    "pyproject.toml",
    "setup.py",
    "setup.cfg",
    "requirements.txt",
    "Pipfile",
    "pyrightconfig.json",
    ".git",
  },
}
