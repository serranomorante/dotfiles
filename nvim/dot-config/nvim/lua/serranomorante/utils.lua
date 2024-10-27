local tools = require("serranomorante.tools")
local constants = require("serranomorante.constants")

local M = {}

---Check if a plugin has been loaded
---@param plugin string # The name of the plugin. It should be the same as the one you use in `require(plugin name)`
---@return boolean available # Whether the plugin is available
function M.is_available(plugin) return package.loaded[plugin] ~= nil end

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
    vim.api.nvim_err_writeln(("Error running command %s\nError message:\n%s"):format(table.concat(cmd, " "), result))
  end
  return success and result:gsub("[\27\155][][()#;?%d]*[A-PRZcf-ntqry=><~]", "") or nil
end

--- Get the first worktree that a file belongs to (from a predefined list of worktrees only)
--- Very useful for `.dotfiles` repository
---
--- Thanks AstroNvim!!
--- https://astronvim.com/Recipes/detached_git_worktrees
---
---@param path string? the file to check, defaults to the current file
---@param worktrees table<string, string>[]? an array like table of worktrees with entries `toplevel` and `gitdir`, default retrieves from `vim.g.git_worktrees`
---@return table<string, string>|nil # a table specifying the `toplevel` and `gitdir` of a worktree or nil if not found
function M.file_worktree(path, worktrees)
  worktrees = worktrees or vim.g.git_worktrees
  if not worktrees then return end
  path = path or vim.fn.resolve(vim.fn.expand("%"))

  if vim.startswith(path, "oil:") then path = path:gsub("oil:", "") end

  for _, worktree in pairs(worktrees) do
    if
      M.cmd({
        "git",
        "--work-tree",
        worktree.toplevel,
        "--git-dir",
        worktree.gitdir,
        "ls-files",
        "--error-unmatch",
        path,
      }, false)
    then
      return worktree
    end
  end
end

---Toggle global LSP inlay hints
function M.toggle_inlay_hints()
  if vim.lsp.inlay_hint then
    ---@diagnostic disable-next-line: missing-parameter
    local is_enabled = not vim.lsp.inlay_hint.is_enabled()
    vim.lsp.inlay_hint.enable(is_enabled)
    return is_enabled
  end
  return false
end

--- Toggle LSP codelens
function M.toggle_codelens()
  vim.g.codelens_enabled = not vim.g.codelens_enabled
  if not vim.g.codelens_enabled then vim.lsp.codelens.clear() end
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
    if client.supports_method(capability) then return true end
  end
  return false
end

function M.del_buffer_autocmd(augroup, bufnr)
  local cmds_found, cmds = pcall(vim.api.nvim_get_autocmds, { group = augroup, buffer = bufnr })
  if cmds_found then vim.tbl_map(function(cmd) vim.api.nvim_del_autocmd(cmd.id) end, cmds) end
end

---@alias GeneralToolType "formatters"|"lsp"|"linters"|"dap"|"extra"
---@alias TreesitterToolType "parsers"
---@alias CocToolType "extensions"
---@alias ToolEnsureInstall table<GeneralToolType|TreesitterToolType|CocToolType, string[]|table[]>

---Merges an array of `ToolEnsureInstall` specs into 1 flat array of strings
---@param installer_type? "general"|"treesitter"|"coc" Default is "general"
---@param ... ToolEnsureInstall
---@return string[] # A flat array of tools without duplicates
function M.merge_tools(installer_type, ...)
  installer_type = installer_type or "general"
  local general_tool_type = { "formatters", "lsp", "linters", "dap", "extra" }
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

