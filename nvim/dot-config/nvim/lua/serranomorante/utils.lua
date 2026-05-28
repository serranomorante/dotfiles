local constants = require("serranomorante.constants")
local tools = require("serranomorante.tools")

local M = {}

---Writes a Grep/Find command into vim's command-line with
---nnn's hovered dir prepopulated
---@param search_type 'Grep'|'Find'
---@param filepath string
function M.nnn_search_in_dir(search_type, filepath)
  local search_dir = vim.fn.fnamemodify(filepath or "", ":p:~:h")
  if not M.is_directory(vim.fn.expand(search_dir)) then
    local msg = '[NNN] %s search aborted. Directory "%s" not found'
    return vim.api.nvim_echo({ { msg:format(search_type, search_dir) } }, false, { err = true })
  end
  ---Wait until terminal closes
  vim.defer_fn(function()
    M.feedkeys(string.format(":%s '' %s", search_type, search_dir), "n")
    M.feedkeys(constants.POSITION_CURSOR_BETWEEN_QUOTES, "n")
  end, 200)
end

---Check if a plugin has been loaded
---@param plugin string # The name of the plugin. It should be the same as the one you use in `require(plugin name)`
---@return boolean available # Whether the plugin is available
function M.is_available(plugin) return package.loaded[plugin] ~= nil end

function M.clear_ui2_ephemeral_messages()
  local ok_ui2, ui2 = pcall(require, "vim._core.ui2")
  if not ok_ui2 then return end

  if ui2.msg and ui2.msg.msg and type(ui2.msg.msg.clear) == "function" then
    pcall(function() ui2.msg.msg:clear() end)
  end

  local msg_win = ui2.wins and ui2.wins.msg
  if msg_win and vim.api.nvim_win_is_valid(msg_win) then
    pcall(vim.api.nvim_win_set_config, msg_win, { hide = true })
  end

  local msg_buf = ui2.bufs and ui2.bufs.msg
  if msg_buf and vim.api.nvim_buf_is_valid(msg_buf) then
    pcall(vim.api.nvim_buf_set_lines, msg_buf, 0, -1, false, {})
  end
end

---Get the installation path of a plugin
---@param plugin string
---@return string Empty if path doesn't exists
function M.installation_path(plugin) return vim.fn.finddir(plugin, vim.fn.stdpath("data") .. "/site/pack/plugins/*/") end

--- Call function if a condition is met
---@param func function # The function to run
---@param condition boolean # Wether to run the function or not
---@return any|nil result # The result of the function running or nil
function M.conditional_func(func, condition, ...)
  if condition and type(func) == "function" then return func(...) end
end

--- Checks whether a given path exists and is a directory
--- Thanks LunarVim!
--@param path (string) path to check
--@returns (bool)
function M.is_directory(path)
  local stat = (vim.uv or vim.loop).fs_stat(path)
  return stat and stat.type == "directory" or false
end

local path_sep = (vim.uv or vim.loop).os_uname().version:match("Windows") and "\\" or "/"

---Join path segments that were passed as input
---Thanks LunarVim!
---@param ... string
---@return string
function M.join_paths(...)
  local result = table.concat({ ... }, path_sep)
  return result
end

local function lua_pattern_escape(value) return (value:gsub("([^%w])", "%%%1")) end

---@param servername? string
---@return boolean
function M.is_kitty_cwd_servername(servername)
  servername = servername or vim.v.servername
  if servername == "" then return false end

  local runtime_root = (vim.env.XDG_RUNTIME_DIR or M.join_paths(vim.env.HOME, ".cache", "nvim")):gsub("/+$", "")
  return servername:match("^" .. lua_pattern_escape(runtime_root) .. "/kitty%-cwd%-[A-Za-z0-9._-]+%.nvim%.sock$") ~= nil
end

---@return boolean
function M.should_persist_local_state() return M.is_kitty_cwd_servername(vim.v.servername) end

--- Run a shell command and capture the output and if the command succeeded or failed
---
---@param cmd string|string[] The terminal command to execute
---@param show_error? boolean Whether or not to show an unsuccessful command as an error to the user
---@return string|nil # The result of a successfully executed command or nil
function M.cmd(cmd, show_error)
  if type(cmd) == "string" then cmd = { cmd } end
  if vim.fn.has("win32") == 1 then cmd = vim.list_extend({ "cmd.exe", "/C" }, cmd) end
  local result = vim.fn.system(cmd)
  local success = vim.api.nvim_get_vvar("shell_error") == 0
  if not success and (show_error == nil or show_error) then
    local msg = "Error running command %s\nError message:\n%s"
    vim.api.nvim_echo({ { msg:format(table.concat(cmd, " "), result) } }, false, { err = true })
  end
  return success and result:gsub("[\27\155][][()#;?%d]*[A-PRZcf-ntqry=><~]", "") or nil
end

function M.bool2str(bool) return bool and "on" or "off" end

--- Helper function to check if any active LSP clients given a filter provide a specific capability
---@param capability string The server capability to check for (example: "documentFormattingProvider")
---@param filter vim.lsp.get_clients.Filter|nil (table|nil) A table with
---              key-value pairs used to filter the returned clients.
---              The available keys are:
---               - id (number): Only return clients with the given id
---               - bufnr (number): Only return clients attached to this buffer
---               - name (string): Only return clients with the given name
---@return boolean # Whether or not any of the clients provide the capability
function M.has_capability(capability, filter)
  for _, client in pairs(vim.lsp.get_clients(filter)) do
    if client:supports_method(capability) then return true end
  end
  return false
end

function M.del_buffer_autocmd(augroup, bufnr)
  local cmds_found, cmds = pcall(vim.api.nvim_get_autocmds, { group = augroup, buffer = bufnr })
  if cmds_found then vim.tbl_map(function(cmd) vim.api.nvim_del_autocmd(cmd.id) end, cmds) end
