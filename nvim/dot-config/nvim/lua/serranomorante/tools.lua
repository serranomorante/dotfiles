local M = {}

---Don't add nvim-lspconfig names like `tsserver` here
---@type table<string, ToolEnsureInstall>
M.by_filetype = {
  asm = { parsers = { "asm" } },
  javascript = {
    fmts = { "eslint_d" },
    linters = { "eslint_d" },
    lsp = { "@vtsls/language-server", "@tailwindcss/language-server" },
    dap = {
      "js-debug-adapter", -- or { "js-debug-adapter", version = "v1.82.0" },
    },
    parsers = { "javascript", "typescript", "tsx", "jsdoc", "vue" },
  },
  lua = { fmts = { "stylua" }, lsp = { "lua-language-server" }, parsers = { "lua", "luap", "luadoc" } },
  json = {
    fmts = { "prettierd" },
    lsp = { "vscode-langservers-extracted" },
    parsers = { "json" },
  },
  yaml = { fmts = { "ansible-lint" }, lsp = { "yaml-language-server" }, parsers = { "yaml" } },
  c = { lsp = { "clangd" }, parsers = { "cpp" } },
  python = {
    lsp = { "python-lsp-server" },
    dap = { "debugpy" },
    parsers = { "python", "requirements" },
  },
  bash = {
    fmts = { "shfmt" },
    lsp = { "bash-language-server" },
    dap = { "bash-debug-adapter" },
    parsers = { "bash" },
  },
  fish = { parsers = { "fish" }, lsp = { "fish-lsp" } },
  markdown = {
    lsp = { "marksman" },
    linters = { "markdownlint" },
    fmts = { "mdformat" },
    parsers = { "markdown" },
  },
  toml = { parsers = { "toml" } },
  tmux = { parsers = { "tmux" } },
  gitcommit = { parsers = { "gitcommit" } },
  diff = { parsers = { "diff" } },
  vim = { parsers = { "vim", "vimdoc" }, lsp = { "vim-language-server" } },
  html = {
    fmts = { "prettierd", "superhtml" },
    lsp = { "vscode-langservers-extracted", "@tailwindcss/language-server" },
    parsers = { "html" },
  },
  xml = { parsers = { "xml" } },
  css = { lsp = { "vscode-langservers-extracted", "@tailwindcss/language-server" }, parsers = { "css", "scss" } },
  php = { lsp = { "phpactor" }, parsers = { "php" } },
  go = { fmts = { "gofmt" }, lsp = { "gopls" }, parsers = { "go" } },
  svelte = { parsers = { "svelte" } },
  sshconfig = { parsers = { "ssh_config" } },
  kitty = { parsers = { "file:kitty" } },
  gitignore = { parsers = { "gitignore" } },
  systemd = { parsers = { "git_config" } },
  org = { parsers = { "file:org" } },
  conf = { parsers = { "file:conf" } },
  gitconfig = { parsers = { "file:gitconfig" } },
  editorconfig = { parsers = { "editorconfig" } },
  make = { parsers = { "file:make" } },
  dockerfile = { parsers = { "dockerfile" } },
  ---No specific filetype
  all = {
    parsers = {
      "disassembly",
      "query",
      "regex",
      "git_config",
      "git_rebase",
      "gitattributes",
      "rst",
      "mermaid",
      "udev",
    },
  },
}

---Make sure all possible filetypes that a tool can handle are considered here
M.by_filetype.vue = vim.deepcopy(M.by_filetype.javascript)
table.insert(M.by_filetype.vue.lsp, "@vue/language-server")
M.by_filetype.tsx = vim.deepcopy(M.by_filetype.javascript)
M.by_filetype.typescript = vim.deepcopy(M.by_filetype.javascript)
M.by_filetype.typescriptreact = vim.deepcopy(M.by_filetype.javascript)
M.by_filetype.javascriptreact = vim.deepcopy(M.by_filetype.javascript)

M.by_filetype.cpp = vim.deepcopy(M.by_filetype.c)

M.by_filetype.scss = vim.deepcopy(M.by_filetype.css)

M.by_filetype.sh = vim.deepcopy(M.by_filetype.bash)

M.by_filetype["markdown.system_health"] = vim.deepcopy(M.by_filetype.markdown)

M.by_filetype.jsonc = vim.deepcopy(M.by_filetype.json)
M.by_filetype["yaml.ansible"] = vim.deepcopy(M.by_filetype.yaml)
table.insert(M.by_filetype["yaml.ansible"].lsp, "@ansible/ansible-language-server")

if vim.fn.executable("npm") == 0 then M.by_filetype.javascript = {} end
if vim.fn.executable("pip") == 0 then M.by_filetype.python = {} end

return M
