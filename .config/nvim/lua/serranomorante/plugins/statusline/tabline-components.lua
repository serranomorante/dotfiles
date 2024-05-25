local heirline_utils = require("heirline.utils")
local components = require("serranomorante.plugins.statusline.components")

local M = {}

-- Here the filename block finally comes together
local TablineFileNameBlock = {
  init = function(self)
    local window = vim.api.nvim_tabpage_get_win(self.tabpage)
    self.bufnr = vim.api.nvim_win_get_buf(window)
    self.filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(self.bufnr), ":t")
    if self.filename == "" then self.filename = "[No Name]" end
  end,
  hl = function(self)
    if self.is_active then
      return "TabLineSel"
    else
      return "TabLine"
    end
  end,
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
