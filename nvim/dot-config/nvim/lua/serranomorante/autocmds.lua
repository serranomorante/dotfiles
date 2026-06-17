local utils = require("serranomorante.utils")

local general_settings_group = vim.api.nvim_create_augroup("general_settings", { clear = true })
local indent_line_group = vim.api.nvim_create_augroup("indent_line", { clear = true })
local terminal_window_options_group = vim.api.nvim_create_augroup("terminal_window_options", { clear = true })

local terminal_window_option_names = {
  "number",
  "relativenumber",
  "signcolumn",
  "foldcolumn",
  "foldenable",
}
local plain_terminal_window_options = {
  number = false,
  relativenumber = false,
  signcolumn = "no",
  foldcolumn = "0",
  foldenable = false,
}

local function current_window_options()
  local winid = vim.api.nvim_get_current_win()
  local options = {}
  for _, name in ipairs(terminal_window_option_names) do
    options[name] = vim.api.nvim_get_option_value(name, { win = winid })
  end
  return options
end

local function set_current_window_options(options)
  local winid = vim.api.nvim_get_current_win()
  for name, value in pairs(options) do
    vim.api.nvim_set_option_value(name, value, { win = winid })
  end
end

local function terminal_regular_options_from_other_window(bufnr)
  local current_winid = vim.api.nvim_get_current_win()
  for _, winid in ipairs(vim.fn.win_findbuf(bufnr)) do
    if winid ~= current_winid and vim.api.nvim_win_is_valid(winid) then
      local options = vim.w[winid].plain_terminal_saved_window_options
        or vim.w[winid].plain_terminal_last_regular_window_options
      if options then return vim.deepcopy(options) end
    end
  end
end

local function apply_terminal_window_options(bufnr)
  if not utils.is_terminal_buffer(bufnr) then
    if vim.w.plain_terminal_options_active then
      local saved_options = vim.w.plain_terminal_saved_window_options
        or vim.w.plain_terminal_last_regular_window_options
      if saved_options then set_current_window_options(saved_options) end
      vim.w.plain_terminal_saved_window_options = nil
      vim.w.plain_terminal_options_active = nil
      vim.w.plain_terminal_last_regular_window_options = saved_options or current_window_options()
    else
      vim.w.plain_terminal_last_regular_window_options = current_window_options()
    end
    return
  end

  if not vim.w.plain_terminal_options_active then
    vim.w.plain_terminal_saved_window_options = terminal_regular_options_from_other_window(bufnr)
      or vim.w.plain_terminal_last_regular_window_options
      or current_window_options()
  end
  vim.w.plain_terminal_options_active = true
  set_current_window_options(plain_terminal_window_options)
  vim.schedule(function()
    if vim.api.nvim_get_current_buf() == bufnr then utils.refresh_terminal_window(bufnr) end
  end)
end

vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "WinEnter", "WinNew", "TermOpen" }, {
  desc = "Keep terminal windows free of editor columns",
  group = terminal_window_options_group,
  callback = function(args) apply_terminal_window_options(args.buf) end,
})

vim.api.nvim_create_autocmd("OptionSet", {
  desc = "Remember non-terminal window column options",
  group = terminal_window_options_group,
  pattern = terminal_window_option_names,
  callback = function(args)
    if utils.is_terminal_buffer(args.buf) or vim.w.plain_terminal_saved_window_options then return end
    vim.w.plain_terminal_last_regular_window_options = current_window_options()
  end,
})

vim.api.nvim_create_autocmd("TextYankPost", {
  desc = "Highlight yanked text",
  group = vim.api.nvim_create_augroup("highlight_yank", { clear = true }),
  callback = function()
    vim.highlight.on_yank({
      timeout = 300,
      on_macro = true,
    })
  end,
})

vim.api.nvim_create_autocmd({ "BufWinEnter", "TermOpen" }, {
  desc = "Make q close help, terminal, dap floats, etc",
  group = vim.api.nvim_create_augroup("q_close_windows", { clear = true }),
  callback = function(args)
    if not vim.g.q_close_windows then vim.g.q_close_windows = {} end
    if vim.g.q_close_windows[args.buf] then return end
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(args.buf, "n")) do
      if map.lhs == "q" then return end
    end
    local buftype = vim.api.nvim_get_option_value("buftype", { buf = args.buf })
    local filetype = vim.api.nvim_get_option_value("filetype", { buf = args.buf })
    if
      vim.list_contains({ "help", "nofile", "quickfix", "prompt", "nowrite", "terminal" }, buftype)
      or vim.list_contains({ "help", "qf" }, filetype)
    then
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

vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile", "BufWritePost" }, {
  desc = "Update indent line on BufReadPost, BufNewFile and BufWritePost",
  group = indent_line_group,
  callback = function(args)
    if vim.b[args.buf].large_buf then return end
    vim.schedule(function() -- schedule to ensure correct GuessIndent execution
      if utils.is_available("guess-indent") then require("guess-indent").set_from_buffer(args.buf, false, true) end
      local winid = vim.fn.bufwinid(args.buf)
      if not vim.api.nvim_win_is_valid(winid) then return end
      vim.wo[winid].listchars = utils.update_indent_line(vim.wo[winid].listchars, vim.bo[args.buf].shiftwidth)
    end)
  end,
})

