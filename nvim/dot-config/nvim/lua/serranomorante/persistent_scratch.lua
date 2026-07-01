local utils = require("serranomorante.utils")

local M = {}

local AUGROUP = vim.api.nvim_create_augroup("persistent_scratch", { clear = true })
local COLOR_GROUP = vim.api.nvim_create_augroup("persistent_scratch_colors", { clear = true })
local entries_by_cwd = {}
local SCRATCH_TITLE = "Scratch buffer"
local SCRATCH_EOB_HL = "PersistentScratchEndOfBuffer"
local PADDING_NS = vim.api.nvim_create_namespace("persistent_scratch_padding")
local WINDOW_PADDING = { top = 0, bottom = 0 }

local function current_cwd() return vim.fn.getcwd() end
local function current_tabpage() return vim.api.nvim_get_current_tabpage() end

local function scratch_path(cwd)
  local scratch_dir = utils.join_paths(vim.fn.stdpath("state"), "persistent-scratch")
  return utils.join_paths(scratch_dir, utils.local_state_cwd_key(cwd) .. ".md")
end

local function ensure_parent_dir(path) vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p") end

local function is_float_window(winid)
  if not vim.api.nvim_win_is_valid(winid) then return false end
  local relative = vim.api.nvim_win_get_config(winid).relative or ""
  return relative ~= ""
end

local function tab_key(tabid) return tostring(tabid) end

local function tab_regular_win(tabid, preferred_win)
  tabid = tabid or current_tabpage()
  if
    preferred_win
    and vim.api.nvim_win_is_valid(preferred_win)
    and vim.api.nvim_win_get_tabpage(preferred_win) == tabid
    and not is_float_window(preferred_win)
  then
    return preferred_win
  end

  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(tabid)) do
    if not is_float_window(winid) then return winid end
  end
end

local function centered_float_config()
  local columns = vim.o.columns
  local lines = vim.o.lines
  local width = math.max(60, math.floor(columns * 0.72))
  local height = math.max(12, math.floor(lines * 0.72))
  width = math.min(width, math.max(20, columns - 8))
  height = math.min(height, math.max(5, lines - 6))

  return {
    relative = "editor",
    row = math.floor((lines - height) / 2 - 1),
    col = math.floor((columns - width) / 2),
    width = width,
    height = height,
    border = "rounded",
  }
end

local function with_fillchar(value, spec)
  if value == "" then return spec end
  local key = spec:match("^([^:]+):")
  if not key then return value end
  local pattern = key .. ":[^,]*"
  if value:find(pattern) then return value:gsub(pattern, spec) end
  return value .. "," .. spec
end

local function define_scratch_end_of_buffer_hl() vim.api.nvim_set_hl(0, SCRATCH_EOB_HL, { fg = "#8be9fd", bold = true }) end

local function blank_virt_lines(height)
  local lines = {}
  for _ = 1, height do
    table.insert(lines, { { " ", "NormalFloat" } })
  end
  return lines
end

