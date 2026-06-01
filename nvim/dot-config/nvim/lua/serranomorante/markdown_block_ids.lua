local M = {}
local utils = require("serranomorante.utils")

local ID_PATTERN = "[A-Za-z][A-Za-z0-9-]*"
local ID_LINE_PATTERN = "^%s*@id%s+(" .. ID_PATTERN .. ")%s*$"

local function warn(message) vim.notify("[Markdown @id] " .. message, vim.log.levels.WARN) end

local function lua_pattern_escape(value) return (value:gsub("([^%w])", "%%%1")) end

local function is_blank(line) return line:match("^%s*$") ~= nil end

local function is_metadata_line(line) return line:match("^%s*@[%w-]+%s+") ~= nil end

local function parse_id_line(line) return line:match(ID_LINE_PATTERN) end

local function is_attached_to_block(lines, lnum)
  local prev = lnum - 1
  while prev >= 1 do
    local line = lines[prev]
    if is_blank(line) then return false end
    if not is_metadata_line(line) then return true end
    prev = prev - 1
  end
  return false
end

local function get_buffer_lines(bufnr) return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false) end

local function get_file_lines(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then return nil end
  return lines
end

local function normalize(path)
  if not path or path == "" then return nil end
  return vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
end

local function get_uri_lines(uri)
  local path = normalize(vim.uri_to_fname(uri))
  if not path then return nil end

  local bufnr = vim.fn.bufnr(path)
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then return get_buffer_lines(bufnr) end
  return get_file_lines(path)
end

local function diagnostic_missing_heading(diagnostic)
  if not diagnostic.message then return nil end
  return diagnostic.message:match("Link to non%-existent heading '(" .. ID_PATTERN .. ")'")
    or diagnostic.message:match("Link to non%-existent heading (" .. ID_PATTERN .. ")")
end

local function diagnostic_text(lines, diagnostic)
  if not diagnostic.range or not diagnostic.range.start then return nil end

  local lnum = diagnostic.range.start.line + 1
  local line = lines[lnum]
  if not line then return nil end

  local start_col = diagnostic.range.start.character + 1
  local end_col = diagnostic.range["end"] and diagnostic.range["end"].character or #line
  local sliced = line:sub(start_col, math.max(start_col, end_col))
  return sliced ~= "" and sliced or line
end

local function is_block_id_diagnostic(lines, diagnostic)
  local id = diagnostic_missing_heading(diagnostic)
  if not id then return false end

  local text = diagnostic_text(lines, diagnostic) or ""
  if text:find("#%^" .. lua_pattern_escape(id)) then return true end

  if not diagnostic.range or not diagnostic.range.start then return false end
  local line = lines[diagnostic.range.start.line + 1] or ""
  return line:find("#%^" .. lua_pattern_escape(id)) ~= nil
end

local function file_exists(path)
  local stat = path and vim.uv.fs_stat(path)
  return stat and stat.type == "file"
end

local function get_buf_path(bufnr) return normalize(vim.api.nvim_buf_get_name(bufnr)) end

local function get_root(bufnr)
  for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr, name = "marksman" })) do
    if client.root_dir and client.root_dir ~= "" then return normalize(client.root_dir) end
    if client.workspace_folders and client.workspace_folders[1] then
      return normalize(vim.uri_to_fname(client.workspace_folders[1].uri))
    end
  end

  local buf_path = get_buf_path(bufnr)
  if buf_path then
    local ok, root = pcall(vim.fs.root, buf_path, { ".marksman.toml", ".git" })
    if ok and root then return normalize(root) end
  end

  return normalize(vim.fn.getcwd())
end

local function strip_wiki_alias(target) return target:match("^([^|]+)") or target end

local function strip_markdown_title(target)
  target = target:match("^%s*<([^>]+)>%s*$") or target
  return target:match("^(%S+)") or target
end

local function parse_block_target(raw_target, kind)
  local target = kind == "wiki" and strip_wiki_alias(raw_target) or strip_markdown_title(raw_target)
  local file_part, id = target:match("^(.-)#%^(" .. ID_PATTERN .. ")$")
  if not id then return nil end
  return { file_part = file_part, id = id, kind = kind }
end

