local constants = require("serranomorante.constants")

if not constants.BINARIES.clangd then return {} end

---@type vim.lsp.Config
return {
  cmd = { constants.BINARIES.clangd() },
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
