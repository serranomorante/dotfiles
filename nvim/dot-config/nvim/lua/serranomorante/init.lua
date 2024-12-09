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
  "undotree",
  "vim-sleuth",
  "treesitter.treesitter",
  "treesitter.treesitter-context",
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
  "nvim-fundo",
  "nnn",
}

for _, plugin in ipairs(plugins) do
  require("serranomorante.plugins." .. plugin).config()
end
