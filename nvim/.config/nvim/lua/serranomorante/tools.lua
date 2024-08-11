local M = {}

---Don't add nvim-lspconfig names like `tsserver` here
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
    extensions = { "coc-tsserver", "@yaegassy/coc-tailwindcss3" },
  },
  lua = { formatters = { "stylua" }, lsp = { "lua-language-server" }, parsers = { "lua", "luap", "luadoc" } },
  json = { lsp = { "vscode-json-languageserver" }, formatters = { "prettierd" }, parsers = { "json", "jsonc" } },
  yaml = { lsp = { "yaml-language-server" }, parsers = { "yaml" } },
  c = { lsp = { "clangd" }, parsers = { "cpp" } },
  python = {
    lsp = { "python-lsp-server" },
    dap = { "debugpy" },
  },
  bash = {
    formatters = { "beautysh" },
    lsp = { "bash-language-server" },
    dap = { "bash-debug-adapter" },
    parsers = { "bash" },
  },
  fish = { parsers = { "fish" }, lsp = { "fish-lsp" } },
  markdown = {
    lsp = { "marksman" },
    formatters = { "prettierd" },
    parsers = { "markdown" },
    extensions = { "coc-markdown-preview-enhanced" },
  },
  toml = { parsers = { "toml" } },
  tmux = { parsers = { "tmux" } },
  gitcommit = { parsers = { "gitcommit" } },
  diff = { parsers = { "diff" } },
  vim = { parsers = { "vim", "vimdoc" }, lsp = { "vim-language-server" } },
  html = { parsers = { "html" } },
  xml = { parsers = { "xml" } },
  css = { parsers = { "css" } },
  all = { parsers = { "regex" }, extensions = { "coc-webview" } },
}

---Make sure all possible filetypes that a tool can handle are considered here
M.by_filetype.tsx = vim.deepcopy(M.by_filetype.javascript)
M.by_filetype.typescript = vim.deepcopy(M.by_filetype.javascript)
M.by_filetype.typescriptreact = vim.deepcopy(M.by_filetype.javascript)
M.by_filetype.javascriptreact = vim.deepcopy(M.by_filetype.javascript)

if vim.fn.executable("npm") == 0 then M.by_filetype.javascript = {} end
if vim.fn.executable("pip") == 0 then M.by_filetype.python = {} end

M.package_name_to_lspconfig = {
  ["lua-language-server"] = "lua_ls",
  ["bash-language-server"] = "bashls",
  ["yaml-language-server"] = "yamlls",
  ["vscode-json-languageserver"] = "jsonls",
  ["ruff-lsp"] = "ruff_lsp",
  ["typescript-language-server"] = "tsserver",
  ["rust-analyzer"] = "rust_analyzer",
  ["tailwindcss-language-server"] = "tailwindcss",
  ["vim-language-server"] = "vimls",
  ["fish-lsp"] = "fish_lsp",
  ["python-lsp-server"] = "pylsp",
}

return M
