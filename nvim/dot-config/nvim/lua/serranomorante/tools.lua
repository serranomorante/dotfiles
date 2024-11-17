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
    parsers = { "javascript", "typescript", "tsx", "jsdoc" },
    extensions = { "coc-tsserver", "@yaegassy/coc-tailwindcss3" },
  },
  lua = { formatters = { "stylua" }, lsp = { "lua-language-server" }, parsers = { "lua", "luap", "luadoc" } },
  json = {
    formatters = { "prettierd" },
    parsers = { "json", "jsonc" },
    extensions = { "coc-json" },
  },
  yaml = { parsers = { "yaml" }, extensions = { "coc-yaml", "@yaegassy/coc-ansible" } },
  c = { lsp = { "clangd" }, parsers = { "cpp" } },
  python = {
    lsp = { "python-lsp-server" },
    dap = { "debugpy" },
    parsers = { "requirements" },
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
    formatters = { "mdformat" },
    parsers = { "markdown" },
    extensions = { "coc-markdown-preview-enhanced", "@yaegassy/coc-marksman", "coc-markdownlint" },
  },
  toml = { parsers = { "toml" } },
  tmux = { parsers = { "tmux" } },
  gitcommit = { parsers = { "gitcommit" } },
  diff = { parsers = { "diff" } },
  vim = { parsers = { "vim", "vimdoc" }, lsp = { "vim-language-server" } },
  html = { parsers = { "html" } },
  xml = { parsers = { "xml" } },
  css = { parsers = { "css" } },
  php = { parsers = { "php" } },
  all = {
    parsers = {
      "regex",
      "git_config",
      "git_rebase",
      "gitattributes",
      "gitignore",
      "rst",
      "ssh_config",
      "sxhkdrc",
      "dockerfile",
      "mermaid",
      "udev"
    },
    extensions = { "coc-webview" },
  },
}

---Make sure all possible filetypes that a tool can handle are considered here
M.by_filetype.tsx = vim.deepcopy(M.by_filetype.javascript)
M.by_filetype.typescript = vim.deepcopy(M.by_filetype.javascript)
M.by_filetype.typescriptreact = vim.deepcopy(M.by_filetype.javascript)
M.by_filetype.javascriptreact = vim.deepcopy(M.by_filetype.javascript)

M.by_filetype.jsonc = vim.deepcopy(M.by_filetype.json)
M.by_filetype["yaml.ansible"] = vim.deepcopy(M.by_filetype.yaml)

if vim.fn.executable("npm") == 0 then M.by_filetype.javascript = {} end
if vim.fn.executable("pip") == 0 then M.by_filetype.python = {} end

return M
