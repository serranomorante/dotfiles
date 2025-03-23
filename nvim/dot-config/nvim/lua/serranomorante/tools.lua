local M = {}

---Don't add nvim-lspconfig names like `tsserver` here
---@type table<string, ToolEnsureInstall>
M.by_filetype = {
  asm = { parsers = { "asm" } },
  javascript = {
    fmts = { "eslint_d", "prettierd" },
    linters = { "eslint_d" },
    lsp = { "typescript-language-server", "tailwindcss-language-server", "vtsls" },
    dap = {
      "js-debug-adapter", -- or { "js-debug-adapter", version = "v1.82.0" },
    },
    parsers = { "javascript", "typescript", "tsx", "jsdoc", "vue" },
    extensions = { "coc-tsserver", "@yaegassy/coc-tailwindcss3", "@yaegassy/coc-volar" },
  },
  lua = { fmts = { "stylua" }, lsp = { "lua-language-server" }, parsers = { "lua", "luap", "luadoc" } },
  json = {
    fmts = { "prettierd" },
    parsers = { "json", "jsonc" },
    extensions = { "coc-json" },
  },
  yaml = { parsers = { "yaml" }, extensions = { "coc-yaml", "@yaegassy/coc-ansible" } },
  c = { lsp = { "clangd" }, parsers = { "cpp" }, extensions = { "coc-clangd" } },
  python = {
    lsp = { "python-lsp-server" },
    dap = { "debugpy" },
    parsers = { "requirements" },
  },
  bash = {
    fmts = { "beautysh" },
    lsp = { "bash-language-server" },
    dap = { "bash-debug-adapter" },
    parsers = { "bash" },
  },
  fish = { parsers = { "fish" }, lsp = { "fish-lsp" } },
  markdown = {
    lsp = { "marksman" },
    fmts = { "mdformat" },
    parsers = { "markdown" },
    extensions = { "@yaegassy/coc-marksman", "coc-markdownlint" },
  },
  toml = { parsers = { "toml" } },
  tmux = { parsers = { "tmux" } },
  gitcommit = { parsers = { "gitcommit" } },
  diff = { parsers = { "diff" } },
  vim = { parsers = { "vim", "vimdoc" }, lsp = { "vim-language-server" } },
  html = { parsers = { "html" } },
  xml = { parsers = { "xml" } },
  css = { parsers = { "css", "scss" }, extensions = { "coc-css" } },
  php = { parsers = { "php" }, extensions = { "coc-phpls" } },
  go = { fmts = { "gofmt" }, lsp = { "gopls" }, parsers = { "go" } },
  all = {
    parsers = {
      "disassembly",
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
      "udev",
    },
  },
}

---Make sure all possible filetypes that a tool can handle are considered here
M.by_filetype.vue = vim.deepcopy(M.by_filetype.javascript)
M.by_filetype.tsx = vim.deepcopy(M.by_filetype.javascript)
M.by_filetype.typescript = vim.deepcopy(M.by_filetype.javascript)
M.by_filetype.typescriptreact = vim.deepcopy(M.by_filetype.javascript)
M.by_filetype.javascriptreact = vim.deepcopy(M.by_filetype.javascript)

M.by_filetype.cpp = vim.deepcopy(M.by_filetype.c)

M.by_filetype.scss = vim.deepcopy(M.by_filetype.css)

M.by_filetype.jsonc = vim.deepcopy(M.by_filetype.json)
M.by_filetype["yaml.ansible"] = vim.deepcopy(M.by_filetype.yaml)

if vim.fn.executable("npm") == 0 then M.by_filetype.javascript = {} end
if vim.fn.executable("pip") == 0 then M.by_filetype.python = {} end

return M
