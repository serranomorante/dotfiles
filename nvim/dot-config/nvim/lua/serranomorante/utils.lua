local constants = require("serranomorante.constants")

local M = {}

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
    vim.api.nvim_err_writeln(("Error running command %s\nError message:\n%s"):format(table.concat(cmd, " "), result))
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
---@alias ToolEnsureInstall table<GeneralToolType|TreesitterToolType|CocToolType, string[]|table[]>

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
---Example: <filename>:<line>:<col>
function M.filename_with_cursor_pos()
  local bufname = vim.api.nvim_buf_get_name(0)
  local line, col = unpack(vim.api.nvim_win_get_cursor(0))
  return ("%s:%s:%s"):format(bufname, line, col)
end

function M.next_qf_item()
  local ok, _ = pcall(vim.cmd.cnext)
  if not ok then return vim.notify("No more items", vim.log.levels.WARN) end
end

function M.prev_qf_item()
  local ok, _ = pcall(vim.cmd.cprev)
  if not ok then return vim.notify("No more items", vim.log.levels.WARN) end
end

---Check if nvim was started with no args and without reading from stdin
function M.nvim_started_without_args() return vim.fn.argc(-1) == 0 and not vim.g.using_stdin end

---Check if current cwd is home
function M.cwd_is_home() return vim.fn.getcwd() == vim.env.HOME end

function M.open_quickfix_list()
  vim.cmd.cfirst()
  vim.cmd("normal! zz")
  require("serranomorante.plugins.quicker").open_qf()
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

return M