local function refresh_padding(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then return end

  vim.api.nvim_buf_clear_namespace(bufnr, PADDING_NS, 0, -1)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  if line_count == 0 then return end

  if WINDOW_PADDING.bottom > 0 then
    vim.api.nvim_buf_set_extmark(bufnr, PADDING_NS, line_count - 1, 0, {
      virt_lines = blank_virt_lines(WINDOW_PADDING.bottom),
      virt_lines_above = false,
      virt_lines_leftcol = false,
    })
  end
end

local function leading_padding_lines(lines)
  local padding = {}
  for i = 1, math.min(WINDOW_PADDING.top, #lines) do
    padding[#padding + 1] = lines[i]
  end
  return padding
end

local function content_after_leading_padding(lines)
  local content = {}
  for i = WINDOW_PADDING.top + 1, #lines do
    content[#content + 1] = lines[i]
  end
  return content
end

local function save_entry(entry, winid)
  if not entry.bufnr or not vim.api.nvim_buf_is_valid(entry.bufnr) then return end
  ensure_parent_dir(entry.path)
  if not vim.bo[entry.bufnr].modified then return end

  if winid and vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) == entry.bufnr then
    pcall(function()
      vim.api.nvim_win_call(winid, function() vim.cmd("silent! noautocmd write!") end)
    end)
    return
  end

  if vim.api.nvim_get_current_buf() == entry.bufnr then
    pcall(function() vim.cmd("silent! noautocmd write!") end)
  end
end

local function normalize_trailing_blank_lines(lines)
  while #lines > 0 and lines[#lines] == "" do
    table.remove(lines)
  end
  return lines
end

local function append_lines_to_entry(entry, lines)
  if type(lines) ~= "table" or #lines == 0 then return false end

  local inserted_line = nil
  if not entry.bufnr or not vim.api.nvim_buf_is_valid(entry.bufnr) then create_buffer(entry) end
  if not entry.bufnr or not vim.api.nvim_buf_is_valid(entry.bufnr) then return false end

  local bufnr = entry.bufnr
  local current_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local padding_lines = leading_padding_lines(current_lines)
  local existing_lines = normalize_trailing_blank_lines(content_after_leading_padding(current_lines))
  if #existing_lines == 1 and existing_lines[1] == "" then existing_lines = {} end

  local inserted_lines = vim.deepcopy(lines)
  if #existing_lines > 0 then table.insert(inserted_lines, 1, "") end

  local new_lines = vim.deepcopy(padding_lines)
  vim.list_extend(new_lines, existing_lines)
  if #existing_lines > 0 then table.insert(new_lines, "") end
  vim.list_extend(new_lines, lines)
  inserted_line = #padding_lines + #existing_lines + (#existing_lines > 0 and 2 or 1)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)
  save_entry(entry)
  return true, inserted_line
end

local function entry_state_for_tab(entry, tabid, create)
  entry.tabs = entry.tabs or {}
  local key = tab_key(tabid)
  local state = entry.tabs[key]
  if state and state.winid and not vim.api.nvim_win_is_valid(state.winid) then state.winid = nil end
  if not state and create then
    state = {}
    entry.tabs[key] = state
  end
  return state
end

local function current_tab_state(entry, create) return entry_state_for_tab(entry, current_tabpage(), create) end

local function remember_state_view(state)
  if not state or not state.winid or not vim.api.nvim_win_is_valid(state.winid) then return end
  pcall(function()
    vim.api.nvim_win_call(state.winid, function() state.view = vim.fn.winsaveview() end)
  end)
end

local function hide_state(state)
  if not state or not state.winid or not vim.api.nvim_win_is_valid(state.winid) then return end
  local config = vim.api.nvim_win_get_config(state.winid)
  if config.hide then return end

  remember_state_view(state)
  config.hide = true
  pcall(vim.api.nvim_win_set_config, state.winid, config)
  state.hidden = true
end

local function restore_state_view(winid, state)
  if not state or not state.view then return end
  pcall(function()
    vim.api.nvim_win_call(winid, function() vim.fn.winrestview(state.view) end)
  end)
end

local function register_buffer_autocmds(entry)
  local bufnr = entry.bufnr
  local buffer_group = vim.api.nvim_create_augroup(("persistent_scratch_%d"):format(bufnr), { clear = true })
  vim.api.nvim_create_autocmd({ "BufLeave", "WinLeave", "BufHidden", "TextChanged", "TextChangedI" }, {
    desc = "Persist scratch buffer content",
    group = buffer_group,
    buffer = bufnr,
    callback = function() save_entry(entry, vim.api.nvim_get_current_win()) end,
  })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    desc = "Refresh scratch padding",
    group = buffer_group,
    buffer = bufnr,
    callback = function() refresh_padding(bufnr) end,
  })
end

local function create_buffer(entry)
  ensure_parent_dir(entry.path)
  local bufnr = vim.fn.bufadd(entry.path)
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].buflisted = false
  vim.bo[bufnr].swapfile = false
  -- Keep undo persistence on for scratch files even when broader cwd-scoped
  -- local state is disabled.
  vim.bo[bufnr].undofile = true
  vim.b[bufnr].persistent_scratch = true
  vim.b[bufnr].persistent_scratch_disable_lsp = true
  pcall(vim.fn.bufload, bufnr)
  vim.bo[bufnr].filetype = "markdown"
  vim.bo[bufnr].modifiable = true
  vim.bo[bufnr].readonly = false
  vim.bo[bufnr].modified = false

  refresh_padding(bufnr)
  entry.bufnr = bufnr
  register_buffer_autocmds(entry)
  return bufnr
