local constants = require("serranomorante.constants")
local utils = require("serranomorante.utils")
local events = require("serranomorante.events")

local function has_running_prevent_quit_tasks()
  local ok_overseer, overseer = pcall(require, "overseer")
  local ok_constants, overseer_constants = pcall(require, "overseer.constants")
  if not ok_overseer or not ok_constants then return false end

  return unpack(overseer.list_tasks({
    status = overseer_constants.STATUS.RUNNING,
    filter = function(task) return task.metadata.PREVENT_QUIT end,
  })) ~= nil
end

local function open_directory_mark_with_overseer(dir)
  local ok_overseer, overseer = pcall(require, "overseer")
  local ok_template, nnn_explorer = pcall(require, "overseer.template.editor-tasks.TASK__nnn_explorer")
  if not ok_overseer or not ok_template then
    vim.cmd.edit(dir)
    return
  end

  overseer.run_task({
    autostart = false,
    name = nnn_explorer.name,
    params = { startdir = dir },
  }, function(task)
    if not task then return end
    task:subscribe("on_output", utils.dispose_on_window_close)
    task:subscribe("on_complete", utils.close_window_on_exit_0)
    task:start()
    utils.schedule_open_overseer_task_output(task)
  end)
end

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
vim.keymap.set("n", "<leader>p", "<cmd>PasteClipboardImage<CR>", { desc = "Paste clipboard image" })
vim.keymap.set("n", "<leader>mr", utils.run_shell_fence, { desc = "Run shell fence" })

---Closing vim
vim.keymap.set("n", "ZQ", function()
  if has_running_prevent_quit_tasks() then
    return "<cmd>echohl DiagnosticWarn | echom 'You have running tasks!' | echohl None<CR>"
  end

  if utils.has_remote_uis() then return "<cmd>detach<CR>" end
  return "<cmd>qa!<CR>"
end, { expr = true, desc = 'Quit without checking for changes (same as ":q!")' })

-- Move selected lines around
vim.keymap.set("x", "J", ":m '>+1<CR>gv=gv", { desc = "Move lines down" })
vim.keymap.set("x", "K", ":m '<-2<CR>gv=gv", { desc = "Move lines up" })
vim.keymap.set("x", "H", "<gv", { desc = "Indent lines left" })
vim.keymap.set("x", "L", ">gv", { desc = "Indent lines right" })

local VISUAL_SEARCH_PREFIX = "\\%V"
local visual_search_state = nil

local function prepare_visual_search_state()
  local pattern = vim.fn.getreg("/")
  if pattern == "" then return nil end

  local visual_pattern = pattern
  local restore_pattern = false
  if not vim.startswith(pattern, VISUAL_SEARCH_PREFIX) then
    visual_pattern = VISUAL_SEARCH_PREFIX .. pattern
    restore_pattern = true
  end

  visual_search_state = {
    pattern = pattern,
    restore_pattern = restore_pattern,
    visual_pattern = visual_pattern,
  }
  return visual_search_state
end

local function visual_search_repeat(direction, state)
  state = state or visual_search_state
  if not state then return false end
  if vim.fn.getreg("/") ~= state.pattern and vim.fn.getreg("/") ~= state.visual_pattern then
    visual_search_state = nil
    return false
  end

  local count = math.max(vim.v.count, 1)
  local forward = vim.v.searchforward == 1
  local visual_pattern = state.visual_pattern
  vim.fn.setreg("/", visual_pattern)

  local backwards = (direction == "n" and not forward) or (direction == "N" and forward)
  local flags = backwards and "b" or ""
  for _ = 1, count do
    if vim.fn.search(visual_pattern, flags) == 0 then break end
  end

  if state.restore_pattern and vim.fn.getreg("/") == visual_pattern then vim.fn.setreg("/", state.pattern) end
  return true
end

local function normal_search_repeat(direction)
  local count = vim.v.count > 0 and tostring(vim.v.count) or ""
  local ok, err = pcall(vim.cmd.normal, { count .. direction, bang = true })
  if ok then return end

  local msg = tostring(err):match("Vim:(E%d+: .*)") or tostring(err):match("(E%d+: .*)") or tostring(err)
  vim.v.errmsg = msg
  vim.api.nvim_echo({ { msg, "ErrorMsg" } }, true, {})
end

