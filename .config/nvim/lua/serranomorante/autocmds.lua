local augroup = vim.api.nvim_create_augroup
local autocmd = vim.api.nvim_create_autocmd
local utils = require("serranomorante.utils")
local events = require("serranomorante.events")

local general = augroup("General Settings", { clear = true })

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
    if vim.tbl_contains({ "help", "nofile", "quickfix" }, buftype) and vim.fn.maparg("q", "n") == "" then
      vim.keymap.set("n", "q", "<cmd>close<cr>", {
        desc = "Close window",
        buffer = event.buf,
        silent = true,
        nowait = true,
      })
    end
  end,
})

autocmd({ "BufReadPost", "BufNewFile", "BufWritePost" }, {
  desc = "Execute `CustomFile` user event on valid buffers",
  group = augroup("file_user_events", { clear = true }),
  callback = function(args)
    local current_file = vim.api.nvim_buf_get_name(args.buf)
    if not (current_file == "" or vim.api.nvim_get_option_value("buftype", { buf = args.buf }) == "nofile") then
      events.event("File")
    end

    ---https://github.com/AstroNvim/AstroNvim/commit/ba0fbdf974eb63639e43d6467f7232929b8b9b4c
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(args.buf) then return end
      if vim.b[args.buf].large_buf then return end
      ---Lazy load LSP plugins
      utils.load_plugin_by_filetype("LSP", { buffer = args.buf })

      if vim.bo[args.buf].filetype then
        vim.api.nvim_exec_autocmds("FileType", { buffer = args.buf, modeline = false })
      end
      vim.api.nvim_exec_autocmds("CursorMoved", { modeline = false })
    end)
  end,
})

autocmd("BufEnter", {
  desc = "Disable New Line Comment",
  group = general,
  callback = function() vim.opt.formatoptions:remove({ "c", "r", "o" }) end,
})

autocmd("BufReadPre", {
  desc = "Disable certain functionality on very large files",
  group = augroup("large_buf", { clear = true }),
  callback = function(args)
    local ok, stats = pcall((vim.uv or vim.loop).fs_stat, vim.api.nvim_buf_get_name(args.buf))
    local is_large_buf = (ok and stats and stats.size > vim.g.max_file.size)
      or vim.api.nvim_buf_line_count(args.buf) > vim.g.max_file.lines
    vim.b[args.buf].large_buf = is_large_buf
    ---Disable `FileType` event to prevent loading LSP and improve performance
    vim.o.eventignore = is_large_buf and "FileType" or ""
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

local indent_line_group = augroup("indent_line", {})

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

autocmd("User", {
  desc = "Update indent line on CustomFile event",
  pattern = "CustomFile",
  group = indent_line_group,
  callback = function(args)
    if vim.b[args.buf].large_buf then return end
    vim.wo.listchars = utils.update_indent_line(vim.wo.listchars, vim.bo.shiftwidth)
  end,
})

autocmd("LspProgress", {
  desc = "Minimal LSP progress messages in the command line",
  group = augroup("lsp_progress", { clear = true }),
  pattern = { "begin", "end" },
  callback = function(args)
    ---Inspired by: https://github.com/rockyzhang24/dotfiles/blob/master/.config/nvim/lua/rockyz/lsp/progress.lua
    local id = args.data.client_id
    local kind = args.data.result.value.kind
    local title = args.data.result.value.title
    local icons = { ["begin"] = "⣾", ["end"] = "" }
    local client_name = vim.lsp.get_client_by_id(id).name
    local suffix_when_done = kind == "end" and "DONE!" or ""

    -- Assemble the output progress message
    -- - General: ⣾ [client_name] title: message
    -- - Done:     [client_name] title: DONE!
    local message = string.format("%s [%s] %s: %s", icons[kind], client_name, title, suffix_when_done)

    vim.notify(message, vim.log.levels.INFO, { title = "LSP Progress" })
  end,
})
