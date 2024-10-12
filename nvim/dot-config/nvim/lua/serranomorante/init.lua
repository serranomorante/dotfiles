require("serranomorante.globals")
require("serranomorante.set")
require("serranomorante.remap")
require("serranomorante.autocmds")

local plugins = {
  "resession",
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
  "trailblazer",
  "conform",
  "gitsigns",
  "overseer",
  "aerial",
  "diffview",
  "colorizer",
  "quicker",
  "dap.nvim-dap",
  "dap.nvim-dap-python",
  "dap.nvim-dap-virtual-text",
  "smartyank",
}

for _, plugin in ipairs(plugins) do
  require("serranomorante.plugins." .. plugin).config()
end