end

---@alias GeneralToolType "fmts"|"lsp"|"linters"|"dap"|"extra"
---@alias TreesitterToolType "parsers"
---@alias ToolEnsureInstall table<GeneralToolType|TreesitterToolType, string[]>

---Merges an array of `ToolEnsureInstall` specs into 1 flat array of strings
---@param installer_type? "general"|"treesitter" Default is "general"
---@param ... ToolEnsureInstall
---@return string[] # A flat array of tools without duplicates
function M.merge_tools(installer_type, ...)
  installer_type = installer_type or "general"
  local general_tool_type = { "fmts", "lsp", "linters", "dap", "extra" }
  local treesitter_tool_type = { "parsers" }
  local tool_type_by_installer = {
    ["general"] = general_tool_type,
    ["treesitter"] = treesitter_tool_type,
  }
  local merge_result = {}
  for _, tools_table in pairs({ ... }) do
    for _, tool_type in ipairs(tool_type_by_installer[installer_type]) do
      for _, tool in ipairs(tools_table[tool_type] or {}) do
        if not vim.list_contains(merge_result, tool) then table.insert(merge_result, tool) end
      end
    end
  end
  return merge_result
end

---Check if file belongs to a cwd
---@param filename string
---@param cwd string? Uses current if no cwd is passed
---@return boolean
function M.file_inside_cwd(filename, cwd)
  local dir = cwd or vim.fn.getcwd()
  dir = dir:sub(-1) ~= "/" and dir .. "/" or dir
  return vim.startswith(filename, dir) and M.exists(filename)
end

---Get the indent char string for a given shiftwidth
---@param shiftwidth number
local function indent_char(shiftwidth) return "▏" .. string.rep(" ", shiftwidth > 0 and shiftwidth - 1 or 0) end

---Update indent line string with the current shiftwidth
---@param old string old listchars
---@param shiftwidth number current shiftwidth
function M.update_indent_line(old, shiftwidth)
  return old:gsub("leadmultispace:[^,]*", "leadmultispace:" .. indent_char(shiftwidth))
end

---Update indent line for the current buffer
---https://github.com/gravndal/shiftwidth_leadmultispace.nvim/blob/master/plugin/shiftwidth_leadmultispace.lua
function M.update_indent_line_curbuf(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(winid) == bufnr then
      vim.wo[winid].listchars = M.update_indent_line(vim.wo[winid].listchars, vim.bo[bufnr].shiftwidth)
    end
  end
end

---https://github.com/mfussenegger/dotfiles/blob/9a96db7fdcda87b0036c587282de5e0882317a8a/vim/.config/nvim/init.lua#L20
---@param keys string
---@param mode? string
function M.feedkeys(keys, mode)
  mode = mode or "n"
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), mode, true)
end

---Enhances neovim's native commentstring
---Thanks: https://github.com/folke/ts-comments.nvim
---@param opts table?
function M.hijack_commentstring_get_option(opts)
  opts = opts or constants.commentstring_setup
  local get_option = vim.filetype.get_option
  return function(filetype, option)
    if option ~= "commentstring" then return get_option(filetype, option) end
    local lang = vim.treesitter.language.get_lang(filetype) or filetype

    local ret = opts.lang[lang]
    if type(ret) == "table" then
      local ok, node = pcall(vim.treesitter.get_node, { ignore_injections = false })
      while ok and node do
        if ret[node:type()] then
          ret = ret[node:type()]
          break
        end
        node = node:parent()
      end
      if type(ret) == "table" then ret = ret._ end
    end
    return ret or get_option(filetype, option)
  end
end

---Refresh codelens
---@param args any
function M.refresh_codelens(args)
  local buf = args and args.buf or vim.api.nvim_get_current_buf()
  if not M.has_capability("textDocument/codeLens", { bufnr = buf }) then
    M.del_buffer_autocmd("lsp_codelens_augroup", buf)
    return
  end
  if vim.g.codelens_enabled then vim.lsp.codelens.enable(true, { bufnr = buf }) end
end

---Simple setTimeout wrapper
---@param callback function
---@param ms integer
function M.set_timeout(callback, ms)
  local timer = vim.uv.new_timer()
  if timer == nil then return end
  timer:start(ms, 0, function()
    timer:stop()
    timer:close()
    callback()
  end)
  return timer
end

---Extracted from nvim-ufo
---@param ms number
---@return Promise
function M.wait(ms)
  return require("promise")(function(resolve)
    local timer = vim.uv.new_timer()
    assert(timer)
    timer:start(ms, 0, function()
      timer:close()
      resolve()
    end)
  end)
end

---Wait until callback returns true or timeout
---@param callback fun(): Promise
---@param ms number
---@return Promise
function M.wait_until(callback, ms)
  return require("async")(function()
    local timeout = false
    M.set_timeout(function() timeout = true end, ms)
    ---@type boolean|nil
    local result
    while result ~= true and timeout == false do
      result = await(callback())
      await(M.wait(350))
    end
    local promise = require("promise")
    if timeout == false and result == true then
      return promise.resolve(result)
    elseif timeout == true then
      return promise.reject("Timeout reached")
    else
      return promise.reject("Unknown error")
    end
  end)
end

---Return an adapted filename which includes cursor's current line and column
function M.get_cursor_position()
  local bufname = vim.api.nvim_buf_get_name(0)
  local line, col = unpack(vim.api.nvim_win_get_cursor(0))
  return bufname, line, col
end

local function rg_command(search, opts)
  local grep_cmd = "rg -e " .. search:gsub("\\'", "\\x27") -- escape single quotes
  if opts.json then grep_cmd = string.format("%s %s", grep_cmd, "--json") end
  return grep_cmd
end

