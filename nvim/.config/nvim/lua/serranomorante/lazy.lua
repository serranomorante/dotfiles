local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", -- latest stable release
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  { import = "serranomorante.plugins" },
  { import = "serranomorante.plugins.lsp" },
  { import = "serranomorante.plugins.dap.nvim-dap" },
  { import = "serranomorante.plugins.dap.nvim-dap-python" },
  { import = "serranomorante.plugins.dap.one-small-step-for-vimkind" },
  { import = "serranomorante.plugins.statusline.heirline" },
  { import = "serranomorante.plugins.session.persistence" },
}, {
  change_detection = {
    notify = false,
  },
  install = {
    missing = false,
  },
  dev = {
    path = "~/repos",
    fallback = true,
    patterns = {
      -- "kevinhwang91/nvim-bqf",
      -- "LeonHeidelbach/trailblazer.nvim",
      -- "neovim/nvim-lspconfig",
      -- "kevinhwang91/nvim-treesitter",
      -- "mfussenegger/nvim-dap",
      -- "neovim/nvim-lspconfig",
      -- "marilari88/neotest-vitest",
      -- "ibhagwan/fzf-lua",
      -- "hedyhli/outline.nvim",
      "stevearc/aerial.nvim",
    },
  },
  diff = {
    cmd = "diffview.nvim",
  },
  readme = {
    enabled = false,
  },
})
