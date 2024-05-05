local M = {}

---Names should be mason and treesitter compatible
---@type table<string, ToolEnsureInstall>
M.by_filetype = {
  javascript = {
    formatters = { "eslint_d", "prettierd" },
    linters = { "eslint_d" },
    lsp = { "typescript-language-server", "tailwindcss-language-server", "vtsls" },
    dap = {
      "js-debug-adapter", -- or { "js-debug-adapter", version = "v1.82.0" },
    },
    parsers = { "javascript", "typescript", "tsx" },
  },
  lua = { formatters = { "stylua" }, lsp = { "lua-language-server" } },
  go = {
    formatters = { "gofumpt", "goimports", "gomodifytags" },
    lsp = { "gopls" },
    extra = { "iferr", "impl" },
    parsers = { "go" },
  },
  json = { lsp = { "json-lsp" }, formatters = { "prettierd" }, parsers = { "json", "jsonc" } },
  yaml = { lsp = { "yaml-language-server" }, parsers = { "yaml" } },
  c = { lsp = { "clangd" }, parsers = { "cpp" } },
  python = {
    formatters = { "isort", "black" },
    linters = { "mypy", "pylint" },
    lsp = { "basedpyright", "ruff-lsp" },
    dap = { "debugpy" },
  },
  rust = { lsp = { "rust-analyzer" }, parsers = { "rust" } },
  bash = {
    formatters = { "beautysh" },
    lsp = { "bash-language-server" },
    parsers = { "bash" },
  },
  fish = { formatters = { "fish_indent" }, parsers = { "fish" } },
  markdown = { lsp = { "marksman" }, formatters = { "prettierd" } },
  toml = { lsp = { "taplo" }, parsers = { "toml" } },
  all = { parsers = {} },
}

if vim.fn.executable("npm") == 0 then M.by_filetype.javascript = {} end
if vim.fn.executable("go") == 0 then M.by_filetype.go = {} end
if vim.fn.executable("pip") == 0 then M.by_filetype.python = {} end

M.mason_to_lspconfig = {
  ["lua-language-server"] = "lua_ls",
  ["bash-language-server"] = "bashls",
  ["yaml-language-server"] = "yamlls",
  ["json-lsp"] = "jsonls",
  ["ruff-lsp"] = "ruff_lsp",
  ["typescript-language-server"] = "tsserver",
  ["rust-analyzer"] = "rust_analyzer",
  ["tailwindcss-language-server"] = "tailwindcss",
}

return M
