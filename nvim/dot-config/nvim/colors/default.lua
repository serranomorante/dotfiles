vim.cmd.highlight("clear")
if vim.fn.exists("syntax_on") then vim.cmd.syntax("reset") end

local background = vim.api.nvim_get_option_value("background", {})
vim.api.nvim_set_option_value("termguicolors", true, {})

---https://github.com/neovim/neovim/pull/26540#issue-2038341661
---https://github.com/neovim/neovim/issues/26857
local bg = background == "dark" and "NvimDark" or "NvimLight"
local fg = bg == "NvimDark" and "NvimLight" or "NvimDark"

---@type table<string, vim.api.keyset.highlight>
local groups = {
  Normal = { fg = fg == "NvimDark" and "Black" or "White", bg = bg == "NvimDark" and "Black" or "White" },
  DiffChange = { bg = bg .. "Grey3" },
  QuickFixLine = { ctermfg = "NONE", fg = "NONE", bg = bg == "NvimDark" and "#1e2e4a" or "#c1cee5" },
  LspInlayHint = { link = "CursorColumn" },
  TabLineSel = { fg = fg .. "Grey1", bg = bg .. "Grey2" },
  Folded = { bg = bg .. "Grey3" },
  MatchParen = { bg = bg .. "Grey3" },
  Number = { fg = fg .. "Yellow" },
  DapBreakpoint = { fg = fg .. "Red" },
  DapLogPoint = { fg = fg .. "Blue" },
  DapStopped = { fg = fg .. "Cyan" },
  OverseerRUNNING = { fg = fg .. "Cyan" },
  OverseerField = { fg = fg .. "Cyan" },
  OverseerComponent = { fg = fg .. "Yellow" },
  OverseerTask = { fg = fg .. "Blue" },
  DiffviewCursorLine = { ctermfg = 14, bg = bg .. "Grey3" },
  FloatingSuggest = { bg = bg .. "Grey3" },
  CocMenuSel = { link = "PmenuSel" },
  CocInlayHint = { link = "CursorColumn" },
  CocCodeLens = { link = "Comment" },
  qfDirName = { link = "Directory", default = true },
  qfFileName = { link = "CursorLineNr", default = true },
  qfSubmatch = { fg = fg .. "Red" },
  qfSeparatorLeft = { fg = bg .. "Grey4" },
  CustomOperatorPending = { bg = fg .. "Blue" },
  CustomDapReplBg = { bg = bg == "NvimDark" and "#192335" or "#b8cef7" },
  CustomEphemeralMsgBg = { bg = bg == "NvimDark" and "#10264d" or "#93abd9" },
  CustomAIChatBg = { bg = bg == "NvimDark" and "#323a50" or "#b7c5ea" },
  CustomAILineNr = { fg = fg .. "Grey4" },
  CustomAerialBg = { bg = bg .. "Grey3" },
  CustomAerialTitle = { fg = fg .. "Cyan", bg = bg .. "Grey3", bold = true },
  DiagnosticUnderlineError = { sp = fg .. "Red", undercurl = true },
  DiagnosticUnderlineWarn = { sp = fg .. "Yellow", undercurl = true },
  DiagnosticUnderlineInfo = { sp = fg .. "Cyan", undercurl = true },
  DiagnosticUnderlineHint = { sp = fg .. "Blue", undercurl = true },
  DiagnosticUnderlineOk = { sp = fg .. "Green", undercurl = true },
  MsgArea = { bg = bg == "NvimDark" and "Black" or "White" },
  ["@markup.heading.2.markdown"] = { fg = fg .. "Green", bg = bg .. "Green", bold = true },
  ["@markup.heading.3.markdown"] = { fg = fg .. "Blue", bg = bg .. "Blue", bold = true },
  ["@markup.heading.4.markdown"] = { fg = fg .. "Yellow", bg = bg .. "Yellow", bold = true },
  ["@markup.heading.5.markdown"] = { fg = fg .. "Cyan", bg = bg .. "Cyan", bold = true },
  ["@OrgHeadlineLevel2"] = { link = "@markup.heading.2.markdown" },
  ["@OrgHeadlineLevel3"] = { link = "@markup.heading.3.markdown" },
  ["@OrgHeadlineLevel4"] = { link = "@markup.heading.4.markdown" },
  ["@OrgHeadlineLevel5"] = { link = "@markup.heading.5.markdown" },
  ["@OrgListBullet"] = { fg = fg .. "Yellow" },
  ["@OrgComment"] = { link = "Comment" },
  ["@OrgDirective"] = { fg = fg .. "Cyan" },
}

vim.g.terminal_color_0 = vim.g.terminal_color_0 or (bg .. "Grey1")
vim.g.terminal_color_8 = vim.g.terminal_color_8 or (bg .. "Grey1")

for group, opts in pairs(groups) do
  vim.api.nvim_set_hl(0, group, opts)
end