---Grep with ripgrep
---@param search string
---@param opts table?
---@return string|RGContent[]|number
function M.grep_with_rg(search, opts)
  opts = opts or {}
  if search == "''" then
    vim.api.nvim_echo({ { "Empty search pattern" } }, false, { err = true })
    return {}
  end
  local grep_cmd = rg_command(search, opts)
  local content = vim.fn.join(vim.fn.systemlist(grep_cmd), ",")
  if vim.api.nvim_get_vvar("shell_error") > 0 then
    vim.api.nvim_echo({ { content } }, false, { err = true })
    return {}
  end
  if opts.json then return vim.json.decode(string.format("[%s]", content), { luanil = { object = true } }) end
  return content
end

local function echo_no_more_items() vim.api.nvim_echo({ { "No more items", "DiagnosticWarn" } }, false, {}) end

---@class TmuxWrapperOpts
---@field cwd? string
---@field detach? boolean By default we attach to the session
---@field session_name? string
---@field include_binary? boolean Include `tmux` as part of the args?
---@field retain_shell? boolean Enter an interactive shell after command finishes?
---@field wait_for? string Block until command finishes?

---@param cmd table|string
---@param opts? TmuxWrapperOpts
---@return string|table
function M.wrap_overseer_args_with_tmux(cmd, opts)
  opts = opts or {}
  local cmd_is_shell = type(cmd) == "string"
  if cmd_is_shell then cmd = { cmd } end
  local args = {
    "-L", -- use different tmux server for overseer tasks
    "overseer",
    "-f", -- use tmux config that disables statusbar
    vim.env.HOME .. "/.config/tmux/tmuxnvim.conf",
    "new-session",
  }
  table.insert(args, opts.detach and "-d" or "-A")
  if opts.include_binary then table.insert(args, 1, "tmux") end
  if opts.cwd then vim.list_extend(args, { "-c", M.wrap_in_single_quotes(opts.cwd) }) end
  if opts.session_name then
    vim.list_extend(args, { "-s", M.wrap_in_single_quotes(opts.session_name .. vim.fn.fnameescape(vim.v.servername)) })
  end
  ---Delimite the command part (and add wait-for if required)
  table.insert(args, '"')
  vim.list_extend(args, cmd --[[@as table]])
  if opts.retain_shell then vim.list_extend(args, { ";", "bash" }) end
  if opts.wait_for then vim.list_extend(args, { ";", "tmux", "wait-for", "-S", opts.wait_for }) end
  table.insert(args, '"')
  ---Receive the wait
  if opts.wait_for then vim.list_extend(args, { "\\;", "wait-for", opts.wait_for }) end
  if cmd_is_shell then return vim.fn.join(args, " ") end
  return args
end

function M.wrap_in_single_quotes(str) return string.format("'%s'", str) end

---@param opts table
function M.next_qf_item(opts)
  opts = opts or {}
  local ok, _ = pcall(vim.cmd.cnext)
  if not ok then return echo_no_more_items() end
  if opts.center_view then vim.cmd.normal({ "zz", bang = true }) end
end

---@param opts table
function M.prev_qf_item(opts)
  opts = opts or {}
  local ok, _ = pcall(vim.cmd.cprev)
  if not ok then return echo_no_more_items() end
  if opts.center_view then vim.cmd.normal({ "zz", bang = true }) end
end

---Check if nvim was started with no args and without reading from stdin
function M.nvim_started_without_args() return not vim.g.using_stdin and vim.fn.argc() == 0 end

function M.has_remote_uis() return vim.tbl_count(vim.api.nvim_list_uis()) > 1 end

---Check if current cwd is home
function M.cwd_is_home() return vim.fn.getcwd() == vim.env.HOME end

function M.cwd_is_dwm() return vim.fn.getcwd() == vim.env.HOME .. "/data/repos/dwm" end

function M.cwd_is_dotfiles() return vim.fn.getcwd() == vim.env.HOME .. "/dotfiles" end

function M.cwd_is_notes() return vim.fn.getcwd() == vim.env.HOME .. "/data/notes/foam" end

---@class OpenQfList
---@field loclist? boolean
---@field height? integer
---@field focus? boolean

---Open quickfix list
---@param opts OpenQfList?
function M.open_qflist(opts)
  opts = vim.tbl_deep_extend("force", { focus = false, loclist = false, height = 7 }, opts or {})
  local copen_opts = { mods = { split = "botright" } }
  if opts.height then copen_opts.count = opts.height end
  if opts.loclist then return vim.cmd.lopen(copen_opts) end
  local ok, error = pcall(vim.cmd.copen, copen_opts)
  if not ok then vim.api.nvim_echo({ { vim.fn.string(error), "DiagnosticWarn" } }, false, {}) end
  if not opts.focus then vim.cmd.wincmd({ args = { "p" } }) end
end

---Toggle quickfix list
---@param opts OpenQfList?
function M.toggle_qflist(opts)
  if vim.bo.filetype == "qf" then return vim.cmd.cclose() end
  for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(winid)].filetype == "qf" then return vim.cmd.cclose() end
  end
  M.open_qflist(opts)
end

---Check if file is large without relying on buffers (only file path)
---@param file string
---@return boolean
function M.is_large_file(file)
  local ok, stats = pcall((vim.uv or vim.loop).fs_stat, file)
  if not ok or not stats then error("Cannot use fs_stat") end
  local lines_count = #vim.fn.readfile(file)
  return stats.size > vim.g.max_file.size
    or lines_count > vim.g.max_file.lines
    or stats.size / lines_count > vim.o.synmaxcol
end

---Conceal ripgrep 0 base with lua 1 base
---@param start_0 integer
---@param end_0 integer
---@param seg_start_1 integer
function M.rel_cols(start_0, end_0, seg_start_1)
  local shift = seg_start_1 - 1
  return (start_0 - shift) + 1, end_0 - shift