end

local function leave_visual_mode()
  local mode = vim.fn.mode()
  if not vim.list_contains({ "v", "V", "\22" }, mode) then return end
  vim.cmd("normal! \27")
end

local function current_visual_selection_lines()
  local mode = vim.fn.mode()
  if not vim.list_contains({ "v", "V", "\22" }, mode) then return nil end

  local start_pos = vim.fn.getpos("v")
  local end_pos = vim.fn.getpos(".")
  if start_pos[2] == 0 or end_pos[2] == 0 then return nil end

  local lines = vim.fn.getregion(start_pos, end_pos, { type = mode })
  if #lines == 0 then return nil end
  return lines
end

local function apply_window_options(winid)
  define_scratch_end_of_buffer_hl()
  vim.wo[winid].number = false
  vim.wo[winid].relativenumber = false
  vim.wo[winid].signcolumn = "yes:1"
  vim.wo[winid].foldcolumn = "1"
  vim.wo[winid].wrap = true
  vim.wo[winid].linebreak = true
  vim.wo[winid].list = true
  vim.wo[winid].fillchars = with_fillchar(vim.wo[winid].fillchars, "eob:~")
  vim.wo[winid].conceallevel = 0
  vim.wo[winid].concealcursor = ""
  vim.wo[winid].winfixbuf = true
  vim.wo[winid].winhighlight = ("Normal:NormalFloat,NormalFloat:NormalFloat,FloatBorder:FloatBorder,SignColumn:NormalFloat,FoldColumn:NormalFloat,EndOfBuffer:%s"):format(
    SCRATCH_EOB_HL
  )
end

local function hide_entry(entry)
  local state = current_tab_state(entry)
  if not state or not state.winid or not vim.api.nvim_win_is_valid(state.winid) then return end

  local current_winid = vim.api.nvim_get_current_win()
  local tabid = current_tabpage()
  if current_winid == state.winid then
    state.previous_winid = tab_regular_win(tabid, state.previous_winid) or tab_regular_win(tabid)
  end

  save_entry(entry, state.winid)
  hide_state(state)

  if current_winid == state.winid then
    local target = tab_regular_win(tabid, state.previous_winid) or tab_regular_win(tabid)
    if target then pcall(vim.api.nvim_set_current_win, target) end
  end
end

local function find_state_by_winid(winid)
  for _, entry in pairs(entries_by_cwd) do
    for tabid, state in pairs(entry.tabs or {}) do
      if state.winid == winid then return entry, state, tabid end
    end
  end
end

local function cleanup_state_for_window(winid)
  local entry, state = find_state_by_winid(winid)
  if not entry or not state then return end
  remember_state_view(state)
  state.winid = nil
  state.hidden = false
end

local function save_visible_scratch_views()
  for _, entry in pairs(entries_by_cwd) do
    for _, state in pairs(entry.tabs or {}) do
      remember_state_view(state)
      save_entry(entry, state.winid)
    end
  end
end

local function create_window(entry, state)
  if not entry.bufnr or not vim.api.nvim_buf_is_valid(entry.bufnr) then create_buffer(entry) end
  local tabid = current_tabpage()
  state = state or current_tab_state(entry, true)
  state.previous_winid = tab_regular_win(tabid, state.previous_winid) or tab_regular_win(tabid) or state.previous_winid

  refresh_padding(entry.bufnr)
  local config = centered_float_config()
  config.title = SCRATCH_TITLE
  config.title_pos = "center"
  local winid = vim.api.nvim_open_win(entry.bufnr, true, config)
  state.winid = winid
  state.hidden = false
  apply_window_options(winid)
  restore_state_view(winid, state)
  if not state.view then pcall(vim.api.nvim_win_set_cursor, winid, { WINDOW_PADDING.top + 1, 0 }) end
