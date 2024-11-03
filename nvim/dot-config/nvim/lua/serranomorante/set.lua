local utils = require("serranomorante.utils")

vim.g.mapleader = " "

vim.opt.guicursor = {
  "n:block-Cursor/lCursor",
  "a:blinkwait700-blinkoff400-blinkon250-Cursor/lCursor",
  "o:hor25-Cursor/lCursor",
}

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
vim.opt.showmode = false

vim.opt.swapfile = false
vim.opt.backup = false

vim.opt.shada = "'100,<0,%0,:10,/10,s500,h"
vim.opt.shadafile = utils.join_paths(shadadir, "nvim.shada")
vim.opt.undodir = undodir
vim.opt.undofile = true
vim.opt.jumpoptions = { "stack", "view" }

vim.opt.scrolloff = 4
vim.opt.signcolumn = "auto:2-4"
vim.opt.isfname:append("@-@")
vim.opt.cursorline = true
vim.opt.cursorlineopt = "number"
vim.opt.wrapscan = false

vim.opt.foldcolumn = "1"
vim.opt.foldlevel = 99
vim.opt.foldlevelstart = 99 -- start with all code unfolded
vim.opt.foldenable = true
vim.opt.foldopen:remove({ "hor" })
vim.opt.fillchars:append({ eob = " ", fold = " ", foldopen = " ", foldsep = " ", foldclose = "+" })

vim.opt.splitright = true
vim.opt.splitbelow = true

vim.g.markdown_fenced_languages = { "html", "javascript", "typescript", "css", "scss", "vim", "lua", "json", "yaml" }

vim.g.max_file = { size = 1024 * 500, lines = 5000 } -- set global limits for large files
vim.g.codelens_enabled = true
vim.g.python_host_skip_check = 1 -- improve buffer startup time (supposedly)

-- This is specific to my setup in order to add git worktrees support
-- to gitsigns.nvim
vim.g.git_worktrees = {
  {
    toplevel = vim.env.HOME,
    gitdir = vim.env.HOME .. "/.dotfiles",
  },
}

vim.opt.updatetime = 50
vim.opt.timeoutlen = 500
vim.opt.showtabline = 2

vim.opt.inccommand = "split"

vim.opt.list = true
vim.opt_global.listchars:append({ leadmultispace = "  ", trail = " " })
vim.opt.completeopt = { "menuone", "noselect", "noinsert", "popup", "fuzzy" }
vim.opt.pumheight = 15
vim.o.shortmess = "atToOF"

vim.cmd.syntax("off")
vim.cmd.colorscheme("default")

vim.filetype.get_option = utils.hijack_commentstring_get_option()
