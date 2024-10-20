local augroup = vim.api.nvim_create_augroup
local autocmd = vim.api.nvim_create_autocmd
local utils = require("serranomorante.utils")

local general_settings_group = augroup("general_settings", { clear = true })
local indent_line_group = augroup("indent_line", { clear = true })

autocmd("BufWinEnter", {
  desc = "Make q close help, man, dap floats",
  group = augroup("q_close_windows", { clear = true }),
  callback = function(event)
    local buftype = vim.api.nvim_get_option_value("buftype", { buf = event.buf })
    local match = vim.tbl_contains({ "help", "nofile" }, buftype)
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

autocmd("BufReadPost", {
  desc = "Update indent line on BufReadPost event",
  group = indent_line_group,
  callback = function(args)
    if vim.b[args.buf].large_buf then return end
    vim.wo.listchars = utils.update_indent_line(vim.wo.listchars, vim.bo.shiftwidth)
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
  pattern = { "qf", "undotree", "OverseerList", "OverseerForm", "aerial", "git", "grapple", "oil" },
  callback = function(args) vim.api.nvim_set_option_value("syntax", args.match, { buf = args.buf }) end,
})

autocmd("CmdwinEnter", {
  desc = "Set mappings and options local to command-line window",
  group = general_settings_group,
  callback = function(args)
    vim.api.nvim_set_option_value("syntax", "vim", { buf = args.buf })
    if vim.b[args.buf].saved_complete == nil then
      vim.b[args.buf].saved_complete = vim.api.nvim_get_option_value("complete", { buf = args.buf })
    end
    vim.api.nvim_set_option_value("complete", ".,t", { buf = args.buf })
  end,
})

autocmd("CmdwinLeave", {
  desc = "Set mappings and options local to command-line window",
  group = general_settings_group,
  callback = function(args)
    if vim.b[args.buf].saved_complete == nil then return end
    vim.api.nvim_set_option_value("complete", vim.b[args.buf].saved_complete, { buf = args.buf })
  end,
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
    ---Fix autocmds.lua:142: Vim:E11: Invalid in command-line window; <CR> executes, CTRL-C quits
    ---TODO check if instead of skipping `checktime` there's a way to skipped it from the cmd window only
    if vim.fn.getcmdwintype() ~= "" then return end
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

---@type table
local default_cursor_hl = vim.api.nvim_get_hl(0, { name = "Cursor" })
autocmd("ModeChanged", {
  desc = "Change cursor color on operator-pending mode",
  group = general_settings_group,
  pattern = {
    "i:niI", -- from insert mode to operator-pending
    "niI:*", -- from operator-pending mode to any
  },
  callback = function(event)
    if event.match == "i:niI" then
      vim.api.nvim_set_hl(0, "Cursor", { bg = "NvimLightBlue" })
    else
      vim.api.nvim_set_hl(0, "Cursor", default_cursor_hl)
    end
  end,
})
