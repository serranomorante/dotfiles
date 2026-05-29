local utils = require("serranomorante.utils")
local constants = require("serranomorante.constants")

vim.g.mapleader = " "

vim.go.guicursor = "n:block-Cursor/lCursor,a:blinkwait700-blinkoff400-blinkon250-Cursor/lCursor,o:hor25-Cursor/lCursor"

---@type string
local cache_path = vim.fn.stdpath("cache")
local local_state = utils.local_state_config(constants.CWD, vim.v.servername, cache_path)
if local_state.persist and not utils.is_directory(local_state.undodir) then vim.fn.mkdir(local_state.undodir, "p") end
if local_state.persist and not utils.is_directory(local_state.shadadir) then vim.fn.mkdir(local_state.shadadir, "p") end

vim.opt.exrc = true
vim.opt.secure = true

vim.go.viewoptions = vim.o.viewoptions:gsub(",curdir", "")

vim.wo.number = true
vim.wo.foldtext = ""
vim.bo.expandtab = true
vim.bo.scrollback = 1000000
vim.o.tabstop = 4
vim.bo.softtabstop = 4
vim.go.tabclose = "left"
vim.bo.shiftwidth = 4
vim.o.matchpairs = vim.o.matchpairs .. ",<:>"
vim.go.showmode = false

vim.o.swapfile = false
vim.go.backup = false

vim.go.shada = "'2000,<3000,%0,:3000,/3000,@1000,s2048,h"
vim.go.shadafile = local_state.shadafile
if local_state.persist then vim.go.undodir = local_state.undodir end
vim.o.undofile = local_state.persist
if local_state.persist then
  local secret_undo_group = vim.api.nvim_create_augroup("serranomorante_secret_persistent_undo", { clear = true })
  local function disable_secret_persistent_undo(args)
    local name = vim.api.nvim_buf_get_name(args.buf)
    if name ~= "" and utils.is_secret_persistent_undo_path(name) then vim.bo[args.buf].undofile = false end
  end
  vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile", "BufFilePost" }, {
    group = secret_undo_group,
    callback = disable_secret_persistent_undo,
  })
  disable_secret_persistent_undo({ buf = vim.api.nvim_get_current_buf() })
end
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
vim.go.fillchars = "eob: ,fold: ,foldopen: ,foldsep: ,foldinner: ,foldclose:+"

vim.go.splitright = true
vim.go.splitbelow = true
vim.go.maxsearchcount = 5000

vim.g.markdown_fenced_languages = { "html", "javascript", "typescript", "css", "scss", "vim", "lua", "json", "yaml" }
vim.g.max_file = { size = 1024 * 700, lines = 15000 } -- set global limits for large files
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
vim.go.shortmess = "atToOFC"
vim.go.pumborder = "single"
vim.go.showbreak = "⮎ "
vim.go.virtualedit = "all"
vim.go.messagesopt = "hit-enter,history:10000"
vim.go.wildmode = "lastused,full"
vim.go.wildcharm = ("\t"):byte()
vim.go.cmdheight = 1

vim.cmd.syntax("manual")
vim.cmd.colorscheme("default")

vim.filetype.get_option = utils.hijack_commentstring_get_option()

vim.go.grepprg = "rg --vimgrep"
vim.go.chistory = 20

vim.ui.select = utils.select
