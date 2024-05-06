local utils = require("serranomorante.utils")

vim.g.mapleader = " "

vim.opt.guicursor = ""

---@type string
---@diagnostic disable-next-line: assign-type-mismatch
local cache_path = vim.fn.stdpath("cache")
local undodir = utils.join_paths(cache_path, "undodir")
local shadadir = utils.join_paths(cache_path, "shadadir")
if not utils.is_directory(undodir) then vim.fn.mkdir(undodir, "p") end
if not utils.is_directory(shadadir) then vim.fn.mkdir(shadadir, "p") end

vim.opt.viewoptions:remove("curdir")

vim.opt.diffopt:append("linematch:60") -- enable linematch diff algorithm

vim.opt.number = true
vim.opt.expandtab = true
vim.opt.tabstop = 4
vim.opt.softtabstop = 4
vim.opt.shiftwidth = 4

vim.opt.swapfile = false
vim.opt.backup = false

vim.opt.shada = "'100,<0,%0,:10000,/10000,s500,h"
vim.opt.shadafile = utils.join_paths(shadadir, "nvim.shada")
vim.opt.undodir = undodir
vim.opt.undofile = true
vim.opt.jumpoptions:append("stack")

vim.opt.scrolloff = 4
vim.opt.signcolumn = "yes:1"
vim.opt.isfname:append("@-@")
vim.opt.cursorline = true
vim.opt.cursorlineopt = "number"

vim.opt.clipboard = "unnamedplus"

vim.opt.foldcolumn = "1"
vim.opt.foldlevel = 99 -- set high foldlevel for nvim-ufo
vim.opt.foldlevelstart = 99 -- start with all code unfolded
vim.opt.foldenable = true -- enable fold for nvim-ufo
vim.opt.foldopen:remove({ "hor" })
vim.opt.fillchars:append({ eob = " ", fold = " ", foldopen = " ", foldsep = " ", foldclose = "+" })

vim.opt.splitright = true
vim.opt.splitbelow = true

vim.g.markdown_fenced_languages = { "html", "javascript", "typescript", "css", "scss", "vim", "lua", "json", "yaml" }

vim.g.max_file = { size = 1024 * 500, lines = 5000 } -- set global limits for large files
vim.g.codelens_enabled = true
vim.g.python_host_skip_check = 1 -- improve buffer startup time (supposedly)
vim.g.node_system_executable = "node" -- fallback, this might be mutated by nvim-dap config

-- This is specific to my setup in order to add git worktrees support
-- to gitsigns.nvim
vim.g.git_worktrees = {
  {
    toplevel = vim.env.HOME,
    gitdir = vim.env.HOME .. "/.dotfiles",
  },
}

vim.opt.updatetime = 50
vim.opt.timeoutlen = 300

vim.opt.inccommand = "split"
vim.opt.formatoptions:remove({ "c", "r", "o" })

vim.opt.list = true
vim.opt_global.listchars:append({ leadmultispace = "  ", trail = " " })
vim.opt.completeopt = { "menuone", "noselect", "noinsert", "popup" }
vim.opt.pumheight = 15
vim.o.shortmess = "atToOF"

vim.cmd.syntax("off")
vim.cmd.colorscheme("default")
