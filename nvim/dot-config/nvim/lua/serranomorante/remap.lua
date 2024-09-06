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
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move lines down" })
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move lines up" })
vim.keymap.set("v", "H", "<gv", { desc = "Indent lines left" })
vim.keymap.set("v", "L", ">gv", { desc = "Indent lines right" })

-- Replace the highlighted word
vim.keymap.set(
  "n",
  "<leader>sr",
  [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]],
  { desc = "Replace highlighted word" }
)

-- Horizontal and vertical splits
vim.keymap.set("n", "ss", "<cmd>split<CR>", { desc = "Horizontal split" })
vim.keymap.set("n", "sv", "<cmd>vsplit<CR>", { desc = "Vertical split" })

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

vim.keymap.set("n", "<leader>qf", "<cmd>botright copen<CR>", { desc = "Quickfix: Open list" })
vim.keymap.set("n", "<leader>ql", "<cmd>botright lopen<CR>", { desc = "Quickfix: Open location list" })

vim.keymap.set("n", "<ESC>", "<cmd>noh<CR><ESC>", { desc = "Escape and clear hlsearch" })

vim.keymap.set("i", "<C-f>", "<Esc>gUiw`]a", { desc = "Make the word before the cursor uppercase" })

vim.keymap.set("n", "<leader>zl", function()
  local winid = vim.api.nvim_get_current_win()
  local foldopen_visible = vim.wo[winid].fillchars:gsub("foldopen: ", "foldopen:")
  vim.wo[winid].fillchars = foldopen_visible

  -- Hide available folds after timout
  local timeout = 2000
  vim.defer_fn(function()
    local foldopen_hidden = vim.wo[winid].fillchars:gsub("foldopen:", "foldopen: ")
    vim.wo[winid].fillchars = foldopen_hidden
  end, timeout)
end, { desc = "Ufo: Temporarily show available folds" })

if vim.env.TMUX then
  ---Prepare tmux command to render all panes at the bottom based on directory
  ---@param dir string
  ---@return nil|string[]
  local function new_pane_on_dir(dir)
    local cmd = string.format("tmux split-window -c %s", dir)
    local split_window = utils
      .cmd({
        "tmux",
        "display",
        "-p",
        "#{?#{==:#{window_panes},1},#{l:" .. cmd .. " -v -l 30%},#{l:" .. cmd .. " -h}}",
      })
      :gsub("\n", "")
    local window_zoomed_flag = utils
      .cmd({ "tmux", "display", "-p", "#{?#{==:#{window_zoomed_flag},1},#{l:tmux resize-pane -Z},}" })
      :gsub("\n", "")
    if window_zoomed_flag ~= nil and #window_zoomed_flag > 0 then utils.cmd(vim.split(window_zoomed_flag, " ")) end
    if split_window == "" or split_window == nil then return end
    return vim.split(split_window .. " -t {bottom-right}", " ")
  end

  vim.keymap.set("n", "<leader>pf", function()
    local dir = vim.fn.getcwd()
    if vim.bo.filetype == "oil" then dir = require("oil").get_current_dir() end
    local result = new_pane_on_dir(dir)
    if result then utils.cmd(result) end
  end, { desc = "TMUX: new pane in cwd" })

  vim.keymap.set("n", "<leader>pF", function()
    local dir = vim.fn.fnamemodify(vim.fn.resolve(vim.fn.expand("%")), ":p:h")
    if vim.bo.filetype == "oil" then dir = require("oil").get_current_dir() end
    local result = new_pane_on_dir(dir)
    if result then utils.cmd(result) end
  end, { desc = "TMUX: new pane on file directory" })
end

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
end, { desc = "Copy <filename>:<line>:<col>" })
