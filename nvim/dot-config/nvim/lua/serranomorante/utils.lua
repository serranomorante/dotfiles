local constants = require("serranomorante.constants")
local tools = require("serranomorante.tools")

local M = {}

---Writes a Grep/Find command into vim's command-line with
---nnn's hovered dir prepopulated
---@param search_type 'Grep'|'Find'
---@param filepath string
function M.nnn_search_in_dir(search_type, filepath)
  local search_dir = vim.fn.fnamemodify(filepath or "", ":p:~:h")
  if vim.fn.isdirectory(vim.fn.expand(search_dir)) ~= 1 then
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
---@alias CocToolType "extensions"
---@alias ToolEnsureInstall table<GeneralToolType|TreesitterToolType|CocToolType, string[]>

---Merges an array of `ToolEnsureInstall` specs into 1 flat array of strings
---@param installer_type? "general"|"treesitter"|"coc" Default is "general"
---@param ... ToolEnsureInstall
---@return string[] # A flat array of tools without duplicates
function M.merge_tools(installer_type, ...)
  installer_type = installer_type or "general"
  local general_tool_type = { "fmts", "lsp", "linters", "dap", "extra" }
  local treesitter_tool_type = { "parsers" }
  local coc_tool_type = { "extensions" }
  local tool_type_by_installer = {
    ["general"] = general_tool_type,
    ["treesitter"] = treesitter_tool_type,
    ["coc"] = coc_tool_type,
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
  return vim.startswith(filename, dir) and vim.fn.filereadable(filename) == 1
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
  if vim.g.codelens_enabled then vim.lsp.codelens.refresh({ bufnr = buf }) end
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
  local grep_cmd = "rg -e " .. search:gsub("\\'", "\\x27") -- escape single quotes
  if opts.json then grep_cmd = string.format("%s %s", grep_cmd, "--json") end
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
---@field session_name string
---@field include_binary? boolean
---@field retain_shell? boolean

---@param cmd table
---@param opts? TmuxWrapperOpts
function M.wrap_overseer_args_with_tmux(cmd, opts)
  opts = opts or {}
  local args = {
    "-L", -- use different tmux server for overseer tasks
    "overseer",
    "-f", -- use tmux config that disables statusbar
    vim.env.HOME .. "/.config/tmux/tmuxnvim.conf",
    "new-session",
    "-A", -- attach in session exists
  }
  if opts.include_binary then table.insert(args, 1, "tmux") end
  if opts.cwd then vim.list_extend(args, { "-c", M.wrap_in_single_quotes(opts.cwd) }) end
  if opts.session_name then
    vim.list_extend(args, { "-s", M.wrap_in_single_quotes(opts.session_name .. vim.fn.fnameescape(vim.v.servername)) })
  end
  ---Don't exit after command execution
  if opts.retain_shell then
    table.insert(args, "sh")
    table.insert(args, "-c")
    table.insert(args, '"')
  end
  vim.list_extend(args, cmd)
  if opts.retain_shell then
    table.insert(args, ";")
    table.insert(args, "exec bash")
    table.insert(args, '"')
  end
  return args
end

function M.wrap_in_single_quotes(str) return string.format("'%s'", str) end

function M.next_qf_item()
  local ok, _ = pcall(vim.cmd.cnext)
  if not ok then return echo_no_more_items() end
end

function M.prev_qf_item()
  local ok, _ = pcall(vim.cmd.cprev)
  if not ok then return echo_no_more_items() end
end

---Check if nvim was started with no args and without reading from stdin
function M.nvim_started_without_args() return vim.fn.argc(-1) == 0 and not vim.g.using_stdin end

---Check if current cwd is home
function M.cwd_is_home() return vim.fn.getcwd() == vim.env.HOME end

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

---RipGrep json output to quickfix list items
---@param json RGContent[]
function M.rg_json_to_qfitems(json)
  ---@type vim.quickfix.entry[]
  local entries = {}
  for json_index, item in pairs(json) do
    local prev_new_line_match_end = 1

    ---Detect the "end" item so we can gather if the search was --multiline or not
    local end_item_found_cache = false
    local count = json_index + 1
    while not end_item_found_cache and json[count] and json[count].type ~= "end" do
      count = count + 1
    end
    local is_multiline = json[count] and json[count].data.stats.matched_lines > json[count].data.stats.matches
    end_item_found_cache = item.type == "end" and false or true

    ---Inner loop is required due to: https://github.com/BurntSushi/ripgrep/issues/1983
    ---and https://github.com/BurntSushi/ripgrep/issues/2779
    for i, submatch in pairs(item.data.submatches or {}) do
      if is_multiline then
        local new_line_match_end = item.data.lines.text:find("\n", submatch["end"]) + 1
        local text = item.data.lines.text:sub(prev_new_line_match_end, new_line_match_end)
        local col, end_col = M.rel_cols(submatch.start, submatch["end"], prev_new_line_match_end)
        table.insert(entries, {
          text = text,
          filename = item.data.path.text,
          lnum = item.data.line_number + ((i - 1) * vim.tbl_count(vim.fn.split(submatch.match.text, "\n"))),
          col = col,
          end_col = end_col,
          user_data = { submatch = submatch.match.text },
        })
        prev_new_line_match_end = new_line_match_end or 1
      else
        table.insert(entries, {
          text = item.data.lines.text,
          filename = item.data.path.text,
          lnum = item.data.line_number,
          col = submatch.start + 1,
          end_col = submatch["end"],
          user_data = { submatch = submatch.match.text },
        })
      end
    end
  end
  return entries, vim.tbl_count(entries)
end

---Treesitter compatible filetypes
---Basically, filetypes that have treesitter parsers
---@return string[]
function M.ts_compatible_filetypes()
  local filetypes = {}
  for filetype, tooling in pairs(tools.by_filetype) do
    if vim.tbl_count(tooling.parsers) > 0 then table.insert(filetypes, filetype) end
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

---https://elanmed.dev/blog/native-fzf-in-neovim
---@param opts FzfOpts
function M.fzf(opts)
  opts.options = opts.options or {}
  local tempname = vim.fn.tempname()
  local source_temp = vim.fn.tempname()

  local editor_height = vim.o.lines - 1
  local border_height = 2

  local listed = false
  local scratch = true
  local term_bufnr = vim.api.nvim_create_buf(listed, scratch)
  vim.api.nvim_set_option_value("filetype", "fzf", { buf = term_bufnr })
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

  local source = (function()
    if type(opts.source) == "string" then
      return opts.source
    else
      vim.fn.writefile(opts.source, source_temp)
      return ([[cat %s]]):format(source_temp)
    end
  end)()

  local cmd = ("%s | fzf %s > %s"):format(source, table.concat(opts.options, " "), tempname)
  vim.fn.jobstart(cmd, {
    term = true,
    on_exit = function()
      vim.api.nvim_win_close(term_winnr, true)
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
    end,
  })
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

return M
