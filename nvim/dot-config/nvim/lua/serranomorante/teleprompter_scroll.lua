local M = {}

local uv = vim.uv or vim.loop
local timer = nil

local state = {
  value = 0,
  accumulator = 0,
  last_seconds = nil,
  win = nil,
  fifo_anchor = nil,
  reader_job = nil,
  cleanup_registered = false,
}

local function number_from_env(name, default, min, max)
  local raw = vim.env[name]
  local value = tonumber(raw)
  if value == nil then return default end
  if min ~= nil and value < min then return min end
  if max ~= nil and value > max then return max end
  return value
end

local options = {
  deadzone = number_from_env("DOTFILES_TELEPROMPTER_DEADZONE", 21, 0, 64),
  interval_ms = number_from_env("DOTFILES_TELEPROMPTER_INTERVAL_MS", 100, 20, 250),
  min_lines_per_second = number_from_env("DOTFILES_TELEPROMPTER_MIN_LPS", 0.55, 0.1, 20),
  max_lines_per_second = number_from_env("DOTFILES_TELEPROMPTER_MAX_LPS", 3.2, 0.1, 20),
  curve = number_from_env("DOTFILES_TELEPROMPTER_CURVE", 1.35, 0.2, 4),
  wrap_width = number_from_env("DOTFILES_TELEPROMPTER_WRAP_WIDTH", nil, 20, 240),
  fifo = vim.env.DOTFILES_TELEPROMPTER_SCROLL_FIFO
    or ((vim.env.XDG_RUNTIME_DIR or "/tmp") .. "/dotfiles-teleprompter-scroll.fifo"),
}

local function clamp_midi_value(value)
  value = tonumber(value) or 0
  if value < 0 then return 0 end
  if value > 127 then return 127 end
  return math.floor(value + 0.5)
end

local function valid_window(win) return type(win) == "number" and vim.api.nvim_win_is_valid(win) end

local function teleprompter_window()
  if valid_window(state.win) then return state.win end
  state.win = vim.api.nvim_get_current_win()
  return state.win
end

local function set_midi_value(value)
  state.value = clamp_midi_value(value)
  vim.g.teleprompter_scroll_value = state.value
end

local function display_width(text) return vim.fn.strdisplaywidth(text) end

local function chars_for_text(text) return vim.fn.split(text, "\\zs") end

local function char_is_space(char) return char:match("%s") ~= nil end