local function find_wikilink_at_cursor(line, cursor_col)
  local search_from = 1
  while true do
    local start_col, end_col, target = line:find("%[%[([^%]]+)%]%]", search_from)
    if not start_col then return nil end
    if cursor_col >= start_col and cursor_col <= end_col then return parse_block_target(target, "wiki") end
    search_from = end_col + 1
  end
end

local function find_markdown_link_at_cursor(line, cursor_col)
  local search_from = 1
  while true do
    local start_col, end_col, target = line:find("!-%[[^%]]-%]%(([^%)]+)%)", search_from)
    if not start_col then return nil end
    if cursor_col >= start_col and cursor_col <= end_col then return parse_block_target(target, "markdown") end
    search_from = end_col + 1
  end
end

local function block_target_under_cursor(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], false)[1] or ""
  local cursor_col = cursor[2] + 1
  return find_wikilink_at_cursor(line, cursor_col) or find_markdown_link_at_cursor(line, cursor_col)
end

local function open_at(path, lnum)
  if get_buf_path(0) ~= path then vim.cmd.edit({ args = { path }, mods = { hide = true } }) end
  vim.api.nvim_win_set_cursor(0, { lnum, 0 })
  vim.cmd.normal({ args = { "zz" }, bang = true })
end

local function id_locations(lines, id)
  local locations = {}
  for lnum, line in ipairs(lines) do
    if parse_id_line(line) == id and is_attached_to_block(lines, lnum) then table.insert(locations, lnum) end
  end
  return locations
end

local function go_to_id(path, id, opts)
  opts = opts or {}
  local target_bufnr = vim.fn.bufnr(path)
  local lines
  if target_bufnr ~= -1 and vim.api.nvim_buf_is_loaded(target_bufnr) then
    lines = get_buffer_lines(target_bufnr)
  else
    lines = get_file_lines(path)
  end

  if not lines then
    if not opts.quiet then warn(("Could not read %s"):format(path)) end
    return false
  end

  local locations = id_locations(lines, id)
  if #locations == 0 then
    if not opts.quiet then warn(("No attached @id %s found in %s"):format(id, vim.fn.fnamemodify(path, ":~:."))) end
    return false
  end
  if #locations > 1 then
    warn(("Duplicate @id %s in %s; opening the first match"):format(id, vim.fn.fnamemodify(path, ":~:.")))
  end

  open_at(path, locations[1])
  return true
end

local function rg_match_paths(stdout)
  local paths = {}
  local seen = {}

  for line in stdout:gmatch("[^\r\n]+") do
    local ok, item = pcall(vim.json.decode, line)
    if ok and item and item.type == "match" and item.data and item.data.path and item.data.path.text then
      local path = normalize(item.data.path.text)
      if path and not seen[path] then
        seen[path] = true
        table.insert(paths, path)
      end
    end
  end

  return paths
end

local function resolve_markdown_path(file_part, bufnr)
  local current_path = get_buf_path(bufnr)
  if not current_path then return nil end
  if file_part == "" then return current_path end

  if file_part:match("^%a[%w+.-]*:") then return nil end

  local root = get_root(bufnr)
  local candidate
  if vim.startswith(file_part, "/") then
    candidate = file_exists(file_part) and file_part or (root .. file_part)
  else
    candidate = vim.fs.joinpath(vim.fn.fnamemodify(current_path, ":h"), file_part)
  end
  return file_exists(candidate) and normalize(candidate) or nil
end

local function resolve_wiki_path(file_part, bufnr, callback)
  local current_path = get_buf_path(bufnr)
  if not current_path then return callback(nil, "Current buffer has no file path") end
  if file_part == "" then return callback(current_path) end

  local root = get_root(bufnr)
  local direct_candidates = {}
  if file_part:find("/") or file_part:match("%.md$") then
    table.insert(direct_candidates, vim.fs.joinpath(root, file_part))
    table.insert(direct_candidates, vim.fs.joinpath(vim.fn.fnamemodify(current_path, ":h"), file_part))
    if not file_part:match("%.md$") then
      table.insert(direct_candidates, vim.fs.joinpath(root, file_part .. ".md"))
      table.insert(direct_candidates, vim.fs.joinpath(vim.fn.fnamemodify(current_path, ":h"), file_part .. ".md"))
    end
  end

  for _, candidate in ipairs(direct_candidates) do
    if file_exists(candidate) then return callback(normalize(candidate)) end
  end

  if vim.fn.executable("rg") ~= 1 then return callback(nil, "rg is required to resolve file-stem wikilinks") end

  vim.system({ "rg", "--files", "-g", "*.md", root }, { text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then return callback(nil, "Could not list Markdown files under " .. root) end

      local matches = {}
      for file in result.stdout:gmatch("[^\r\n]+") do
        local full_path = normalize(file)
        if vim.fn.fnamemodify(full_path, ":t:r") == file_part then table.insert(matches, full_path) end
      end

      if #matches == 1 then return callback(matches[1]) end
      if #matches > 1 then return callback(nil, "Ambiguous wikilink stem " .. file_part) end
      callback(nil, "No Markdown file found for wikilink stem " .. file_part)
    end)
  end)
