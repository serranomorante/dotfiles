local M = {}

---Names should be mason and treesitter compatible
---@type table<string, ToolEnsureInstall>
M.by_filetype = {
  javascript = {
    formatters = { "eslint_d", "prettierd" },
    linters = { "eslint_d" },
    lsp = { "typescript-language-server", "tailwindcss-language-server" },
    dap = {
      "js-debug-adapter", -- or { "js-debug-adapter", version = "v1.82.0" },
    },
    parsers = { "javascript", "typescript", "tsx" },
    extensions = { "coc-tsserver", "@yaegassy/coc-tailwindcss3" },
  },
  lua = { formatters = { "stylua" }, lsp = { "lua-language-server" }, parsers = { "lua", "luap", "luadoc" } },
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
    dap = { "bash-debug-adapter" },
    parsers = { "bash" },
  },
  fish = { formatters = { "fish_indent" }, parsers = { "fish" } },
  markdown = { lsp = { "marksman" }, formatters = { "prettierd" }, parsers = { "markdown" } },
  toml = { lsp = { "taplo" }, parsers = { "toml" } },
  tmux = { parsers = { "tmux" } },
  gitcommit = { parsers = { "gitcommit" } },
  diff = { parsers = { "diff" } },
  vim = { parsers = { "vim", "vimdoc" } },
  all = { parsers = { "regex" } },
}

---Make sure all possible filetypes that a tool can handle are considered here
M.by_filetype.tsx = vim.deepcopy(M.by_filetype.javascript)
M.by_filetype.typescript = vim.deepcopy(M.by_filetype.javascript)
M.by_filetype.typescriptreact = vim.deepcopy(M.by_filetype.javascript)
M.by_filetype.javascriptreact = vim.deepcopy(M.by_filetype.javascript)

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
