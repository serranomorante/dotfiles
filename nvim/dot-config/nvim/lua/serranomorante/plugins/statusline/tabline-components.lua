local heirline_utils = require("heirline.utils")
local heirline_conds = require("heirline.conditions")
local components = require("serranomorante.plugins.statusline.components")

local M = {}

-- Here the filename block finally comes together
local TablineFileNameBlock = {
  init = function(self)
    local window = vim.api.nvim_tabpage_get_win(self.tabpage)
    self.bufnr = vim.api.nvim_win_get_buf(window)
    self.bufname = vim.api.nvim_buf_get_name(self.bufnr)
    self.filename = vim.fn.fnamemodify(self.bufname, ":t")
    if vim.fn.empty(self.filename) == 1 then self.filename = "[No Name]" end
    if heirline_conds.buffer_matches({ filetype = { "oil" } }, self.bufnr) then self.filename = "File Explorer" end
    if heirline_conds.buffer_matches({ filetype = { "codecompanion" } }, self.bufnr) then self.filename = "AI" end
    if heirline_conds.buffer_matches({ filetype = { "fzf" } }, self.bufnr) then self.filename = "FZF" end
  end,
  static = {
    context = {
      view = "tabline",
    },
  },
  hl = function(self) return self.is_active and "TabLineSel" or "TabLine" end,
  heirline_utils.insert(
    components.FileIcon,
    heirline_utils.insert(components.FileNameModifier, components.FileName),
    components.FileFlags,
    { provider = "%<" }
  ),
}

local Tabpage = {
  provider = function(self) return "%" .. self.tabnr .. "T " .. self.tabnr .. " %T" end,
  hl = function(self)
    if not self.is_active then
      return "TabLine"
    else
      return "TabLineSel"
    end
  end,
  TablineFileNameBlock,
  components.Space,
}

local TabpageClose = {
  provider = "%999X 󰅙 %X",
  hl = "TabLine",
}

M.TabPages = {
  heirline_utils.make_tablist(Tabpage),
  { provider = "%=" },
  TabpageClose,
}

return M
