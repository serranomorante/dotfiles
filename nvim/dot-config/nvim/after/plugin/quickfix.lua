vim.go.quickfixtextfunc = "v:lua.user.QuickfixTextFunc"

local history_group = vim.api.nvim_create_augroup("user.quickfix_history", { clear = true })

local function history_file()
  if vim.o.shadafile == "" or vim.o.shadafile == "NONE" then return nil end
  return vim.fn.fnamemodify(vim.o.shadafile, ":r") .. ".quickfix.json"
end

local function serializable_item(item)
  local copy = vim.deepcopy(item)
  local bufnr = copy.bufnr
  if bufnr and bufnr > 0 and vim.api.nvim_buf_is_valid(bufnr) then
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= "" then copy.filename = name end
  end
  copy.bufnr = nil
  return copy
end

local function save_history()
  local file = history_file()
  if not file then return end

  local data = { version = 1, current = vim.fn.getqflist({ nr = 0 }).nr, lists = {} }
  for nr = 1, vim.fn.getqflist({ nr = "$" }).nr do
    local qf = vim.fn.getqflist({ nr = nr, title = 0, items = 0, idx = 0, context = 0, quickfixtextfunc = 0 })
    local items = vim.tbl_map(serializable_item, qf.items or {})
    table.insert(data.lists, {
      title = qf.title,
      idx = qf.idx,
      context = qf.context,
      quickfixtextfunc = qf.quickfixtextfunc ~= "" and qf.quickfixtextfunc or nil,
      items = items,
    })
  end

  local ok, encoded = pcall(vim.json.encode, data)
  if ok then
    vim.fn.mkdir(vim.fn.fnamemodify(file, ":h"), "p")
    pcall(vim.fn.writefile, { encoded }, file)
  end
end

local function restore_history()
  local file = history_file()
  if not file or vim.fn.filereadable(file) == 0 or vim.fn.getqflist({ nr = "$" }).nr > 0 then return end

  local ok, lines = pcall(vim.fn.readfile, file)
  if not ok or #lines == 0 then return end

  local decoded, data = pcall(vim.json.decode, table.concat(lines, "\n"))
  if not decoded or type(data) ~= "table" or data.version ~= 1 or type(data.lists) ~= "table" then return end

  local first = math.max(1, #data.lists - vim.go.chistory + 1)
  for nr = first, #data.lists do
    local qf = data.lists[nr]
    if type(qf) == "table" and type(qf.items) == "table" then
      vim.fn.setqflist({}, " ", {
        title = qf.title or "",
        idx = qf.idx or 1,
        context = qf.context or "",
        quickfixtextfunc = qf.quickfixtextfunc or "",
        items = qf.items,
      })
    end
  end

  local current = tonumber(data.current) and tonumber(data.current) - first + 1
  if current and current > 0 and current <= vim.fn.getqflist({ nr = "$" }).nr then
    pcall(vim.cmd, "silent " .. current .. "chistory")
  end
end

vim.api.nvim_create_autocmd("VimEnter", { group = history_group, callback = restore_history })
vim.api.nvim_create_autocmd("VimLeavePre", { group = history_group, callback = save_history })
restore_history()

local function init() vim.wo.wrap = false end

local function echo_stack_warn(direction)
  local msg = "At the %s of the quickfix stack"
  vim.api.nvim_echo({ { msg:format(direction), "DiagnosticWarn" } }, false, {})
end

---@param opts table
local function keys(opts)
  vim.keymap.set("n", ">", function()
    local ok, _ = pcall(vim.cmd.cnewer)
    if not ok then return echo_stack_warn("top") end
  end, { desc = "Go to next quickfix in history", nowait = true, buffer = opts.buf })
  vim.keymap.set("n", "<", function()
    local ok, _ = pcall(vim.cmd.colder)
    if not ok then return echo_stack_warn("bottom") end
  end, { desc = "Go to previous quickfix in history", nowait = true, buffer = opts.buf })
end

---@param syntax_regions string[]
local function generate_region_syntax(syntax_regions)
  local cmd = [[
      syntax clear
      %s
      syntax match qfFileName oneline "^[^\|]*\ze" nextgroup=qfSeparatorLeft
      syntax match qfDirName oneline "^\S*/\ze[^\|]*" nextgroup=qfFileName
      syntax match qfFileName oneline "[^\|]*\ze" contained nextgroup=qfSeparatorLeft
      syntax match qfSeparatorLeft oneline "|[^\|]*|" contained
      setlocal cursorline
      setlocal cursorlineopt=line
      setlocal signcolumn=no
      let b:current_syntax = 'qf'
    ]]
  vim.cmd(cmd:format(vim.fn.join(syntax_regions, "\n")))
end

---@class QfInfo
---@field id integer
---@field end_idx integer
---@field start_idx integer
---@field winid integer
---@field quickfix integer

---@param info QfInfo
function _G.user.QuickfixTextFunc(info)
  local qf
  if info.quickfix == 1 then
    qf = vim.fn.getqflist({ id = info.id, items = 0, context = 0 })
  else
    qf = vim.fn.getloclist(info.winid, { id = info.id, items = 0, context = 0 })
  end
  ---@type vim.quickfix.entry[]
  local items = qf.items
  local context = qf.context or { name = "" }
  ---@type string[], string[]
  local entries, syntax_entries = {}, {}
  local qf_prefix, qf_final, qf_syntax_region = "", "", ""
  local qf_prefix_format = "%s | %d:%d |%s "
  local qf_syntax_region_format = [[syn region qfSubmatch start="\%%%dl\%%%dc" end="\%%%dl\%%%dc"]]
  for i = info.start_idx, info.end_idx do
    ---@type vim.quickfix.entry
    local item = items[i]
    local filename = ""
    if item.valid then
      if item.bufnr > 0 then
        filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(item.bufnr), ":.")
        filename = filename:gsub("^" .. vim.env.HOME, "~")
      else
        qf_prefix = item.text
      end
      local lnum = item.lnum > 99999 and -1 or item.lnum
      local col = item.col > 999 and -1 or item.col
      local qf_type = item.type == "" and "" or " " .. item.type:sub(1, 1):upper()
      qf_prefix = qf_prefix_format:format(filename, lnum, col, qf_type)
      qf_final = qf_prefix .. item.text
      ---perf: avoid dealing with submatches after N rows
      if vim.list_contains({ "user.grep", "user.helpgrep" }, context.name) and i < 999 and col >= 0 then
        qf_syntax_region = qf_syntax_region_format:format(i, #qf_prefix + item.col, i, #qf_prefix + item.end_col + 1)
        table.insert(syntax_entries, qf_syntax_region)
      end
    else
      qf_final = item.text
    end
    table.insert(entries, qf_final)
  end
  ---Feels weird to create autocmd here, but it's fine for now.
  vim.api.nvim_create_autocmd("BufWinEnter", {
    desc = "Set dynamic syntax highlights for quickfix buffers",
    group = vim.api.nvim_create_augroup("user.quickfix", { clear = true }),
    pattern = "quickfix",
    callback = function(args)
      init()
      keys(args)
      generate_region_syntax(syntax_entries)
    end,
  })
  return entries
end