local function line_from_chars(chars, first, last)
  if last < first then return "" end

  local parts = {}
  for index = first, last do
    parts[#parts + 1] = chars[index]
  end
  return table.concat(parts):gsub("%s+$", "")
end

local function trim_leading_space(chars)
  while #chars > 0 and char_is_space(chars[1]) do
    table.remove(chars, 1)
  end
end

local function last_space_index(chars)
  for index = #chars, 1, -1 do
    if char_is_space(chars[index]) then return index end
  end
  return nil
end

local function wrapped_line_chunks(line, width)
  if line == "" then return { "" } end

  local chunks = {}
  local current = {}
  for _, char in ipairs(chars_for_text(line)) do
    current[#current + 1] = char

    if display_width(table.concat(current)) > width and #current > 1 then
      local break_at = last_space_index(current)
      if break_at == nil or break_at <= 1 then break_at = #current - 1 end

      chunks[#chunks + 1] = line_from_chars(current, 1, break_at)

      local next_current = {}
      for index = break_at + 1, #current do
        next_current[#next_current + 1] = current[index]
      end
      trim_leading_space(next_current)
      current = next_current
    end
  end

  if #current > 0 then chunks[#chunks + 1] = line_from_chars(current, 1, #current) end

  return chunks
end

local function wrap_width_for_window(win)
  if options.wrap_width ~= nil then return options.wrap_width end

  local ok, win_width = pcall(vim.api.nvim_win_get_width, win)
  if not ok then win_width = vim.o.columns end
  return math.max(20, win_width - 6)
end

local function build_wrapped_lines(lines, width)
  local wrapped = {}
  for _, line in ipairs(lines) do
    for _, chunk in ipairs(wrapped_line_chunks(line, width)) do
      wrapped[#wrapped + 1] = chunk
    end
  end

  if #wrapped == 0 then wrapped[1] = "" end
  return wrapped
end

local function prepare_scratch_buffer(win)
  if not valid_window(win) then return end

  local source_buf = vim.api.nvim_win_get_buf(win)
  if vim.b[source_buf].teleprompter_scratch == true then return end

  local source_lines = vim.api.nvim_buf_get_lines(source_buf, 0, -1, false)
  local scratch_buf = vim.api.nvim_create_buf(false, true)
  local wrapped_lines = build_wrapped_lines(source_lines, wrap_width_for_window(win))

  vim.bo[scratch_buf].buftype = "nofile"
  vim.bo[scratch_buf].bufhidden = "wipe"
  vim.bo[scratch_buf].swapfile = false
  vim.bo[scratch_buf].filetype = vim.bo[source_buf].filetype
  vim.b[scratch_buf].teleprompter_scratch = true
  vim.b[scratch_buf].teleprompter_source_name = vim.api.nvim_buf_get_name(source_buf)

  vim.api.nvim_buf_set_lines(scratch_buf, 0, -1, false, wrapped_lines)
  vim.bo[scratch_buf].modifiable = false
  vim.bo[scratch_buf].readonly = true
  vim.api.nvim_win_set_buf(win, scratch_buf)
end

local function speed_for_value(value)
  value = clamp_midi_value(value)
  if value <= options.deadzone then return 0 end

  local normalized = (value - options.deadzone) / (127 - options.deadzone)
  normalized = math.max(0, math.min(1, normalized))
  return options.min_lines_per_second
    + (options.max_lines_per_second - options.min_lines_per_second) * (normalized ^ options.curve)
end

local function configure_ui()
  vim.o.showtabline = 0
  vim.o.laststatus = 0
  vim.o.cmdheight = 0
  vim.o.ruler = false
  vim.o.showcmd = false
  vim.o.showmode = false
end

local function configure_window(win)
  if not valid_window(win) then return end

  vim.wo[win].number = true
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].cursorline = false
  vim.wo[win].wrap = false
  vim.wo[win].linebreak = false
  vim.wo[win].scrolloff = 0
end

local function handle_fifo_line(line)
  local value = line and line:match("^(%d+)")
  if value == nil then return end
  set_midi_value(value)
end

local function cleanup_fifo()
  if state.reader_job ~= nil then
    vim.fn.jobstop(state.reader_job)
    state.reader_job = nil
  end
  if state.fifo_anchor ~= nil then
    uv.fs_close(state.fifo_anchor)
    state.fifo_anchor = nil
  end
  if vim.fn.getftype(options.fifo) == "fifo" then vim.fn.delete(options.fifo) end
end

local function ensure_fifo()
  local dir = vim.fn.fnamemodify(options.fifo, ":h")
  vim.fn.mkdir(dir, "p")

  local filetype = vim.fn.getftype(options.fifo)
  if filetype ~= "" and filetype ~= "fifo" then
    vim.fn.delete(options.fifo)
    filetype = ""
  end
  if filetype ~= "fifo" then
    local result = vim.fn.system({ "mkfifo", options.fifo })
    if vim.v.shell_error ~= 0 then
      vim.notify(("teleprompter: could not create FIFO %s: %s"):format(options.fifo, result), vim.log.levels.ERROR)
      return false
    end
  end

  if state.fifo_anchor == nil then
    local fd, err = uv.fs_open(options.fifo, "r+", 438)
    if fd == nil then
      vim.notify(
        ("teleprompter: could not open FIFO %s: %s"):format(options.fifo, err or "unknown error"),
        vim.log.levels.ERROR
      )
      return false
    end
    state.fifo_anchor = fd
  end

  if not state.cleanup_registered then
    state.cleanup_registered = true
    vim.api.nvim_create_autocmd("VimLeavePre", {
      group = vim.api.nvim_create_augroup("teleprompter_scroll_fifo", { clear = true }),
      callback = cleanup_fifo,
    })
  end

  return true
end

local function ensure_reader()
  if state.reader_job ~= nil then return end
  if not ensure_fifo() then return end

  state.reader_job = vim.fn.jobstart({ "cat", options.fifo }, {
    stdout_buffered = false,
    on_stdout = function(_, data, _)
      for _, line in ipairs(data or {}) do
        if line ~= "" then handle_fifo_line(line) end
      end
    end,
    on_exit = function() state.reader_job = nil end,
  })

  if state.reader_job <= 0 then
    vim.notify(("teleprompter: could not read FIFO %s"):format(options.fifo), vim.log.levels.ERROR)
    state.reader_job = nil
  end
end

local function scroll_lines(count)
  if count <= 0 then return end

  local win = teleprompter_window()
  if not valid_window(win) then return end

  local keys = vim.api.nvim_replace_termcodes("<C-E>", true, false, true)
  vim.api.nvim_win_call(win, function() vim.api.nvim_command("normal! " .. math.min(count, 8) .. keys) end)
end

local function tick()
  ensure_reader()

  local now = uv.hrtime() / 1000000000
  local last = state.last_seconds
  state.last_seconds = now

  if last == nil then return end

  local lines_per_second = speed_for_value(state.value)
  if lines_per_second <= 0 then
    state.accumulator = 0
    return
  end

  state.accumulator = state.accumulator + lines_per_second * (now - last)
  local lines = math.floor(state.accumulator)
  if lines <= 0 then return end

  state.accumulator = state.accumulator - lines
  scroll_lines(lines)
end

local function ensure_timer()
  if timer ~= nil then return end

  timer = uv.new_timer()
  timer:start(options.interval_ms, options.interval_ms, vim.schedule_wrap(tick))
end

function M.set_midi_value(value)
  set_midi_value(value)
  ensure_reader()
  ensure_timer()
  return state.value
end

function M.start()
  state.win = vim.api.nvim_get_current_win()
  state.accumulator = 0
  set_midi_value(0)
  prepare_scratch_buffer(state.win)
  configure_ui()
  configure_window(state.win)
  ensure_reader()
  ensure_timer()
end

function M.refresh()
  ensure_reader()
  return state.value
end

function M.stop()
  set_midi_value(0)
  state.accumulator = 0
end

return M
