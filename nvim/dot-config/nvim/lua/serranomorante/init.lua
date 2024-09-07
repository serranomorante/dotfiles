require("serranomorante.globals")
require("serranomorante.set")
require("serranomorante.remap")
require("serranomorante.autocmds")

local plugins = {
  "session.persistence",
  "statusline.heirline",
  "coc",
  "lsp",
  "nvim-ufo",
  "undotree",
  "vim-sleuth",
  "treesitter.treesitter",
  "treesitter.treesitter-context",
  "oil",
  "oil-git-status",
  "fzf",
  "ale",
  "blame",
  "grapple",
  "conform",
  "gitsigns",
  "overseer",
  "aerial",
  "diffview",
  "colorizer",
  "quicker",
  "dap.nvim-dap",
  "dap.nvim-dap-python",
  "dap.one-small-step-for-vimkind",
  "smartyank",
}

for _, plugin in ipairs(plugins) do
  require("serranomorante.plugins." .. plugin).config()
end
