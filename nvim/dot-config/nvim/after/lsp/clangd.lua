local binaries = require("serranomorante.binaries")
local constants = require("serranomorante.constants")

---@type vim.lsp.Config
return {
  cmd = { binaries.clangd() },
  filetypes = constants.c_aliases,
  capabilities = {
    offsetEncoding = "utf-16",
  },
  root_markers = {
    ".clangd",
    ".clang-tidy",
    ".clang-format",
    "compile_commands.json",
    "compile_flags.txt",
    "configure.ac",
    ".git",
  },
}