end

local function resolve_path(target, bufnr, callback)
  if target.kind == "markdown" then return callback(resolve_markdown_path(target.file_part, bufnr)) end
  resolve_wiki_path(target.file_part, bufnr, callback)
end

function M.goto_block_id_under_cursor(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local target = block_target_under_cursor(bufnr)
  if not target then return false end

  resolve_path(target, bufnr, function(path, err)
    if not path then
      warn(err or "Could not resolve block target")
      return
    end
    go_to_id(path, target.id)
  end)

  return true
end

function M.goto_block_id(id, root)
  if not id or not id:match("^" .. ID_PATTERN .. "$") then
    warn("Invalid block id " .. vim.inspect(id))
    return false
  end

  root = normalize(root or get_root(vim.api.nvim_get_current_buf()))
  if not root then
    warn("Could not resolve a Markdown workspace root")
    return false
  end

  if vim.fn.executable("rg") ~= 1 then
    warn("rg is required to resolve block ids")
    return false
  end

  local rg_args = { "rg", "--json", "--fixed-strings", "--glob", "*.md" }
  vim.list_extend(rg_args, utils.foam_todo_rg_exclude_args())
  vim.list_extend(rg_args, { "@id " .. id, root })

  vim.system(rg_args, { text = true }, function(result)
    vim.schedule(function()
      if result.code > 1 then
        warn(("Could not search %s: %s"):format(root, vim.trim(result.stderr or "")))
        return
      end

      local paths = rg_match_paths(result.stdout or "")
      table.sort(paths)
      if #paths == 0 then
        warn(("No attached @id %s found under %s"):format(id, vim.fn.fnamemodify(root, ":~")))
        return
      end
      if #paths > 1 then warn(("Multiple files mention @id %s; opening the first attached match"):format(id)) end

      for _, path in ipairs(paths) do
        if go_to_id(path, id, { quiet = true }) then return end
      end
      warn(("No attached @id %s found under %s"):format(id, vim.fn.fnamemodify(root, ":~")))
    end)
  end)

  return true
end

function M.warn_duplicate_ids(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if vim.b[bufnr].large_buf then return end

  local lines = get_buffer_lines(bufnr)
  local ids = {}
  local duplicates = {}
  for lnum, line in ipairs(lines) do
    local id = parse_id_line(line)
    if id and is_attached_to_block(lines, lnum) then
      if ids[id] then
        duplicates[id] = true
      else
        ids[id] = lnum
      end
    end
  end

  local names = vim.tbl_keys(duplicates)
  table.sort(names)
  if #names > 0 then warn("Duplicate ids in this file: " .. table.concat(names, ", ")) end
end

function M.highlight_ids(bufnr, namespace)
  if vim.b[bufnr].large_buf then return end
  local lines = get_buffer_lines(bufnr)
  for lnum, line in ipairs(lines) do
    local id = parse_id_line(line)
    if id then
      local col = line:find(id, 1, true)
      if col then
        vim.api.nvim_buf_set_extmark(bufnr, namespace, lnum - 1, col - 1, {
          end_col = col - 1 + #id,
          hl_group = is_attached_to_block(lines, lnum) and "Identifier" or "DiagnosticUnnecessary",
          priority = 200,
        })
      end
    end
  end
end

function M.filter_marksman_diagnostics(result)
  if not result or not result.uri or not result.diagnostics then return result end

  local lines = get_uri_lines(result.uri)
  if not lines then return result end

  result.diagnostics = vim.tbl_filter(
    function(diagnostic) return not is_block_id_diagnostic(lines, diagnostic) end,
    result.diagnostics
  )

  return result
end

return M