end

local function hide_other_tab_states(entry, current_tabid)
  for tabid_key, state in pairs(entry.tabs or {}) do
    local tabid = tonumber(tabid_key)
    if tabid and tabid ~= current_tabid then hide_state(state) end
  end
end

local function show_entry(entry)
  local tabid = current_tabpage()
  hide_other_tab_states(entry, tabid)

  local state = current_tab_state(entry, true)
  if state.winid and vim.api.nvim_win_is_valid(state.winid) then
    apply_window_options(state.winid)
    refresh_padding(vim.api.nvim_win_get_buf(state.winid))
    if not vim.api.nvim_win_get_config(state.winid).hide then
      vim.api.nvim_set_current_win(state.winid)
      return
    end

    local config = centered_float_config()
    config.hide = false
    config.title = SCRATCH_TITLE
    config.title_pos = "center"
    refresh_padding(vim.api.nvim_win_get_buf(state.winid))
    vim.api.nvim_win_set_config(state.winid, config)
    apply_window_options(state.winid)
    vim.api.nvim_set_current_win(state.winid)
    restore_state_view(state.winid, state)
    if not state.view then pcall(vim.api.nvim_win_set_cursor, state.winid, { WINDOW_PADDING.top + 1, 0 }) end
    state.hidden = false
    return
  end

  create_window(entry, state)
end

local function entry_for_cwd(cwd)
  cwd = cwd or current_cwd()
  local entry = entries_by_cwd[cwd]
  if entry then return entry end

  entry = {
    cwd = cwd,
    path = scratch_path(cwd),
  }
  entries_by_cwd[cwd] = entry
  return entry
end

function M.toggle()
  local entry = entry_for_cwd(current_cwd())
  local state = current_tab_state(entry)
  if
    state
    and state.winid
    and vim.api.nvim_win_is_valid(state.winid)
    and not vim.api.nvim_win_get_config(state.winid).hide
  then
    hide_entry(entry)
    return
  end

  show_entry(entry)
end

---@param entry? table
local function focus_entry(entry)
  entry = entry or entry_for_cwd(current_cwd())
  show_entry(entry)
end

---@param lines string[]
---@return boolean
function M.append_lines(lines)
  local entry = entry_for_cwd(current_cwd())
  return append_lines_to_entry(entry, lines)
end

---@return boolean
function M.append_visual_selection()
  local lines = current_visual_selection_lines()
  if not lines then return false end

  leave_visual_mode()
  local entry = entry_for_cwd(current_cwd())
  local ok, inserted_line = append_lines_to_entry(entry, lines)
  if not ok then return false end

  focus_entry(entry)
  if inserted_line and entry.bufnr and vim.api.nvim_buf_is_valid(entry.bufnr) then
    local winid = vim.api.nvim_get_current_win()
    if vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) == entry.bufnr then
      pcall(vim.api.nvim_win_set_cursor, winid, { inserted_line, 0 })
    end
  end
  return true
end

function M.setup()
  define_scratch_end_of_buffer_hl()

  vim.api.nvim_create_autocmd("ColorScheme", {
    desc = "Restore scratch highlight groups after colorscheme reloads",
    group = COLOR_GROUP,
    callback = function()
      define_scratch_end_of_buffer_hl()
      vim.schedule(function() vim.cmd.redraw() end)
    end,
  })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    desc = "Persist scratch buffers on exit",
    group = AUGROUP,
    callback = save_visible_scratch_views,
  })

  vim.api.nvim_create_autocmd("FocusLost", {
    desc = "Persist scratch buffers when Neovim loses focus",
    group = AUGROUP,
    callback = save_visible_scratch_views,
  })

  vim.api.nvim_create_autocmd("WinClosed", {
    desc = "Persist scratch buffers when their window closes",
    group = AUGROUP,
    callback = function(args)
      local closed_winid = tonumber(args.match)
      if not closed_winid then return end

      cleanup_state_for_window(closed_winid)
    end,
  })
end

return M
