local events = require("serranomorante.events")
local tools = require("serranomorante.tools")

local M = {}

---Check if a plugin spec exists in lazy config.
---This will not load the plugin.
---@param plugin string # The plugin to search for
---@return boolean available # Whether the plugin is available
function M.is_available(plugin)
  local lazy_config_avail, lazy_config = pcall(require, "lazy.core.config")
  return lazy_config_avail and lazy_config.plugins[plugin] ~= nil
end

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

  for _, worktree in ipairs(worktrees) do
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

--- Toggle buffer LSP inlay hints
--- Thanks AstroNvim
---@param bufnr? number of the buffer to toggle the clients on
function M.toggle_buffer_inlay_hints(bufnr)
  bufnr = bufnr or 0
  vim.b[bufnr].inlay_hints_enabled = not vim.b[bufnr].inlay_hints_enabled
  vim.lsp.inlay_hint.enable(bufnr, vim.b[bufnr].inlay_hints_enabled)
end

--- Toggle LSP codelens
function M.toggle_codelens()
  vim.g.codelens_enabled = not vim.g.codelens_enabled
  if not vim.g.codelens_enabled then vim.lsp.codelens.clear() end
end

function M.bool2str(bool) return bool and "on" or "off" end

--- Helper function to check if any active LSP clients given a filter provide a specific capability
---@param capability string The server capability to check for (example: "documentFormattingProvider")
---@param filter vim.lsp.get_clients.filter|nil (table|nil) A table with
---              key-value pairs used to filter the returned clients.
---              The available keys are:
---               - id (number): Only return clients with the given id
---               - bufnr (number): Only return clients attached to this buffer
---               - name (string): Only return clients with the given name
---@return boolean # Whether or not any of the clients provide the capability
function M.has_capability(capability, filter)
  for _, client in ipairs(vim.lsp.get_clients(filter)) do
    if client.supports_method(capability) then return true end
  end
  return false
end

function M.del_buffer_autocmd(augroup, bufnr)
  local cmds_found, cmds = pcall(vim.api.nvim_get_autocmds, { group = augroup, buffer = bufnr })
  if cmds_found then vim.tbl_map(function(cmd) vim.api.nvim_del_autocmd(cmd.id) end, cmds) end
end

---@alias MasonToolType "formatters"|"lsp"|"linters"|"dap"|"extra"
---@alias TreesitterToolType "parsers"
---@alias ToolEnsureInstall table<MasonToolType|TreesitterToolType, string[]|table[]>

---Merges an array of `ToolEnsureInstall` specs into 1 flat array of strings
---@param installer_type? "treesitter"|"mason" We will use Mason by default
---@param ... ToolEnsureInstall
---@return string[] # A flat array of tools without duplicates
function M.merge_tools(installer_type, ...)
  installer_type = installer_type or "mason"
  local mason_tool_type = { "formatters", "lsp", "linters", "dap", "extra" }
  local treesitter_tool_type = { "parsers" }
  local tool_type_by_installer = { mason = mason_tool_type, treesitter = treesitter_tool_type }
  local merge_result = {}
  for _, tools_table in ipairs({ ... }) do
    for _, tool_type in ipairs(tool_type_by_installer[installer_type]) do
      for _, tool in ipairs(tools_table[tool_type] or {}) do
        if not vim.list_contains(merge_result, tool) then table.insert(merge_result, tool) end
      end
    end
  end
  return merge_result
end

---Get a list of tools from a specific tool type: lsp, dap, etc.
---@param base table<string, ToolEnsureInstall> The base list of tools
---@param tool_type MasonToolType|TreesitterToolType The type to extract tools from
---@param use_lspconfig_map? boolean Whether we should use nvim-lspconfig names (lua-language-server -> lua_ls)
---@param lspconfig_map? table<string, string> Your custom lspconfig mapping
---@return string[]
function M.get_from_tools(base, tool_type, use_lspconfig_map, lspconfig_map)
  local types = {}
  for _, v in pairs(base) do
    for _, tool in ipairs(v[tool_type] or {}) do
      if type(tool) == "table" then tool = tool[1] end
      if use_lspconfig_map then
        local nvim_lspconfig_map = lspconfig_map or tools.mason_to_lspconfig
        if nvim_lspconfig_map[tool] ~= nil then tool = nvim_lspconfig_map[tool] end
      end
      if tool and not vim.list_contains(types, tool) then table.insert(types, tool) end
    end
  end
  return types
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

---Resolve the options table for a given plugin with lazy
---@param plugin string The plugin to search for
---@return table opts # The plugin options
function M.plugin_opts(plugin)
  local lazy_config_avail, lazy_config = pcall(require, "lazy.core.config")
  local lazy_plugin_avail, lazy_plugin = pcall(require, "lazy.core.plugin")
  local opts = {}
  if lazy_config_avail and lazy_plugin_avail then
    local spec = lazy_config.spec.plugins[plugin]
    if spec then opts = lazy_plugin.values(spec, "opts") end
  end
  return opts
end

---Execute a custom user event constructed by a "lazy_type" and a filetype
---@param lazy_type "LSP" | "DAP"
---@param opts? { filetype?: string, buffer?: integer, delay?: boolean }
function M.load_plugin_by_filetype(lazy_type, opts)
  opts = opts or {}
  local filetype = opts.filetype or vim.api.nvim_get_option_value("filetype", { buf = opts.buffer or 0 })

  if filetype and lazy_type then
    local capitalized_filetype = filetype:gsub("^%l", string.upper) -- https://stackoverflow.com/a/2421746
    events.event(lazy_type .. "Load" .. capitalized_filetype, opts.delay)
  end
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

return M