vim.keymap.set("x", "/", "/" .. VISUAL_SEARCH_PREFIX, { desc = "Search forward inside visual selection" })
vim.keymap.set("x", "?", "?" .. VISUAL_SEARCH_PREFIX, { desc = "Search backward inside visual selection" })
vim.keymap.set("x", "n", function()
  local state = prepare_visual_search_state()
  vim.cmd("normal! \27")
  visual_search_repeat("n", state)
end, {
  desc = "Next search match inside visual selection",
})
vim.keymap.set("x", "N", function()
  local state = prepare_visual_search_state()
  vim.cmd("normal! \27")
  visual_search_repeat("N", state)
end, {
  desc = "Previous search match inside visual selection",
})
vim.keymap.set("n", "n", function()
  if visual_search_repeat("n") then return end
  normal_search_repeat("n")
end, { desc = "Next search match" })
vim.keymap.set("n", "N", function()
  if visual_search_repeat("N") then return end
  normal_search_repeat("N")
end, { desc = "Previous search match" })

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

vim.keymap.set("n", "<ESC>", function()
  visual_search_state = nil
  return "<cmd>noh<CR><ESC>"
end, { desc = "Escape and clear hlsearch", expr = true })

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
vim.keymap.set({ "n", "x", "o" }, "''", "``zz", { desc = "Go to `` mark and center view" })

local FIND_EX_CMD = ":Find ''" .. constants.POSITION_CURSOR_BETWEEN_QUOTES
vim.keymap.set("n", "<leader>ff", FIND_EX_CMD, { desc = "Find files" })
vim.keymap.set("n", "<leader>f_", function()
  if utils.cwd_is_dotfiles() then return FIND_EX_CMD end
  return ":Find '' ~/dotfiles" .. constants.POSITION_CURSOR_BETWEEN_QUOTES
end, { desc = "Find in dotfiles", expr = true })

local GREP_EX_CMD = ":Grep ''" .. constants.POSITION_CURSOR_BETWEEN_QUOTES
vim.keymap.set("n", "<leader>fw", GREP_EX_CMD, { desc = "Grep text [You must escape single quotes and pipes]" })
vim.keymap.set("n", "<leader>g_", function()
  if utils.cwd_is_dotfiles() then return GREP_EX_CMD end
  return ":Grep '' ~/dotfiles" .. constants.POSITION_CURSOR_BETWEEN_QUOTES
end, { desc = "Grep in dotfiles [You must escape single quotes and pipes]", expr = true })
vim.keymap.set(
  "n",
  "<leader>fh",
  ":Helpgrep ''" .. constants.POSITION_CURSOR_BETWEEN_QUOTES,
  { desc = "Grep on vim help pages" }
)

vim.keymap.set("n", "<leader>fb", ":b <Tab><Tab>", { desc = "Open recent buffers in wildmenu" }) -- will go directly to the second most recent buffer

local GREP_UNDER_CURSOR_EX_CMD = ":Grep '<C-r><C-w>\\b'" .. constants.POSITION_CURSOR_BETWEEN_QUOTES .. "\\b"
vim.keymap.set("n", "<leader>fc", GREP_UNDER_CURSOR_EX_CMD, { desc = "Grep word under cursor" })
vim.keymap.set("n", "<leader>gc", function()
  if utils.cwd_is_dotfiles() then return GREP_UNDER_CURSOR_EX_CMD end
  return ":Grep '<C-r><C-w>\\b' ~/dotfiles" .. constants.POSITION_CURSOR_BETWEEN_QUOTES .. "\\b"
end, { desc = "Grep word under cursor in dotfiles", expr = true })
vim.keymap.set({ "x", "v" }, "<leader>fv", function()
  local start_pos, end_pos, mode = vim.fn.getpos("v"), vim.fn.getpos("."), vim.fn.mode()
  local region = vim.fn.getregion(start_pos, end_pos, { type = mode })
  return (":<C-u>Grep '%s'"):format(region[1])
end, { desc = "Find visual selection", expr = true })
vim.keymap.set({ "x", "v" }, "<leader>fV", function()
  local start_pos, end_pos, mode = vim.fn.getpos("v"), vim.fn.getpos("."), vim.fn.mode()
  local region = vim.fn.getregion(start_pos, end_pos, { type = mode })
  return (":<C-u>Grep '%s' ~/dotfiles"):format(region[1])
end, { desc = "Find visual selection in dotfiles", expr = true })

local function redir_cmd()
  local position_cursor_start = "<HOME>"
  local position_cursor_quote = "<C-Right><C-Right><C-Right><C-Right><Space><C-v><C-j><Left><Left>"
  local remove_marks = "<C-Delete><C-Delete><C-Delete><C-Delete><C-Delete>"
  local expr = ":redir @a | %s redir END | echom getreg('a')%s" -- I put null type (instead of |) just before redir END
  if vim.fn.mode() ~= "n" then
    expr = expr:format("'<,'>", position_cursor_start .. remove_marks .. position_cursor_quote)
  else
    expr = expr:format("", position_cursor_start .. position_cursor_quote)
  end
  return expr
end

vim.keymap.set({ "n", "x" }, "<leader>re", redir_cmd, { desc = "Prepare redir command", expr = true })