---Check if buffer belongs to a cwd
---@param bufnr integer
---@param cwd string? Uses current if no cwd is passed
---@return boolean
function M.buf_inside_cwd(bufnr, cwd)
  local dir = cwd or vim.fn.getcwd()
  dir = dir:sub(-1) ~= "/" and dir .. "/" or dir
  return vim.startswith(vim.api.nvim_buf_get_name(bufnr), dir)
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
function M.update_indent_line_curbuf()
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_buf(winid) == vim.api.nvim_get_current_buf() then
      vim.wo[winid].listchars = M.update_indent_line(vim.wo[winid].listchars, vim.bo.shiftwidth)
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

---Replace `%` char from filenames
---@param filename string
function M.get_escaped_filename(filename) return filename:gsub("%%", "_") end

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

---@param bufnr integer
---@return boolean
function M.buf_has_coc_extension_available(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local has_extension = false
  local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
  local filetype_tools = ((tools.by_filetype[filetype] or {}).extensions or {})
  for _, extension in ipairs(vim.g.coc_global_extensions or {}) do
    if vim.list_contains(filetype_tools, extension) then has_extension = true end
  end
  return has_extension
end

---Rules to detect if we should prevent attaching coc to this buffer
---If not already attached, this function does nothing
---@param bufnr integer
---@return boolean
function M.buf_prevent_coc_attach(bufnr)
  local prevent_coc_attach = false
  local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
  if vim.wo.diff then prevent_coc_attach = true end
  if not M.buf_has_coc_extension_available(bufnr) then prevent_coc_attach = true end
  return prevent_coc_attach
end

---Enable/disable coc per buffer based on whether passed buffer's filetype
---has coc-extensions assigned
---@param bufnr? integer
---@param on_coc_enabled? function
function M.setup_coc_per_buffer(bufnr, on_coc_enabled)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local document_is_attached = vim.g.coc_service_initialized == 1 and vim.b[bufnr].coc_enabled == 1
  if document_is_attached then return end

  local coc_enabled = 0 -- disabled by default
  if vim.g.coc_service_initialized == 1 then coc_enabled = 1 end
  if M.buf_prevent_coc_attach(bufnr) then coc_enabled = 0 end
  vim.b[bufnr].coc_enabled = coc_enabled
  if on_coc_enabled ~= nil and coc_enabled == 1 then on_coc_enabled(bufnr) end
end

---Simple setTimeout wrapper
---@param timeout integer
---@param callback function
function M.set_timeout(timeout, callback)
  local timer = vim.uv.new_timer()
  if timer == nil then return end
  timer:start(timeout, 0, function()
    timer:stop()
    timer:close()
    callback()
  end)
  return timer
end

---Return an adapted filename which includes cursor's current line and column
---Example: <filename>:<line>:<col>
function M.filename_with_cursor_pos()
  local fname = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":.")
  local line_col_pair = vim.api.nvim_win_get_cursor(0) -- row is index 1, column is index 0 indexed
  return fname .. ":" .. tostring(line_col_pair[1]) .. ":" .. tostring(line_col_pair[2])
end

---@param cmd table
---@param session_name string
function M.wrap_overseer_args_with_tmux(cmd, session_name)
  local args = {
    "-L", -- use different tmux server for overseer tasks
    "overseer",
    "-f", -- use tmux config that disables statusbar
    vim.env.HOME .. "/.config/tmux/tmuxnvim.conf",
    "new-session",
    "-A", -- attach in session exists
    "-s", -- session name
    session_name,
  }
  vim.list_extend(args, cmd)
  return args
end

function M.check_quickfix_list_open()
  for _, win in pairs(vim.fn.getwininfo()) do
    if win["quickfix"] == 1 then return true end
  end
  return false
end

function M.next_qf_item()
  local ok, _ = pcall(vim.cmd.cnext)
  if not ok then return vim.notify("No more items", vim.log.levels.WARN) end
end

function M.prev_qf_item()
  local ok, _ = pcall(vim.cmd.cprev)
  if not ok then return vim.notify("No more items", vim.log.levels.WARN) end
end

---Check if nvim was started with no args
function M.nvim_started_without_args() return vim.fn.argc(-1) == 0 end

return M
