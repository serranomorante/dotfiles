local ts = vim.treesitter

local M = {}

-- Vendored from nvim-treesitter until Neovim exposes a native indentexpr.
M.comment_parsers = {
  comment = true,
  javadoc = true,
  jsdoc = true,
  luadoc = true,
  phpdoc = true,
}

local function getline(lnum) return vim.api.nvim_buf_get_lines(0, lnum - 1, lnum, false)[1] or "" end

---@param lnum integer
---@return integer
local function get_indentcols_at_line(lnum)
  local _, indentcols = getline(lnum):find("^%s*")
  return indentcols or 0
end

---@param root TSNode
---@param lnum integer
---@param col? integer
---@return TSNode?
local function get_first_node_at_line(root, lnum, col)
  col = col or get_indentcols_at_line(lnum)
  return root:descendant_for_range(lnum - 1, col, lnum - 1, col + 1)
end

---@param root TSNode
---@param lnum integer
---@param col? integer
---@return TSNode?
local function get_last_node_at_line(root, lnum, col)
  col = col or (#getline(lnum) - 1)
  return root:descendant_for_range(lnum - 1, col, lnum - 1, col + 1)
end

---@param bufnr integer
---@param node TSNode
---@param delimiter string
---@return TSNode? child
---@return boolean? is_end
local function find_delimiter(bufnr, node, delimiter)
  for child, _ in node:iter_children() do
    if child:type() == delimiter then
      local linenr = child:start()
      local line = vim.api.nvim_buf_get_lines(bufnr, linenr, linenr + 1, false)[1]
      local _, end_col = child:end_()
      local escaped_delimiter = delimiter:gsub("[%-%.%+%[%]%(%)%$%^%%%?%*]", "%%%1")
      local trimmed_after_delim = assert(line):sub(end_col + 1):gsub("[%s" .. escaped_delimiter .. "]*", "")
      return child, #trimmed_after_delim == 0
    end
  end
end

---@generic F: function
---@param fn F
---@param hash_fn fun(...): any
---@return F
local function memoize(fn, hash_fn)
  local cache = setmetatable({}, { __mode = "kv" })

  return function(...)
    local key = hash_fn(...)
    if cache[key] == nil then
      local v = fn(...)
      cache[key] = v ~= nil and v or vim.NIL
    end

    local v = cache[key]
    return v ~= vim.NIL and v or nil
  end
end

local get_indents = memoize(function(bufnr, root, lang)
  ---@type table<string,table<string,table>>
  local map = {
    ["indent.align"] = {},
    ["indent.auto"] = {},
    ["indent.begin"] = {},
    ["indent.branch"] = {},
    ["indent.dedent"] = {},
    ["indent.end"] = {},
    ["indent.ignore"] = {},
    ["indent.zero"] = {},
  }

  local query = ts.query.get(lang, "indents")
  if not query then return map end

  for id, node, metadata in query:iter_captures(root, bufnr) do
    if assert(query.captures[id]):sub(1, 1) ~= "_" then map[query.captures[id]][node:id()] = metadata or {} end
  end

  return map
end, function(bufnr, root, lang) return tostring(bufnr) .. root:id() .. "_" .. lang end)

---@param lnum integer
---@return integer
function M.get_indent(lnum)
  local bufnr = vim.api.nvim_get_current_buf()
  local parser = ts.get_parser(bufnr)
  if not parser or not lnum then return -1 end

  parser:parse({ vim.fn.line("w0") - 1, vim.fn.line("w$") })

  local root, lang_tree ---@type TSNode, vim.treesitter.LanguageTree
  parser:for_each_tree(function(tstree, tree)
    if not tstree or M.comment_parsers[tree:lang()] then return end
    local local_root = tstree:root()
    if ts.is_in_node_range(local_root, lnum - 1, 0) then
      if not root or root:byte_length() >= local_root:byte_length() then
        root = local_root
        lang_tree = tree
      end
    end
  end)

  if not root then return 0 end

  local q = get_indents(bufnr, root, lang_tree:lang())
  local node ---@type TSNode?
  if getline(lnum):find("^%s*$") then
    local prevlnum = vim.fn.prevnonblank(lnum)
    local indentcols = get_indentcols_at_line(prevlnum)
    local prevline = vim.trim(getline(prevlnum))
    node = get_last_node_at_line(root, prevlnum, indentcols + #prevline - 1)
    if node and node:type():match("comment") then
      local first_node = get_first_node_at_line(root, prevlnum, indentcols)
      local _, scol = node:range()
      if first_node and first_node:id() ~= node:id() then
        prevline = vim.trim(prevline:sub(1, scol - indentcols))
        node = get_last_node_at_line(root, prevlnum, indentcols + #prevline - 1)
      end
    end
    if node and q["indent.end"][node:id()] then node = get_first_node_at_line(root, lnum) end
  else
    node = get_first_node_at_line(root, lnum)
  end

  local indent_size = vim.fn.shiftwidth()
  local indent = 0
  local _, _, root_start = root:start()
  if root_start ~= 0 then indent = vim.fn.indent(root:start() + 1) end

  local is_processed_by_row = {} ---@type table<integer,boolean>

  if node and q["indent.zero"][node:id()] then return 0 end

  while node do
    if
      not q["indent.begin"][node:id()]
      and not q["indent.align"][node:id()]
      and q["indent.auto"][node:id()]
      and node:start() < lnum - 1
      and lnum - 1 <= node:end_()
    then
      return -1
    end

    if
      not q["indent.begin"][node:id()]
      and q["indent.ignore"][node:id()]
      and node:start() < lnum - 1
      and lnum - 1 <= node:end_()
    then
      return 0
    end

    local srow, _, erow = node:range()
    local is_processed = false

    if
      not is_processed_by_row[srow]
      and ((q["indent.branch"][node:id()] and srow == lnum - 1) or (q["indent.dedent"][node:id()] and srow ~= lnum - 1))
    then
      indent = indent - indent_size
      is_processed = true
    end

    local should_process = not is_processed_by_row[srow]
    local is_in_err = false
    if should_process then
      local parent = node:parent()
      is_in_err = parent and parent:has_error() or false
    end
    if
      should_process
      and (
        q["indent.begin"][node:id()]
        and (srow ~= erow or is_in_err or q["indent.begin"][node:id()]["indent.immediate"])
        and (srow ~= lnum - 1 or q["indent.begin"][node:id()]["indent.start_at_same_line"])
      )
    then
      indent = indent + indent_size
      is_processed = true
    end

    if is_in_err and not q["indent.align"][node:id()] then
      for child in node:iter_children() do
        if q["indent.align"][child:id()] then
          q["indent.align"][node:id()] = q["indent.align"][child:id()]
          break
        end
      end
    end

    if should_process and q["indent.align"][node:id()] and (srow ~= erow or is_in_err) and srow ~= lnum - 1 then
      local metadata = q["indent.align"][node:id()]
      local open_delim_node, open_is_last_in_line ---@type TSNode?, boolean?
      local close_delim_node, close_is_last_in_line ---@type TSNode?, boolean?
      local indent_is_absolute = false

      if metadata["indent.open_delimiter"] then
        open_delim_node, open_is_last_in_line = find_delimiter(bufnr, node, metadata["indent.open_delimiter"])
      else
        open_delim_node = node
      end
      if metadata["indent.close_delimiter"] then
        close_delim_node, close_is_last_in_line = find_delimiter(bufnr, node, metadata["indent.close_delimiter"])
      else
        close_delim_node = node
      end

      if open_delim_node then
        local open_row, open_col = open_delim_node:start()
        local close_row = close_delim_node and select(1, close_delim_node:start()) or nil

        if open_is_last_in_line then
          indent = indent + indent_size
          if close_is_last_in_line and close_row and close_row < lnum - 1 then
            indent = math.max(indent - indent_size, 0)
          end
        else
          if close_is_last_in_line and close_row and open_row ~= close_row and close_row < lnum - 1 then
            indent = math.max(indent - indent_size, 0)
          else
            indent = open_col + (metadata["indent.increment"] or 1)
            indent_is_absolute = true
          end
        end

        if
          close_row
          and close_row ~= open_row
          and close_row == lnum - 1
          and metadata["indent.avoid_last_matching_next"]
        then
          if indent <= vim.fn.indent(open_row + 1) + indent_size then indent = indent + indent_size end
        end

        is_processed = true
        if indent_is_absolute then return indent end
      end
    end

    is_processed_by_row[srow] = is_processed_by_row[srow] or is_processed
    node = node:parent()
  end

  return indent
end

function M.expr() return M.get_indent(vim.v.lnum) end

return M
