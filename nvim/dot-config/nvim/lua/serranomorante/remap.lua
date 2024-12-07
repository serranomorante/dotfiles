local utils = require("serranomorante.utils")
local events = require("serranomorante.events")

-- Toggle wrap
vim.keymap.set("n", "<leader>uw", function()
  vim.wo.wrap = not vim.wo.wrap
  vim.notify("Wrap " .. utils.bool2str(vim.wo.wrap))
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
  if vim.fn.winnr("$") == 1 then return vim.notify("there is only one window open", vim.log.levels.INFO) end
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
  local filename_with_cursor_pos = utils.filename_with_cursor_pos()
  vim.fn.setreg("+", filename_with_cursor_pos)
  vim.notify("Copied " .. filename_with_cursor_pos, vim.log.levels.INFO)
end, { desc = "Copy <filename>:<line>:<col>" })

vim.keymap.set("n", "<C-S-e>", "zl", { desc = "Scroll right horizontally" })
vim.keymap.set("n", "<C-S-y>", "zh", { desc = "Scroll left horizontally" })
vim.keymap.set("n", "<C-S-d>", "50zl", { desc = "Scroll right horizontally +50" })
vim.keymap.set("n", "<C-S-u>", "50zh", { desc = "Scroll left horizontally +50" })

vim.keymap.set({ "n", "x", "o" }, "'", "`", { desc = "Make single quote act like backtick" })

vim.keymap.set("n", "<A-j>", utils.next_qf_item, { desc = "Next quickfix list item" })
vim.keymap.set("n", "<A-k>", utils.prev_qf_item, { desc = "Prev quickfix list item" })
