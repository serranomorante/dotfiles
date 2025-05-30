local constants = require("serranomorante.constants")
local utils = require("serranomorante.utils")
local events = require("serranomorante.events")

-- Toggle wrap
vim.keymap.set("n", "<leader>uw", function()
  vim.wo.wrap = not vim.wo.wrap
  vim.api.nvim_echo(
    { { "Wrap " }, { utils.bool2str(vim.wo.wrap), vim.wo.wrap and "DiagnosticOk" or "Comment" } },
    false,
    {}
  )
end, { desc = "Toggle wrap" })

-- New file
vim.keymap.set("n", "<leader>nb", "<cmd>enew<CR>", { desc = "New buffer" })

---Closing vim
vim.keymap.set("n", "ZQ", "<cmd>qa!<CR>", { desc = 'Quit without checking for changes (same as ":q!")' })

-- Move selected lines around
vim.keymap.set("x", "J", ":m '>+1<CR>gv=gv", { desc = "Move lines down" })
vim.keymap.set("x", "K", ":m '<-2<CR>gv=gv", { desc = "Move lines up" })
vim.keymap.set("x", "H", "<gv", { desc = "Indent lines left" })
vim.keymap.set("x", "L", ">gv", { desc = "Indent lines right" })

-- Replace the highlighted word
vim.keymap.set(
  "n",
  "<leader>sr",
  [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]],
  { desc = "Replace highlighted word" }
)

-- Close window
vim.keymap.set("n", "<C-q>", "<cmd>close<CR>")

-- Tabs navigation
vim.keymap.set("n", "te", "<cmd>tabedit<CR>", { desc = "New tab" })
vim.keymap.set("n", "tc", "<cmd>tabclose<CR>", { desc = "Close tab" })
vim.keymap.set("n", "<leader>zf", function()
  -- https://github.com/pocco81/true-zen.nvim/blob/2b9e210e0d1a735e1fa85ec22190115dffd963aa/lua/true-zen/focus.lua#L11-L15
  vim.cmd("tab split")
end, { desc = "Zen: Focus split on new tab" })

-- Tabs move
vim.keymap.set("n", "<t", "<cmd>tabmove -1<CR>", { desc = "Move tab left" })
vim.keymap.set("n", ">t", "<cmd>tabmove +1<CR>", { desc = "Move tab right" })

vim.keymap.set("n", "<ESC>", "<cmd>noh<CR><ESC>", { desc = "Escape and clear hlsearch" })

vim.keymap.set("i", "<C-f>", "<Esc>gUiw`]a", { desc = "Make the word before the cursor uppercase" })

vim.keymap.set("n", "<leader>zl", function()
  local winid = vim.api.nvim_get_current_win()
  vim.wo[winid].fillchars = vim.wo[winid].fillchars .. ",foldopen:"
  vim.defer_fn(function() vim.wo[winid].fillchars = vim.wo[winid].fillchars .. ",foldopen: " end, 2000)
end, { desc = "Temporarily show available folds" })

vim.keymap.set("n", "u", function()
  events.event("Undo")
  return "u"
end, { expr = true })

vim.keymap.set("n", "<C-r>", function()
  events.event("Redo")
  return "<C-r>"
end, { expr = true })

vim.keymap.set("n", "<leader>yy", function()
  local bufname, line, col = utils.get_cursor_position()
  vim.fn.setreg("+", string.format("%s:%s:%s", bufname, line, col))
  local part_1, part_2, part_3 = 'Yanked! "%s', ":%s:%s", '"'
  vim.api.nvim_echo({
    { part_1:format(bufname), "DiagnosticInfo" },
    { part_2:format(line, col), "DiffText" },
    { part_3, "DiagnosticInfo" },
  }, false, {})
end, { desc = "Yank <filename>:<line>:<col>" })

vim.keymap.set("n", "<C-S-e>", "zl", { desc = "Scroll right horizontally" })
vim.keymap.set("n", "<C-S-y>", "zh", { desc = "Scroll left horizontally" })
vim.keymap.set("n", "<C-S-d>", "50zl", { desc = "Scroll right horizontally +50" })
vim.keymap.set("n", "<C-S-u>", "50zh", { desc = "Scroll left horizontally +50" })
vim.keymap.set("n", "z.", "<cmd>normal! zszH<CR>", { desc = "Horizontally center cursor position" })

vim.keymap.set({ "n", "x", "o" }, "'", "`", { desc = "Make single quote act like backtick" })

vim.keymap.set("n", "<leader>ff", ":Find ''" .. constants.POSITION_CURSOR_BETWEEN_QUOTES, { desc = "Find files" })
vim.keymap.set(
  "n",
  "<leader>fw",
  ":Grep ''" .. constants.POSITION_CURSOR_BETWEEN_QUOTES,
  { desc = "Grep text [You must escape single quotes and pipes]" }
)
vim.keymap.set(
  "n",
  "<leader>fh",
  ":Helpgrep ''" .. constants.POSITION_CURSOR_BETWEEN_QUOTES,
  { desc = "Grep on vim help pages" }
)
vim.keymap.set("n", "<leader>fb", ":b <Tab><Tab>", { desc = "Open recent buffers in wildmenu" }) -- will go directly to the second most recent buffer
vim.keymap.set("n", "<leader>fc", ":Grep '\\b<C-r><C-w>\\b'", { desc = "Grep word under cursor" })
vim.keymap.set({ "x", "v" }, "<leader>fv", function()
  local start_pos, end_pos, mode = vim.fn.getpos("v"), vim.fn.getpos("."), vim.fn.mode()
  local region = vim.fn.getregion(start_pos, end_pos, { type = mode })
  return (":<C-u>Grep '%s'"):format(region[1])
end, { desc = "Find visual selection", expr = true })

vim.keymap.set("t", "<leader>lm", function()
  utils.feedkeys("<C-\\><C-n>", "t")
  return "<cmd>close<CR>"
end, { desc = "Close terminal window", expr = true, nowait = true, silent = true })

---Quickfix keymaps
vim.keymap.set("n", "<leader>qf", function()
  if vim.fn.getcmdwintype() ~= "" then
    return vim.api.nvim_echo({ { "Cannot open quickfix list from command-line window", "DiagnosticWarn" } }, false, {})
  end
  utils.toggle_qflist()
end, { desc = "Toggle quickfix list" })

vim.keymap.set("n", "<leader>ql", function()
  if vim.fn.getcmdwintype() ~= "" then
    return vim.api.nvim_echo({ { "Cannot open loclist from command-line window", "DiagnosticWarn" } }, false, {})
  end
  utils.toggle_qflist({ loclist = true })
end, { desc = "Open location list" })

vim.keymap.set("n", "<A-j>", utils.next_qf_item, { desc = "Next quickfix list item" })
vim.keymap.set("n", "<A-k>", utils.prev_qf_item, { desc = "Prev quickfix list item" })
