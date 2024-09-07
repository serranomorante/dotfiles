local augroup = vim.api.nvim_create_augroup
local autocmd = vim.api.nvim_create_autocmd
local utils = require("serranomorante.utils")

local general_settings_group = augroup("general_settings", { clear = true })
local indent_line_group = augroup("indent_line", { clear = true })

autocmd("TextYankPost", {
  desc = "Highlight yanked text",
  group = augroup("highlight_yank", { clear = true }),
  callback = function()
    vim.highlight.on_yank({
      timeout = 300,
      on_macro = true,
    })
  end,
})

autocmd("BufWinEnter", {
  desc = "Make q close help, man, quickfix, dap floats",
  group = augroup("q_close_windows", { clear = true }),
  callback = function(event)
    local buftype = vim.api.nvim_get_option_value("buftype", { buf = event.buf })
    local match = vim.tbl_contains({ "help", "nofile", "quickfix" }, buftype)
    if match and vim.fn.maparg("q", "n") == "" then
      vim.keymap.set("n", "q", "<cmd>close<cr>", {
        desc = "Close window",
        buffer = event.buf,
        silent = true,
        nowait = true,
      })
    end
  end,
})

autocmd("BufReadPre", {
  desc = "Disable certain functionality on very large files",
  group = augroup("large_buf", { clear = true }),
  callback = function(args)
    ---@diagnostic disable-next-line: undefined-field
    local ok, stats = pcall((vim.uv or vim.loop).fs_stat, args.file)
    if not ok or not stats then return end
    ---you can't use `nvim_buf_line_count` because this runs on BufReadPre
    local lines_count = #vim.fn.readfile(args.file)
    local is_large_buffer = stats.size > vim.g.max_file.size
      or lines_count > vim.g.max_file.lines
      or stats.size / lines_count > vim.o.synmaxcol
    vim.b[args.buf].large_buf = is_large_buffer
    if not is_large_buffer then return end
    ---Prevent slow initialization of large buffers
    vim.o.eventignore = "FileType"
    vim.schedule(function() vim.o.eventignore = "" end)
  end,
})

-- https://vi.stackexchange.com/a/8997
autocmd({ "BufWinLeave", "BufWinEnter" }, {
  desc = "Keep screen position zt,zz,zb after switching buffer",
  group = augroup("keep_screen_position", { clear = true }),
  callback = function(event)
    if event.event == "BufWinLeave" then
      vim.b.winview = vim.fn.winsaveview()
    else
      if vim.b.winview == nil then return end

      vim.fn.winrestview(vim.b.winview)
      vim.b.winview = nil
    end
  end,
})

autocmd("OptionSet", {
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

autocmd("VimResized", {
  desc = "Resize floating windows after resizing the terminal",
  group = augroup("resize_floating_windows", { clear = true }),
  callback = function()
    local is_floating = vim.api.nvim_win_get_config(0).relative ~= ""
    if is_floating then vim.api.nvim_win_set_width(0, vim.o.columns) end
  end,
})

autocmd({ "BufWinEnter", "WinEnter" }, { -- TermOpen would only execute the callback once
  desc = "Clear hlsearch highlights when entering terminal",
  pattern = "term://*",
  group = augroup("clear_hlsearch_on_term_open", { clear = true }),
  callback = vim.schedule_wrap(function() vim.cmd("nohlsearch") end),
})

autocmd("FileType", {
  desc = "Enable vim syntax option only for specific filetypes",
  group = general_settings_group,
  pattern = { "qf", "undotree", "OverseerList", "aerial", "git", "grapple", "oil" },
  callback = function(args) vim.cmd.set("syntax=" .. args.match) end,
})

autocmd("FileType", {
  desc = "Disable new line comments",
  group = general_settings_group,
  command = "set formatoptions-=cro",
})

autocmd({ "FocusGained", "BufEnter" }, {
  desc = "Perform buffer reload after file changes outside vim",
  group = general_settings_group,
  callback = function()
    local forbidden_modes = { "c" }
    if vim.list_contains(forbidden_modes, vim.fn.mode()) then return end
    vim.cmd.checktime()
  end,
})

autocmd("FileChangedShellPost", {
  desc = "Notify when file changes outside vim",
  group = general_settings_group,
  callback = function() vim.notify("File changed on disk. Buffer reloaded", vim.log.levels.INFO) end,
})

autocmd("FocusGained", {
  desc = "Redraw status on nvim focus",
  group = general_settings_group,
  command = "redrawstatus",
})
