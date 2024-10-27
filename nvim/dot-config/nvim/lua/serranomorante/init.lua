require("serranomorante.globals")
require("serranomorante.set")
require("serranomorante.remap")
require("serranomorante.autocmds")

local plugins = {
  "resession",
  "trailblazer",
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
  "conform",
  "gitsigns",
  "overseer",
  "aerial",
  "diffview",
  "quicker",
  "dap.nvim-dap",
  "dap.nvim-dap-virtual-text",
  "smartyank",
  "nvim-fundo",
}

for _, plugin in ipairs(plugins) do
  require("serranomorante.plugins." .. plugin).config()
end
