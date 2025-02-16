local utils = require("serranomorante.utils")

local general_settings_group = vim.api.nvim_create_augroup("general_settings", { clear = true })
local indent_line_group = vim.api.nvim_create_augroup("indent_line", { clear = true })

vim.api.nvim_create_autocmd("TextYankPost", {
  desc = "Highlight yanked text",
  group = vim.api.nvim_create_augroup("highlight_yank", { clear = true }),
  callback = function()
    vim.hl.on_yank({
      timeout = 300,
      on_macro = true,
    })
  end,
})

vim.api.nvim_create_autocmd("BufWinEnter", {
  desc = "Make q close help, man, dap floats, etc",
  group = vim.api.nvim_create_augroup("q_close_windows", { clear = true }),
  callback = function(args)
    if not vim.g.q_close_windows then vim.g.q_close_windows = {} end
    if vim.g.q_close_windows[args.buf] then return end
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(args.buf, "n")) do
      if map.lhs == "q" then return end
    end
    if vim.list_contains({ "help", "nofile", "quickfix", "prompt", "nowrite" }, vim.bo[args.buf].buftype) then
      vim.g.q_close_windows[args.buf] = true
      vim.keymap.set("n", "q", "<cmd>close<CR>", {
        desc = "Close window with q",
        buffer = args.buf,
        silent = true,
        nowait = true,
      })
    end
  end,
})

vim.api.nvim_create_autocmd("BufReadPre", {
  desc = "Mark buffer as large",
  group = vim.api.nvim_create_augroup("large_buf", { clear = true }),
  callback = function(args)
    if vim.list_contains({ "help", "nofile", "quickfix", "prompt" }, vim.bo[args.buf].buftype) then return end
    if vim.b[args.buf].large_buf then return end
    local ok, is_large_file = pcall(utils.is_large_file, args.file)
    if ok and is_large_file then
      vim.api.nvim_buf_set_var(args.buf, "large_buf", is_large_file)
      vim.o.eventignore = "all" -- best performance for very large files
      vim.schedule(function() vim.o.eventignore = "" end)
    end
  end,
})

vim.api.nvim_create_autocmd("BufReadPost", {
  desc = "Update indent line on BufReadPost event",
  group = indent_line_group,
  callback = function(args)
    if vim.b[args.buf].large_buf then return end
    vim.wo.listchars = utils.update_indent_line(vim.wo.listchars, vim.bo[args.buf].shiftwidth)
  end,
})

vim.api.nvim_create_autocmd("OptionSet", {
  desc = "Update indent line on shiftwidth change",
  group = indent_line_group,
  pattern = "shiftwidth",
  callback = function(args)
    if vim.b[args.buf].large_buf then return end
    if vim.v.option_type == "local" then
      utils.update_indent_line_curbuf()
    else
      vim.go.listchars = utils.update_indent_line(vim.go.listchars, vim.go.shiftwidth)
    end
  end,
})

vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, { -- TermOpen would only execute the callback once
  desc = "Clear hlsearch highlights when entering terminal",
  pattern = "term://*",
  group = vim.api.nvim_create_augroup("clear_hlsearch_on_term_open", { clear = true }),
  callback = vim.schedule_wrap(function() vim.cmd("nohlsearch") end),
})

vim.api.nvim_create_autocmd("FileType", {
  desc = "Enable vim syntax option only for specific filetypes",
  group = general_settings_group,
  pattern = "qf",
  callback = function(args) vim.api.nvim_set_option_value("syntax", "ON", { buf = args.buf }) end,
})

vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter" }, {
  desc = "Perform buffer reload after file changes outside vim",
  group = general_settings_group,
  callback = function()
    local forbidden_modes = { "c" }
    ---Fix autocmds.lua:142: Vim:E11: Invalid in command-line window; <CR> executes, CTRL-C quits
    ---TODO check if instead of skipping `checktime` there's a way to skipped it from the cmd window only
    if vim.fn.getcmdwintype() ~= "" then return end
    if vim.list_contains(forbidden_modes, vim.fn.mode()) then return end
    vim.cmd.checktime()
  end,
})

vim.api.nvim_create_autocmd("FileChangedShellPost", {
  desc = "Notify when file changes outside vim",
  group = general_settings_group,
  callback = function() vim.notify("File changed on disk. Buffer reloaded", vim.log.levels.INFO) end,
})

vim.api.nvim_create_autocmd("FocusGained", {
  desc = "Redraw status on nvim focus",
  group = general_settings_group,
  command = "redrawstatus",
})

local guicursor = vim.api.nvim_get_option_value("guicursor", {})
local previous_mode = nil
vim.api.nvim_create_autocmd({ "InsertEnter", "InsertLeave" }, {
  desc = "Change cursor on operator-pending mode `:help i_CTRL-O`",
  group = general_settings_group,
  callback = function()
    local current_mode = vim.api.nvim_get_mode().mode
    vim.api.nvim_set_option_value(
      "guicursor",
      (current_mode == "niI" and previous_mode ~= current_mode) and "a:block-CustomOperatorPending" or guicursor,
      {}
    )
    previous_mode = current_mode
  end,
})
