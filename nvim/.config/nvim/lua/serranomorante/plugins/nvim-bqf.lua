local M = {}

M.nvim_bqf = {
  "kevinhwang91/nvim-bqf",
  dependencies = {
    {
      ---`junegunn/fzf` vim plugin is necessary because `nvim-bqf` uses `fzf#run(...)`
      ---https://github.com/junegunn/fzf/blob/master/README-VIM.md#summary
      "junegunn/fzf",
      build = ":call fzf#install()",
    },
  },
  ft = "qf",
  init = function()
    ---https://github.com/kevinhwang91/nvim-bqf?tab=readme-ov-file#format-new-quickfix
    vim.o.qftf = "{info -> v:lua._G.qftf(info)}"
  end,
  opts = {
    auto_resize_height = false, -- to stay consistent
    func_map = {
      open = "", -- disable to not conflict with trailblazer
      tabc = "te",
      vsplit = "sv",
      split = "ss",
    },
    preview = {
      winblend = 0,
    },
    filter = {
      fzf = {
        extra_opts = { "--bind", "ctrl-o:toggle-all", "--delimiter", "│" },
      },
    },
  },
}

---https://github.com/kevinhwang91/nvim-bqf?tab=readme-ov-file#format-new-quickfix
function _G.qftf(info)
  local items
  local ret = {}
  if info.quickfix == 1 then
    items = vim.fn.getqflist({ id = info.id, items = 0 }).items
  else
    items = vim.fn.getloclist(info.winid, { id = info.id, items = 0 }).items
  end
  local limit = 50
  local fname_short_fmt, fname_large_fmt = "%-" .. limit .. "s", "…%." .. (limit - 1) .. "s"
  local valid_qf_fmt = "%s │%5d:%-3d│%s %s"
  for i = info.start_idx, info.end_idx do
    local e = items[i]
    local fname = ""
    local str
    if e.bufnr > 0 then
      fname = vim.fn.bufname(e.bufnr)
      if fname == "" then
        fname = "[No Name]"
      else
        fname = fname:gsub("^" .. vim.env.HOME, "~")
      end
      -- char in fname may occur more than 1 width, ignore this issue in order to keep performance
      if #fname <= limit then
        fname = fname_short_fmt:format(fname)
      else
        fname = fname_large_fmt:format(fname:sub(1 - limit))
      end
    end
    local lnum = e.lnum > 99999 and -1 or e.lnum
    local col = e.col > 999 and -1 or e.col
    local qtype = e.type == "" and "" or " " .. e.type:sub(1, 1):upper()
    str = valid_qf_fmt:format(fname, lnum, col, qtype, e.text)
    table.insert(ret, str)
  end
  return ret
end

return M.nvim_bqf