vim.keymap.set({ "n", "x" }, "<leader>rm", function()
  vim.cmd("enew | setlocal ft=markdown ff=unix")
  local output = utils.cmd({ "remind-agenda", "--next-all", "--markdown" })
  if not output then return end
  vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(output:gsub("\n$", ""), "\n", { plain = true }))
end, { desc = "Show next reminders" })

vim.keymap.set("t", "<C-q>", function()
  utils.feedkeys("<C-\\><C-n>", "t")
  return "<cmd>close<CR>"
end, { desc = "Close terminal window", expr = true, nowait = true, silent = true })

vim.keymap.set("t", "<C-g>", "<C-\\><C-n><Cmd>stopinsert<CR>", {
  desc = "Exit terminal mode",
  nowait = true,
  silent = true,
})

vim.keymap.set("t", "<A-r>", function() utils.refresh_terminal_window() end, {
  desc = "Refresh terminal window",
  nowait = true,
  silent = true,
})

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

vim.keymap.set(
  "n",
  "<A-j>",
  function() utils.next_qf_item({ center_view = true }) end,
  { desc = "Next quickfix list item" }
)
vim.keymap.set(
  "n",
  "<A-k>",
  function() utils.prev_qf_item({ center_view = true }) end,
  { desc = "Prev quickfix list item" }
)

vim.keymap.set("n", "<leader>tt", function()
  utils.feedkeys("gg")
  local search_pattern = "/^- [ \\] "
  utils.feedkeys(search_pattern .. "<CR>")
  utils.feedkeys(("gg%sn<C-l>"):format(math.random(vim.fn.searchcount().total)))
end, { desc = "Go to buffer's random TODO item" })

vim.keymap.set("n", "<leader>to", function()
  local oldfiles = vim.tbl_filter(function(filename) return utils.file_inside_cwd(filename) end, vim.v.oldfiles)
  vim.ui.select(oldfiles, {
    prompt = "Recent files",
    format_item = function(item) return vim.fn.fnamemodify(item, ":~:.") end,
  }, function(choice) vim.cmd.edit(choice) end)
end, { desc = "List oldfiles for current dir" })

vim.keymap.set("n", "<leader>tb", function()
  local background = vim.api.nvim_get_option_value("background", {})
  vim.api.nvim_set_option_value("background", background == "dark" and "light" or "dark", {})
  vim.cmd.runtime({ "colors/default.lua", bang = true })
end, { desc = "Reload colors/default.lua" })

vim.keymap.set("n", "<A-'>", function()
  local global_marks = constants.global_marks_for_cwd()
  local marks = vim.tbl_filter(
    ---@param item vim.fn.getmarklist.ret.item
    function(item) return not vim.list_contains(constants.NUMBERED_MARKS, item.mark) end,
    vim.fn.getmarklist()
  )
  vim.ui.select(marks, {
    prompt = "Go to mark",
    ---@param item vim.fn.getmarklist.ret.item
    format_item = function(item) return string.format("%s | %s", global_marks[item.mark] or item.mark, item.file) end,
  }, function(choice)
    if not choice then return end
    vim.cmd.normal({ "`" .. choice.mark:sub(2), bang = true })
    vim.cmd.normal({ "zz", bang = true })
    vim.notify(string.format("[marks] go to mark: %s", global_marks[choice.mark] or choice.mark))
  end)
end, { desc = "[marks] Go to custom mark" })

vim.keymap.set("n", "<leader>m'", function()
  local source_win = vim.api.nvim_get_current_win()
  local source_buf = vim.api.nvim_get_current_buf()
  vim.ui.select(vim.fn.getmarklist(source_buf), {
    prompt = "Buffer marks",
    ---@param item vim.fn.getmarklist.ret.item
    format_item = function(item)
      local line = vim.api.nvim_buf_get_lines(source_buf, item.pos[2] - 1, item.pos[2], false)[1] or ""
      return string.format("%s %d:%d | %s", item.mark, item.pos[2], item.pos[3], line)
    end,
  }, function(choice)
    if not choice then return end
    if vim.api.nvim_win_is_valid(source_win) then vim.api.nvim_set_current_win(source_win) end
    if vim.api.nvim_get_current_buf() ~= source_buf and vim.api.nvim_buf_is_valid(source_buf) then
      vim.api.nvim_set_current_buf(source_buf)
    end
    vim.api.nvim_win_set_cursor(0, { choice.pos[2], math.max(choice.pos[3] - 1, 0) })
    vim.cmd.normal({ "zz", bang = true })
    vim.notify(string.format("[marks] go to buffer mark: %s", choice.mark))
  end)
end, { desc = "[marks] Go to buffer mark" })