vim.api.nvim_create_autocmd("OptionSet", {
  desc = "Update indent line on shiftwidth change",
  group = indent_line_group,
  pattern = "shiftwidth",
  callback = function(args)
    if vim.b[args.buf].large_buf then return end
    if vim.v.option_type == "local" then
      utils.update_indent_line_curbuf(args.buf)
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

vim.api.nvim_create_autocmd("CmdwinEnter", {
  desc = "Clear ephemeral messages when entering command-line window",
  group = general_settings_group,
  callback = function()
    utils.clear_ui2_ephemeral_messages()
    vim.schedule(utils.clear_ui2_ephemeral_messages)
  end,
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
    if utils.is_available("gitsigns") then require("gitsigns").refresh() end
  end,
})

vim.api.nvim_create_autocmd("FileChangedShellPost", {
  desc = "Notify when file changes outside vim",
  group = general_settings_group,
  callback = function(args)
    vim.api.nvim_echo({ { "File changed on disk. Buffer reloaded", "Comment" } }, false, {})

    local bufnr = args.buf
    local filetype = vim.bo[bufnr].filetype
    local bufname = vim.api.nvim_buf_get_name(bufnr)
    local notes_dir = vim.fs.normalize(vim.env.HOME .. "/data/notes/foam")
    local is_notes_file = vim.fs.normalize(bufname):sub(1, #notes_dir + 1) == notes_dir .. "/"
    if not is_notes_file or not vim.list_contains({ "markdown", "markdown.system_health" }, filetype) then return end

    for _, client in ipairs(vim.lsp.get_clients({ name = "marksman", bufnr = bufnr, _uninitialized = true })) do
      client:stop(true)
    end
    pcall(vim.lsp.enable, "marksman")
  end,
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

vim.api.nvim_create_autocmd("FileType", {
  desc = "Enable wrap on some filetypes",
  pattern = "help",
  group = general_settings_group,
  command = "set wrap",
})

vim.api.nvim_create_autocmd("FileType", {
  desc = "Add custom bg to ephemeral msg window",
  pattern = "msg",
  group = general_settings_group,
  callback = function(args)
    local winid = vim.fn.bufwinid(args.buf)
    vim.api.nvim_set_option_value("winhl", "Normal:CustomEphemeralMsgBg", { win = winid })
  end,
})

vim.api.nvim_create_autocmd("FileType", {
  desc = "Don't allow <C-l> on cmd windows",
  pattern = "vim",
  group = general_settings_group,
  callback = function(args)
    vim.keymap.set("n", "<C-l>", function()
      if vim.fn.getcmdwintype() ~= "" then return end
    end, { buffer = args.buf })
  end,
})

local treesitter_filetypes = utils.ts_compatible_filetypes()
local regex_filetypes = { "qf", "html", "remind", "spajson", "log", "pager", "rst", "dosini", "make" }
vim.api.nvim_create_autocmd("FileType", {
  desc = "Enable syntax highlighting",
  group = vim.api.nvim_create_augroup("ts_highlighting", { clear = true }),
  callback = function(args)
    if vim.b[args.buf].large_buf then return end
    local filetype = vim.api.nvim_get_option_value("filetype", { buf = args.buf })
    local treesitter_lang = vim.treesitter.language.get_lang(filetype) or filetype
    ---Enable treesitter syntax highlighting
    if vim.list_contains(treesitter_filetypes, filetype) then vim.treesitter.start(args.buf, treesitter_lang) end
    ---Enable treesitter indent (except for html filetype)
    if vim.list_contains(treesitter_filetypes, filetype) and not vim.list_contains({ "html" }, filetype) then
      vim.api.nvim_set_option_value(
        "indentexpr",
        "v:lua.require'serranomorante.treesitter.indent'.expr()",
        { buf = args.buf }
      )
    end
    ---Enable regex syntax highlighting
    if vim.list_contains(regex_filetypes, filetype) then
      vim.api.nvim_set_option_value("syntax", "ON", { buf = args.buf })
    end
  end,
})

vim.api.nvim_create_autocmd("BufWritePost", {
  desc = "Refresh remind database on every :w",
  group = vim.api.nvim_create_augroup("remind_update", { clear = true }),
  pattern = vim.env.HOME .. "/data/notes/**/*.md",
  callback = vim.schedule_wrap(function()
    if not utils.cwd_is_notes() then return end
    local ok, error = pcall(vim.cmd.RemindUpdate)
    if not ok then return vim.api.nvim_echo({ { vim.fn.string(error) } }, false, { err = true }) end
    vim.schedule(function() vim.api.nvim_echo({ { "Reminder database updated", "DiagnosticOk" } }, false, {}) end)
  end),
})

vim.api.nvim_create_autocmd("VimEnter", {
  desc = "Open the most recently used file on startup",
  group = general_settings_group,
  callback = vim.schedule_wrap(function()
    if utils.nvim_started_without_args() and not utils.cwd_is_home() then vim.cmd.normal({ "'0" }) end
  end),
})

vim.api.nvim_create_autocmd({ "TermOpen", "BufWinEnter" }, {
  desc = "Set keymaps for terminals",
  group = general_settings_group,
  callback = function(args)
    if not utils.is_terminal_buffer(args.buf) then return end
    vim.keymap.set("n", "i", "<cmd>normal! m`<CR>i", { buffer = args.buf, desc = "" })
  end,
})
