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
    local current_file = vim.fn.resolve(vim.fn.expand("%"))
    if not (current_file == "" or vim.api.nvim_get_option_value("buftype", { buf = args.buf }) == "nofile") then
      events.event("File")
    end

    ---Lazy load LSP plugins
    utils.load_plugin_by_filetype("LSP", { buffer = args.buf })

    ---https://github.com/AstroNvim/AstroNvim/commit/ba0fbdf974eb63639e43d6467f7232929b8b9b4c
    vim.schedule(function()
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

autocmd("BufReadPost", {
  desc = "Disable certain functionality on very large files",
  group = augroup("large_buf", { clear = true }),
  callback = function(args)
    local ok, stats = pcall((vim.uv.fs_stat or vim.loop.fs_stat), vim.api.nvim_buf_get_name(args.buf))
    vim.b[args.buf].large_buf = (ok and stats and stats.size > vim.g.max_file.size)
      or vim.api.nvim_buf_line_count(args.buf) > vim.g.max_file.lines
  end,
})

-- I don't want `typescript-tools.nvim` CodeLens to be enable on startup
-- I also don't want `typescript-tools.nvim` CodeLens to refresh on "CursorHold" event
-- I want to enable both things on demand with keymaps
autocmd("LspAttach", {
  desc = "Remove auto commands from typescript-tools.nvim CodeLens feature",
  group = augroup("remove_typescript_tools_codelens", { clear = true }),
  callback = function()
    local cmds_found, ts_codelens_cmds = pcall(vim.api.nvim_get_autocmds, {
      group = "TypescriptToolsCodeLensGroup",
    })
    if cmds_found then
      if cmds_found then vim.tbl_map(function(cmd) vim.api.nvim_del_autocmd(cmd.id) end, ts_codelens_cmds) end
    end
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
  callback = function()
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
  callback = function() vim.wo.listchars = utils.update_indent_line(vim.wo.listchars, vim.bo.shiftwidth) end,
})