vim.keymap.set("n", "<A-l>", function()
  local global_marks = constants.global_marks_for_cwd()
  local global_mark_keys = vim.tbl_keys(global_marks)
  table.sort(global_mark_keys)

  vim.ui.select(global_mark_keys, {
    prompt = "Set a mark",
    ---@param item string
    format_item = function(item)
      local has_marks = vim.tbl_count(vim.tbl_filter(
        ---@param mark vim.fn.getmarklist.ret.item
        function(mark) return mark.mark == item end,
        vim.fn.getmarklist()
      )) > 0
      return string.format("%s %s", has_marks and " " or "", global_marks[item] or item)
    end,
  }, function(choice)
    if not choice then return end
    vim.cmd.normal({ "m" .. choice:sub(2), bang = true })
    vim.notify(string.format("[marks] new mark: %s", global_marks[choice] or choice))
  end)
end, { desc = "[marks] set a custom mark" })

vim.keymap.set("n", "'0", function()
  for _, m in ipairs(vim.fn.getmarklist()) do
    if
      vim.list_contains(constants.NUMBERED_MARKS, m.mark)
      and utils.file_inside_cwd(m.file)
      and not utils.cwd_is_home()
    then
      if utils.is_directory(m.file) then
        open_directory_mark_with_overseer(m.file)
        return
      else
        local ok, _ = pcall(vim.cmd.normal, { args = { m.mark }, bang = true }) -- pcall because it randomly fails now...
        if ok then vim.schedule(function() pcall(vim.cmd.normal, { "zz", bang = true }) end) end
        return
      end
    end
  end
  local file = unpack(vim.tbl_filter(function(filename) return utils.file_inside_cwd(filename) end, vim.v.oldfiles))
  if file then vim.cmd.edit(file) end
  vim.api.nvim_echo({ { "No suitable numbered mark, fallback to first oldfile.", "DiagnosticWarn" } }, false, {})
end, { desc = "Go to last edited file or fallback to first oldfile" })

vim.keymap.set("n", "t^", function()
  local prev_tab = vim.fn.tabpagenr("#")
  if prev_tab > 0 then vim.cmd("tabn " .. prev_tab) end
end, { desc = "Toggle between current and previous tab" })

vim.keymap.set("n", "t$", "<cmd>tablast<CR>", { desc = "Go to last tab" })

vim.keymap.set({ "i", "c" }, "<C-f>", function()
  if vim.fn.getcmdpos() > #vim.fn.getcmdline() then
    if vim.fn.mode() == "c" then utils.clear_ui2_ephemeral_messages() end
    return "<C-f>"
  end
  return "<Right>"
end, { desc = "Move cursor right", expr = true })
vim.keymap.set({ "i", "c" }, "<C-b>", "<Left>", { desc = "Move cursor left" })
vim.keymap.set({ "i", "c" }, "<C-a>", "<Home>", { desc = "Move to beginning of line" })
vim.keymap.set({ "i", "c" }, "<C-e>", "<End>", { desc = "Move to end of line" })
vim.keymap.set({ "i", "c" }, "<C-d>", "<Delete>", { desc = "Delete character forward" })
vim.keymap.set({ "i", "c" }, "<A-b>", "<C-Left>", { desc = "Move word backward" })
vim.keymap.set({ "i", "c" }, "<A-f>", "<C-Right>", { desc = "Move word forward" })
vim.keymap.set({ "i", "c" }, "<A-d>", "<C-o>dw", { desc = "Delete word forward" })
vim.keymap.set("i", "<A-u>", "<Esc>bvegUgi", { desc = "Make the word before the cursor uppercase" })

---https://stackoverflow.com/questions/11074440/how-to-iterate-through-the-registers-in-my-vimscript
---@type number[]
local registers_nr = vim.fn.range(vim.fn.char2nr("a"), vim.fn.char2nr("z"))
registers_nr = vim.list_extend(registers_nr, vim.fn.range(vim.fn.char2nr("0"), vim.fn.char2nr("9")))
registers_nr = vim.list_extend(registers_nr, vim.tbl_map(vim.fn.char2nr, { '"', "-", "*", "%", "/", ".", "#", ":" }))
vim.keymap.set({ "n", "c", "i" }, "<A-.>", function()
  local registers = vim.tbl_map(function(item)
    local register = vim.fn.nr2char(item)
    return { name = register, value = vim.fn.getreg(register) }
  end, registers_nr)
  registers = vim.tbl_filter(function(register) return register.value ~= "" end, registers)
  vim.ui.select(registers, {
    prompt = "Registers",
    format_item = function(register) return string.format("%s | %s", register.name, vim.fn.trim(register.value, " ")) end,
  }, function(choice)
    if choice then vim.api.nvim_paste(choice.value, false, -1) end
  end)
end, { desc = "[registers] list and paste selected register" })
