local utils = require("serranomorante.utils")

vim.g.mapleader = " "

vim.go.guicursor = "n:block-Cursor/lCursor,a:blinkwait700-blinkoff400-blinkon250-Cursor/lCursor,o:hor25-Cursor/lCursor"

---@type string
local cache_path = vim.fn.stdpath("cache")
local undodir = utils.join_paths(cache_path, "undodir")
local shadadir = utils.join_paths(cache_path, "shadadir")
if not utils.is_directory(undodir) then vim.fn.mkdir(undodir, "p") end
if not utils.is_directory(shadadir) then vim.fn.mkdir(shadadir, "p") end

vim.go.viewoptions = vim.o.viewoptions:gsub(",curdir", "")
vim.go.diffopt = vim.o.diffopt .. ",linematch:60"

vim.wo.number = true
vim.bo.expandtab = true
vim.o.tabstop = 4
vim.bo.softtabstop = 4
vim.go.tabclose = "left"
vim.bo.shiftwidth = 4
vim.o.matchpairs = vim.o.matchpairs .. ",<:>"
vim.go.showmode = false

vim.o.swapfile = false
vim.go.backup = false

vim.go.shada = "'100,<0,%0,:1000,/1000,s500,h"
vim.go.shadafile = utils.join_paths(shadadir, "nvim.shada")
vim.go.undodir = undodir
vim.o.undofile = true
vim.go.jumpoptions = "stack,view"

vim.wo.signcolumn = "auto:2-4"
vim.go.isfname = vim.go.isfname .. ",@-@"
vim.wo.conceallevel = 0
vim.wo.cursorline = true
vim.wo.cursorlineopt = "number"
vim.go.wrapscan = false
vim.wo.wrap = false

vim.wo.foldcolumn = "1"
vim.wo.foldlevel = 99
vim.wo.foldenable = true
vim.go.foldopen = vim.go.foldopen:gsub(",hor", "")
vim.go.fillchars = "eob: ,fold: ,foldopen: ,foldsep: ,foldclose:+"

vim.go.splitright = true
vim.go.splitbelow = true
vim.go.maxsearchcount = 5000

vim.g.markdown_fenced_languages = { "html", "javascript", "typescript", "css", "scss", "vim", "lua", "json", "yaml" }
vim.g.max_file = { size = 1024 * 500, lines = 10000 } -- set global limits for large files
vim.g.codelens_enabled = true
vim.g.python_host_skip_check = 1 -- improve buffer startup time (supposedly)

---This is specific to my setup in order to add git worktrees support
---to gitsigns.nvim
vim.g.git_worktrees = {
  {
    toplevel = vim.env.HOME,
    gitdir = vim.env.HOME .. "/.dotfiles",
  },
}

vim.go.updatetime = 50
vim.go.timeoutlen = 500
vim.go.showtabline = 2

vim.go.inccommand = "split"

vim.wo.list = true
vim.go.listchars = vim.go.listchars .. ",leadmultispace:  ,trail:·,tab:→ "
vim.go.completeopt = "menuone,noselect,noinsert,popup,fuzzy"
vim.go.pumheight = 15
vim.go.shortmess = "atToOF"
vim.go.showbreak = "⮎ "
vim.go.virtualedit = "all"
vim.go.messagesopt = "hit-enter,history:10000"
vim.go.wildmode = "lastused,full"
vim.go.wildcharm = ("\t"):byte()
vim.go.cmdheight = 1

vim.cmd.syntax("off")
vim.cmd.colorscheme("default")

vim.filetype.get_option = utils.hijack_commentstring_get_option()

vim.go.grepprg = "rg --vimgrep"
vim.go.chistory = 20