end

---@class RGStats
---@field matched_lines integer
---@field matches integer

---@class RGMatch
---@field text string

---@class RGSubmatch
---@field match RGMatch
---@field start integer
---@field end integer

---@class RGPath
---@field text string

---@class RGData
---@field path RGPath
---@field lines RGPath
---@field line_number integer
---@field absolute_offset integer
---@field submatches RGSubmatch[]
---@field stats RGStats

---@class RGContent
---@field type "begin"|"match"|"end"
---@field data RGData

---@param text string
---@param offset integer 0-based byte offset
---@return integer line_offset 0-based
---@return integer col 1-based byte column
---@return integer line_start 1-based byte index
local function rg_byte_offset_to_qf_position(text, offset)
  local line_offset = 0
  local line_start = 0
  local search_from = 1

  while true do
    local newline = text:find("\n", search_from, true)
    if not newline or newline > offset then break end

    line_offset = line_offset + 1
    line_start = newline
    search_from = newline + 1
  end

  return line_offset, offset - line_start + 1, line_start + 1
end

---@param text string
---@param line_start integer 1-based byte index
local function rg_line_text_at(text, line_start)
  local line_end = text:find("\n", line_start, true)
  return text:sub(line_start, line_end and line_end - 1 or #text)
end

local function vim_very_nomagic_escape(text) return text:gsub("\\", "\\\\"):gsub("/", "\\/") end

local function qf_exact_line_pattern(line_text, col, end_col)
  local match_end = math.min(math.max(end_col or col, col), #line_text)
  local before = line_text:sub(1, col - 1)
  local match = line_text:sub(col, match_end)
  local after = line_text:sub(match_end + 1)

  return "\\m^\\V"
    .. vim_very_nomagic_escape(before)
    .. "\\zs"
    .. vim_very_nomagic_escape(match)
    .. vim_very_nomagic_escape(after)
    .. "\\m$"
end

local function should_add_rg_qf_pattern(line_text, entries_count, opts)
  local pattern_limit = opts.pattern_limit or 5000
  local pattern_line_max = opts.pattern_line_max or 500
  if pattern_limit ~= false and entries_count >= pattern_limit then return false end
  return #line_text <= pattern_line_max
end

local function rg_json_match_to_qfitems(item, opts, entries_count)
  opts = opts or {}
  entries_count = entries_count or 0
  ---@type vim.quickfix.entry[]
  local entries = {}

  local lines_text = item.data.lines and item.data.lines.text
  if item.type ~= "match" or not lines_text then return entries end

  for _, submatch in ipairs(item.data.submatches or {}) do
    local line_offset, col, line_start = rg_byte_offset_to_qf_position(lines_text, submatch.start)
    local end_line_offset, end_col =
      rg_byte_offset_to_qf_position(lines_text, math.max(submatch["end"] - 1, submatch.start))
    local line_text = rg_line_text_at(lines_text, line_start)
    local qfitem = {
      text = line_text,
      filename = item.data.path.text,
      lnum = item.data.line_number + line_offset,
      col = col,
      end_lnum = item.data.line_number + end_line_offset,
      end_col = end_col,
      user_data = { submatch = submatch.match.text },
    }
    if should_add_rg_qf_pattern(line_text, entries_count + #entries, opts) then
      qfitem.pattern = qf_exact_line_pattern(line_text, col, line_offset == end_line_offset and end_col or #line_text)
    end
    table.insert(entries, qfitem)
  end

  return entries
end

---RipGrep json output to quickfix list items
---@param json RGContent[]
---@param opts table?
function M.rg_json_to_qfitems(json, opts)
  opts = opts or {}
  ---@type vim.quickfix.entry[]
  local entries = {}
  for _, item in ipairs(json) do
    ---Inner loop is required due to: https://github.com/BurntSushi/ripgrep/issues/1983
    ---and https://github.com/BurntSushi/ripgrep/issues/2779
    vim.list_extend(entries, rg_json_match_to_qfitems(item, opts, #entries))
  end
  return entries, vim.tbl_count(entries)
end

---@class GrepQfOpts
---@field batch_size? integer
---@field context? table
---@field on_finish? fun(count: integer, exit_code: integer)
---@field parse_batch_size? integer
---@field pattern_limit? integer|false
---@field pattern_line_max? integer
---@field title_prefix? string

---@param search string
---@param opts GrepQfOpts?
function M.grep_with_rg_to_qflist(search, opts)
  opts = opts or {}
  if search == "''" then
    vim.api.nvim_echo({ { "Empty search pattern" } }, false, { err = true })
    return { cancel = function() end }
  end

  local batch_size = opts.batch_size or 1000
  local parse_batch_size = opts.parse_batch_size or 1000
  local title_prefix = opts.title_prefix or "Grep"
  local running_title = ("[%s] running: %s"):format(title_prefix, search)
  local final_title = ("[%s] %%d results: %s"):format(title_prefix, search)

  vim.fn.setqflist({}, " ", { title = running_title, items = {}, context = opts.context })

  local state = {
    cancelled = false,
    count = 0,
    drain_scheduled = false,
    err_tail = "",
    errors = {},
    exit_code = nil,
    exited = false,
    finished = false,
    head = 1,
    job_id = nil,
    jumped = false,
    lines = {},
    pending_items = {},
    qf_id = vim.fn.getqflist({ id = 0 }).id,
    stdout_tail = "",
  }

  local function compact_queue()
    if state.head > 1000 then
      state.lines = vim.list_slice(state.lines, state.head)
      state.head = 1
    end
  end

  local function update_title(title) vim.fn.setqflist({}, "a", { id = state.qf_id, title = title }) end

  local function flush_items()
    if vim.tbl_isempty(state.pending_items) then return end

    local items = state.pending_items
    state.pending_items = {}
    vim.fn.setqflist({}, "a", { id = state.qf_id, items = items, title = final_title:format(state.count) })

    if not state.jumped then
      state.jumped = true
      vim.cmd.cfirst({ mods = { emsg_silent = true } })
      vim.cmd.normal({ "zz", bang = true })
    end
  end

  local finish
  local schedule_drain

  local function process_json_line(line)
    if line == "" then return end

    local ok, item = pcall(vim.json.decode, line, { luanil = { object = true } })
    if not ok then
      table.insert(state.errors, item)
      return
    end

    local entries = rg_json_match_to_qfitems(item, opts, state.count)
    if vim.tbl_isempty(entries) then return end

    state.count = state.count + #entries
    vim.list_extend(state.pending_items, entries)
    if #state.pending_items >= batch_size then flush_items() end
  end

  schedule_drain = function()
    if state.drain_scheduled or state.cancelled then return end
    state.drain_scheduled = true

    vim.schedule(function()
      state.drain_scheduled = false
      if state.cancelled then return end

      local processed = 0
      while state.head <= #state.lines and processed < parse_batch_size do
        process_json_line(state.lines[state.head])
        state.head = state.head + 1
        processed = processed + 1
      end
      compact_queue()

      if state.head <= #state.lines then
        schedule_drain()
      elseif state.exited then
        finish()
      end
    end)
  end

  finish = function()
    if state.finished or state.cancelled then return end
    state.finished = true
    flush_items()
    update_title(final_title:format(state.count))

    local exit_code = state.exit_code or 0
    if state.count == 0 and exit_code <= 1 then
      vim.api.nvim_echo({ { ("[%s] No results: %s"):format(title_prefix, search) } }, false, { err = true })
    elseif exit_code > 1 then
      local msg = table.concat(state.errors, "\n")
      if msg == "" then msg = ("rg exited with code %d"):format(exit_code) end
      vim.api.nvim_echo({ { msg } }, false, { err = true })
    else
      vim.api.nvim_echo({ { final_title:format(state.count), "DiagnosticOk" } }, false, {})
    end

    if opts.on_finish then opts.on_finish(state.count, exit_code) end
  end

  local function queue_stdout(data)
    if not data or vim.tbl_isempty(data) then return end

    data[1] = state.stdout_tail .. (data[1] or "")
    state.stdout_tail = table.remove(data) or ""
    vim.list_extend(state.lines, data)
    schedule_drain()
  end

  local function collect_stderr(data)
    if not data or vim.tbl_isempty(data) then return end

    data[1] = state.err_tail .. (data[1] or "")
    state.err_tail = table.remove(data) or ""
    vim.list_extend(state.errors, vim.tbl_filter(function(line) return line ~= "" end, data))
  end

  state.job_id = vim.fn.jobstart(rg_command(search, { json = true }), {
    on_exit = function(_, code)
      if state.stdout_tail ~= "" then
        table.insert(state.lines, state.stdout_tail)
        state.stdout_tail = ""
      end
      if state.err_tail ~= "" then
        table.insert(state.errors, state.err_tail)
        state.err_tail = ""
      end
      state.exit_code = code
      state.exited = true
      schedule_drain()
    end,
    on_stderr = function(_, data) collect_stderr(data) end,
    on_stdout = function(_, data) queue_stdout(data) end,
    stderr_buffered = false,
    stdin = "null",
    stdout_buffered = false,
  })

  if state.job_id <= 0 then
    state.cancelled = true
    vim.api.nvim_echo({ { "Could not start rg", "DiagnosticError" } }, false, { err = true })
  end

  return {
    cancel = function()
      if state.finished or state.cancelled then return end
      state.cancelled = true
      if state.job_id and state.job_id > 0 then vim.fn.jobstop(state.job_id) end
      update_title(("[%s] cancelled: %s"):format(title_prefix, search))
    end,
  }
end

---Treesitter compatible filetypes
---Basically, filetypes that have treesitter parsers
---@return string[]
function M.ts_compatible_filetypes()
  local filetypes = {}
  for filetype, tooling in pairs(tools.by_filetype or {}) do
    if vim.tbl_count(tooling.parsers or {}) > 0 then table.insert(filetypes, filetype) end
  end
  return filetypes
end

---@param dirname string
---@param perms? number
function M.mkdir(dirname, perms)
  if not perms then
    perms = 493 -- 0755
  end
  if not M.exists(dirname) then
    local parent = vim.fn.fnamemodify(dirname, ":h")
    if not M.exists(parent) then M.mkdir(parent) end
    vim.uv.fs_mkdir(dirname, perms)
  end
end

---@param filepath string
---@return string?
M.read_file = function(filepath)
  if not M.exists(filepath) then return nil end
  local fd = assert(vim.uv.fs_open(filepath, "r", 420)) -- 0644
  local stat = assert(vim.uv.fs_fstat(fd))
  local content = vim.uv.fs_read(fd, stat.size)
  vim.uv.fs_close(fd)
  return content
end

---@param filepath string
---@return any?
M.load_json_file = function(filepath)
  local content = M.read_file(filepath)
  if content then return vim.json.decode(content, { luanil = { object = true } }) end
end

---@param filename string
---@param contents string
function M.write_file(filename, contents)
  M.mkdir(vim.fn.fnamemodify(filename, ":h"))
  local fd = assert(vim.uv.fs_open(filename, "w", 420)) -- 0644
  vim.uv.fs_write(fd, contents)
  vim.uv.fs_close(fd)
end

---@param filepath string
---@return boolean
function M.exists(filepath)
  local stat = vim.uv.fs_stat(filepath)
  return stat ~= nil and stat.type ~= nil
end

---@class FzfOpts
---@field source string|table
---@field options? string[]
---@field prompt? string
---@field sink? fun(entry: string)
---@field sinklist? fun(entry:string[])
---@field refresh? fun(reload: fun(source: string[]): nil): (fun()|integer)?

---@param value string
---@return string
local function shell_quote(value) return "'" .. value:gsub("'", "'\\''") .. "'" end

---@param path string
---@return boolean
local function path_exists(path) return vim.uv.fs_stat(path) ~= nil end

---@param fzf_sock string
---@param source_file string
local function fzf_reload(fzf_sock, source_file)
  if vim.fn.executable("curl") ~= 1 or not path_exists(fzf_sock) then return end

  vim.fn.jobstart({
    "curl",
    "-fsS",
    "--unix-socket",
    fzf_sock,
    "http://fzf",
    "-d",
    "reload(cat " .. shell_quote(source_file) .. ")",
  }, { detach = true })
end

---@param fzf_sock string
---@param callback fun()
---@param attempts? integer
local function wait_for_fzf_socket(fzf_sock, callback, attempts)
  attempts = attempts or 40
  if path_exists(fzf_sock) then
    callback()
    return
  end

  if attempts <= 0 then return end
  vim.defer_fn(function() wait_for_fzf_socket(fzf_sock, callback, attempts - 1) end, 50)
end

---https://elanmed.dev/blog/native-fzf-in-neovim
---@param opts FzfOpts
function M.fzf(opts)
  opts.options = opts.options or {}
  local tempname = vim.fn.tempname()
  local source_temp = vim.fn.tempname()
  local fzf_sock = opts.refresh and (source_temp .. ".fzf.sock") or nil
  local closed = false

  local editor_height = vim.o.lines - 1
  local border_height = 2

  local listed = false
  local scratch = true
  local term_bufnr = vim.api.nvim_create_buf(listed, scratch)
  vim.api.nvim_create_autocmd("TermOpen", {
    buffer = term_bufnr,
    callback = function(args)
      if vim.api.nvim_get_option_value("buftype", { buf = args.buf }) ~= "terminal" then return end
      vim.cmd.startinsert()
    end,
  })
  vim.api.nvim_set_option_value("filetype", "fzf", { buf = term_bufnr })
  vim.keymap.set(
    "t",
    "<C-y>",
    "<CR>",
    { desc = "Alternative to pressing enter on fuzzy picker", nowait = true, silent = true, buffer = term_bufnr }
  )
  local term_winnr = vim.api.nvim_open_win(term_bufnr, true, {
    relative = "editor",
    row = editor_height,
    col = 0,
    width = vim.o.columns,
    height = math.floor(editor_height / 2 - border_height),
    border = "rounded",
    title = opts.prompt or "Fzf term",
  })
  vim.wo[term_winnr].number = false
  vim.wo[term_winnr].relativenumber = false
  vim.wo[term_winnr].signcolumn = "no"
  vim.wo[term_winnr].scrollbind = false
  vim.wo[term_winnr].cursorbind = false
  vim.api.nvim_set_option_value("winhl", "", { win = term_winnr })

  local source = (function()
    if type(opts.source) == "string" then
      return opts.source
    else
      vim.fn.writefile(opts.source, source_temp)
      return ([[cat %s]]):format(shell_quote(source_temp))
    end
  end)()

  local fzf_options = vim.deepcopy(opts.options)
  if fzf_sock then
    vim.fn.delete(fzf_sock)
    table.insert(fzf_options, "--listen=" .. shell_quote(fzf_sock))
    table.insert(fzf_options, "--bind=" .. shell_quote("ctrl-r:reload(cat " .. shell_quote(source_temp) .. ")"))
  end

  local cmd = ("FZF_API_KEY= %s | fzf %s > %s"):format(source, table.concat(fzf_options, " "), shell_quote(tempname))
  local refresh_cancel
  local job_id = vim.fn.jobstart(cmd, {
    term = true,
    on_exit = function()
      closed = true
      if type(refresh_cancel) == "function" then
        pcall(refresh_cancel)
      elseif type(refresh_cancel) == "number" and refresh_cancel > 0 then
        pcall(vim.fn.jobstop, refresh_cancel)
      end

      if vim.api.nvim_win_is_valid(term_winnr) then pcall(vim.api.nvim_win_close, term_winnr, true) end
      local temp_content = vim.fn.readfile(tempname)
      if #temp_content > 0 then
        if opts.sink then
          opts.sink(temp_content[1])
        elseif opts.sinklist then
          opts.sinklist(temp_content)
        end
      end

      vim.fn.delete(tempname)
      vim.fn.delete(source_temp)
      if fzf_sock then vim.fn.delete(fzf_sock) end
    end,
  })

  if job_id <= 0 or not opts.refresh or not fzf_sock then return end

  refresh_cancel = opts.refresh(function(next_source)
    if closed then return end
    vim.fn.writefile(next_source, source_temp)
    wait_for_fzf_socket(fzf_sock, function()
      if not closed then fzf_reload(fzf_sock, source_temp) end
    end)
  end)
end

---Custom select to override builtin one
---@generic T
---@param items T[] Arbitrary items
---@param opts? {prompt?: string, format_item?: (fun(item: T): string), kind?: string}
---@param on_choice fun(item?: T, idx?: number)
function M.select(items, opts, on_choice)
  opts = opts or {}

  local function adapted_items()
    local choices = {}
    for idx, item in ipairs(items) do
      local text = (opts.format_item or tostring)(item)
      table.insert(choices, string.format("%d: %s", idx, text))
    end
    return choices
  end

  M.fzf({
    source = adapted_items(),
    prompt = opts.prompt,
    ---@param entry string
    sink = function(entry)
      local idx = entry:gsub(":.*", "")
      on_choice(items[tonumber(idx)], tonumber(idx))
    end,
  })
end

---@param opts table?
function M.new_scratch_buffer(opts)
  opts = opts or {}
  M.feedkeys(":tabnew<CR>")
  if opts.filetype then M.feedkeys(string.format(":set filetype=%s<CR>", opts.filetype)) end
end

---Get a uuid
---@param opts table?
function M.get_uuid(opts)
  opts = opts or { chars = 64 }
  local seed = tostring(vim.uv.hrtime()) .. tostring(vim.uv.os_getpid())
  return vim.fn.sha256(seed):sub(1, opts.chars)
end

---@param task overseer.Task
---@param status overseer.Status Can be CANCELED, FAILURE, or SUCCESS
function M.close_window_on_exit_0(task, status)
  if
    status == require("overseer.constants").STATUS.SUCCESS
    and vim.api.nvim_get_option_value("buftype", { buf = task:get_bufnr() }) == "terminal"
  then
    vim.api.nvim_win_close(0, true)
  end
end

local function is_preview(buf)
  local winid = vim.fn.bufwinid(buf)
  return winid ~= -1 and vim.api.nvim_win_get_config(winid).row == 1
end

---@param bufnr integer?
---@return boolean
local function is_terminal_buffer(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return false end
  return vim.api.nvim_get_option_value("buftype", { buf = bufnr }) == "terminal"
end

---@param task overseer.Task
---@return Promise
local function wait_for_task_terminal(task)
  return require("async")(function()
    local timeout = false
    M.set_timeout(function() timeout = true end, 3000)

    while not timeout do
      local bufnr = task:get_bufnr()
      if is_terminal_buffer(bufnr) then return bufnr end
      await(M.wait(100))
    end

    error("Timed out waiting for task terminal buffer")
  end)
end

---@param task overseer.Task
---@param desc string
---@param apply fun(bufnr: integer)
local function setup_task_terminal(task, desc, apply)
  local function apply_if_terminal(bufnr)
    if not is_terminal_buffer(bufnr) then return false end
    if is_preview(bufnr) then return false end
    apply(bufnr)
    return true
  end

  wait_for_task_terminal(task):thenCall(function(bufnr)
    apply_if_terminal(bufnr)
    vim.api.nvim_create_autocmd("BufEnter", {
      desc = desc,
      buffer = bufnr,
      callback = function(args) apply_if_terminal(args.buf) end,
    })
  end, function() end)
end

---@param task overseer.Task
---@param data string[] Output of process. See :help channel-lines
function M.dispose_on_window_close(task, data)
  vim.api.nvim_create_autocmd("WinLeave", {
    desc = "Dispose task if still running after window closes",
    buffer = task:get_bufnr(),
    callback = function(args)
      if is_preview(args.buf) then return end
      if vim.api.nvim_get_option_value("buftype", { buf = args.buf }) ~= "terminal" then return end
      if task.status == require("overseer.constants").STATUS.RUNNING then task:dispose(true) end
    end,
  })
end

---@param task overseer.Task
function M.attach_keymaps(task)
  setup_task_terminal(task, "Attach task terminal keymaps", function(bufnr)
    M.attach_overseer_task_float_navigation(bufnr)
    if vim.api.nvim_get_current_buf() == bufnr then vim.cmd.startinsert() end
  end)
end

---@param bufnr? integer
---@return overseer.Task?
local function overseer_task_for_buf(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local task_id = vim.b[bufnr].overseer_task
  if not task_id then return end
  return require("overseer.task_list").get(task_id)
end

---@param bufnr? integer
function M.open_current_overseer_task_action(bufnr)
  local task = overseer_task_for_buf(bufnr)
  if not task then return vim.notify("Current buffer is not an Overseer task output", vim.log.levels.WARN) end

  require("overseer").run_action(task)
end

---@param step integer
function M.open_adjacent_overseer_task_float(step)
  local current_task = overseer_task_for_buf()
  if not current_task then return vim.notify("Current buffer is not an Overseer task output", vim.log.levels.WARN) end

  local sort = require("overseer.config").task_list.sort
  local tasks = require("overseer").list_tasks({
    include_ephemeral = true,
    sort = sort,
    filter = function(task) return task:get_bufnr() ~= nil end,
  })
  if #tasks <= 1 then return vim.notify("No other Overseer task output to show", vim.log.levels.INFO) end

  local current_index
  for index, task in ipairs(tasks) do
    if task.id == current_task.id then
      current_index = index
      break
    end
  end
  if not current_index then return vim.notify("Current Overseer task is not in the task list", vim.log.levels.WARN) end

  local next_index = ((current_index - 1 + step) % #tasks) + 1
  local next_task = tasks[next_index]
  M.attach_overseer_task_float_navigation(next_task:get_bufnr())
  require("overseer").run_action(next_task, "open float")
end

---@param bufnr? integer
function M.attach_overseer_task_float_navigation(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) or vim.b[bufnr].overseer_float_navigation_attached then return end
  vim.b[bufnr].overseer_float_navigation_attached = true

  vim.keymap.set("n", "]o", function() M.open_adjacent_overseer_task_float(1) end, {
    buffer = bufnr,
    desc = "Overseer: next task output float",
  })
  vim.keymap.set("n", "[o", function() M.open_adjacent_overseer_task_float(-1) end, {
    buffer = bufnr,
    desc = "Overseer: previous task output float",
  })
  vim.keymap.set("n", "<leader>od", function() M.open_current_overseer_task_action(bufnr) end, {
    buffer = bufnr,
    desc = "Overseer: task actions",
  })
  vim.keymap.set({ "n", "t" }, "<M-j>", function() M.open_adjacent_overseer_task_float(1) end, {
    buffer = bufnr,
    desc = "Overseer: next task output float",
  })
  vim.keymap.set({ "n", "t" }, "<M-k>", function() M.open_adjacent_overseer_task_float(-1) end, {
    buffer = bufnr,
    desc = "Overseer: previous task output float",
  })
end

---@param task overseer.Task
function M.schedule_open_overseer_task_float(task)
  vim.schedule(function()
    if not task or not task:get_bufnr() then return end
    pcall(require("overseer").run_action, task, "open float")
  end)
end

---@param bufnr integer
---@return integer?
local function overseer_job_id_for_buf(bufnr)
  local task_id = vim.b[bufnr].overseer_task
  if task_id then
    local ok, task_list = pcall(require, "overseer.task_list")
    local task = ok and task_list.get(task_id) or nil
    if task then return task.job_id or task.strategy and task.strategy.job_id end
  end

  local ok, overseer = pcall(require, "overseer")
  if not ok then return nil end

  local tasks = overseer.list_tasks({
    include_ephemeral = true,
    filter = function(task) return task:get_bufnr() == bufnr end,
  })
  local task = tasks[1]
  if task then return task.job_id or task.strategy and task.strategy.job_id end
end

---@param bufnr? integer
---@param job_id? integer
function M.refresh_terminal_window(bufnr, job_id)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  job_id = job_id or vim.b[bufnr].terminal_job_id or overseer_job_id_for_buf(bufnr)

  if not job_id or job_id == 0 then
    local channel = vim.api.nvim_get_option_value("channel", { buf = bufnr })
    job_id = channel ~= 0 and channel or nil
  end
  if not job_id or job_id == 0 then
    for _, chan in ipairs(vim.api.nvim_list_chans()) do
      if chan.mode == "terminal" and (chan.buffer == bufnr or chan.buf == bufnr) then
        job_id = chan.id
        break
      end
    end
  end

  if job_id and job_id ~= 0 then
    local ok, err = pcall(vim.fn.jobresize, job_id, vim.fn.winwidth(0), vim.fn.winheight(0))
    if not ok and not tostring(err):find("not a job", 1, true) then
      vim.notify(("Could not resize terminal job: %s"):format(err), vim.log.levels.WARN)
    end
  end

  vim.cmd.redraw({ bang = true })
end

---@param task overseer.Task
function M.refresh_task_terminal_window(task)
  setup_task_terminal(task, "Refresh task terminal window", function(bufnr)
    if vim.api.nvim_get_current_buf() ~= bufnr then return end

    local job_id = vim.b[bufnr].terminal_job_id or task.job_id
    if not job_id or job_id == 0 then
      ---@diagnostic disable-next-line: invisible
      local strategy = task.strategy
      job_id = strategy and strategy.job_id or nil
    end

    M.refresh_terminal_window(bufnr, job_id)
  end)
end

local function shell_fence_under_cursor()
  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local cursor = vim.api.nvim_win_get_cursor(0)[1]
  local start_line, lang

  local function fence_lang(line)
    local fence_start = line:find("```", 1, true)
    if not fence_start then return nil end
    return line:sub(fence_start + 3):match("^%s*([%w_-]+)")
  end

  local function has_fence(line) return line:find("```", 1, true) ~= nil end

  for lnum = cursor, 1, -1 do
    lang = fence_lang(lines[lnum])
    if lang then
      start_line = lnum
      break
    end
  end

  if not start_line then return nil end
  lang = lang:lower()
  if not vim.list_contains({ "sh", "bash", "shell" }, lang) then return nil end

  local end_line
  for lnum = start_line + 1, #lines do
    if has_fence(lines[lnum]) then
      end_line = lnum
      break
    end
  end

  if not end_line or cursor > end_line then return nil end
  return vim.list_slice(lines, start_line + 1, end_line - 1), lang
end

function M.run_shell_fence()
  local command_lines, lang = shell_fence_under_cursor()
  if not command_lines or vim.iter(command_lines):all(function(line) return line:match("^%s*$") ~= nil end) then
    vim.notify("No shell fence under cursor", vim.log.levels.WARN)
    return
  end

  local ok, overseer = pcall(require, "overseer")
  if not ok then
    vim.notify("overseer.nvim is not available", vim.log.levels.ERROR)
    return
  end

  local first_line = vim.iter(command_lines):find(function(line) return not line:match("^%s*$") end) or "shell fence"
  first_line = vim.trim(first_line)
  if #first_line > 60 then first_line = first_line:sub(1, 57) .. "..." end

  local script_path = vim.fn.tempname()
  local write_ok, write_result = pcall(vim.fn.writefile, command_lines, script_path)
  if not write_ok or write_result ~= 0 then
    vim.notify("Failed to write shell fence script", vim.log.levels.ERROR)
    return
  end

  local task = overseer.new_task({
    name = "shell fence: " .. first_line,
    cmd = { lang == "bash" and "bash" or "sh", script_path },
    cwd = vim.fn.expand("%:p:h"),
    metadata = {
      PREVENT_QUIT = true,
    },
    components = { "default" },
  })
  task:subscribe("on_complete", function() vim.fn.delete(script_path) end)
  task:start()

  vim.defer_fn(function()
    if not task:get_bufnr() then return end
    M.attach_keymaps(task)
    M.schedule_open_overseer_task_float(task)
  end, 100)
end

---@param task overseer.Task
function M.force_very_fullscreen_float(task)
  setup_task_terminal(task, "Resize task terminal float", function(bufnr)
    if vim.api.nvim_get_current_buf() ~= bufnr then return end
    pcall(vim.fn.jobresize, task.job_id, vim.o.columns, vim.o.lines - 3)
    vim.cmd.wincmd({ "|" })
  end)
end

---@param task overseer.Task
function M.start_insert_mode(task)
  setup_task_terminal(task, "Start insert mode in task terminal", function(bufnr)
    if vim.api.nvim_get_current_buf() == bufnr then vim.cmd.startinsert() end
  end)
end

return M
