vim.go.quickfixtextfunc = "v:lua.user.QuickfixTextFunc"

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
      if vim.list_contains({ "user.grep", "user.helpgrep" }, context.name) and i < 999 then
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
