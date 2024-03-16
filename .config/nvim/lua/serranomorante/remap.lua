local utils = require("serranomorante.utils")

-- Toggle wrap
vim.keymap.set("n", "<leader>uw", function()
  vim.wo.wrap = not vim.wo.wrap
  vim.notify("Wrap " .. utils.bool2str(vim.wo.wrap))
end, { desc = "Toggle wrap" })

-- New file
vim.keymap.set("n", "<leader>nb", "<cmd>enew<cr>", { desc = "New buffer" })

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
vim.keymap.set("n", "<leader>zf", function()
  -- https://github.com/pocco81/true-zen.nvim/blob/2b9e210e0d1a735e1fa85ec22190115dffd963aa/lua/true-zen/focus.lua#L11-L15
  if vim.fn.winnr("$") == 1 then
    vim.notify("there is only one window open", vim.log.levels.INFO)
    return
  end
  vim.cmd("tab split")
end, { desc = "Zen: Focus split on new tab" })

-- Tabs move
vim.keymap.set("n", "<t", "<cmd>tabmove -1<CR>", { desc = "Move tab left" })
vim.keymap.set("n", ">t", "<cmd>tabmove +1<CR>", { desc = "Move tab right" })

vim.keymap.set("n", "<leader>qf", "<cmd>botright copen<CR>", { desc = "Quickfix: Open list" })
vim.keymap.set("n", "<leader>ql", "<cmd>botright lopen<CR>", { desc = "Quickfix: Open location list" })

vim.keymap.set({ "i", "n" }, "<esc>", "<cmd>noh<cr><esc>", { desc = "Escape and clear hlsearch" })

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

if vim.env.TMUX and utils.is_available("plenary.nvim") then
  local Job = require("plenary.job")
  local command = { "tmux", "display-message", "-p", "#{window_panes}:#{?window_zoomed_flag,Z, }" }

  ---Generate command args dynamically base on current tmux window layout
  local function generate_args(window_layout)
    local args = { "split-window" }
    local only_one_pane = vim.startswith(window_layout, "1") -- this assumes no more than 9 panes

    ---`{bottom-right}` splits to bottom if there's only 1 pane in the current window
    ---with this conditional I make sure to avoid that
    if only_one_pane then
      local horizontal_split = "-h"
      local pane_size = { "-l", "30%" }
      table.insert(args, horizontal_split)
      vim.list_extend(args, pane_size)
    else
      local vertical_split = "-v"
      local target_pane = { "-t", "{bottom-right}" }
      table.insert(args, vertical_split)
      vim.list_extend(args, target_pane)
    end

    return args
  end

  ---Handles if tmux window is zoomed
  local function handle_zoom(on_exit)
    Job:new({
      command = "tmux",
      args = { "resize-pane", "-Z" },
      on_exit = on_exit,
    }):start()
  end

  vim.keymap.set("n", "<leader>pf", function()
    local project_directory = vim.fn.getcwd()
    local window_layout = utils.cmd(command)
    if window_layout == nil then return end
    local is_zoom = string.find(window_layout, "Z")

    if is_zoom then
      handle_zoom(
        function()
          Job:new({
            command = "tmux",
            args = generate_args(window_layout),
            cwd = project_directory,
          }):start()
        end
      )
    else
      Job:new({
        command = "tmux",
        args = generate_args(window_layout),
        cwd = project_directory,
      }):start()
    end
  end, { desc = "Tmux: Open project directory" })

  vim.keymap.set("n", "<leader>pF", function()
    local current_file = vim.fn.resolve(vim.fn.expand("%"))
    local file_directory = vim.fn.fnamemodify(current_file, ":p:h")
    local window_layout = utils.cmd(command)
    if window_layout == nil then return end
    local is_zoom = string.find(window_layout, "Z")

    if is_zoom then
      handle_zoom(
        function()
          Job:new({
            command = "tmux",
            args = generate_args(window_layout),
            cwd = file_directory,
          }):start()
        end
      )
    else
      Job:new({
        command = "tmux",
        args = generate_args(window_layout),
        cwd = file_directory,
      }):start()
    end
  end, { desc = "Tmux: Open file directory" })
end
