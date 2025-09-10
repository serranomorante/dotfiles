vim.cmd.highlight("clear")
if vim.fn.exists("syntax_on") then vim.cmd.syntax("reset") end

vim.g.colors_name = "default"
vim.o.background = "dark"
vim.o.termguicolors = true

---https://github.com/neovim/neovim/pull/26540#issue-2038341661
---https://github.com/neovim/neovim/issues/26857
local bg = vim.o.background == "dark" and "NvimDark" or "NvimLight"
local fg = bg == "NvimDark" and "NvimLight" or "NvimDark"

---@type table<string, vim.api.keyset.highlight>
local groups = {
  ---Builtin
  DiffChange = { bg = bg .. "Grey3" },
  QuickFixLine = { ctermfg = "NONE", fg = "NONE", bg = "#1e2e4a" },
  LspInlayHint = { link = "CursorColumn" },
  TabLineSel = { fg = "White", bg = bg .. "Grey2" },
  Folded = { bg = bg .. "Grey3" },
  MatchParen = { bg = bg .. "Grey3" },
  MatchWord = { bg = bg .. "Grey3" },
  Number = { fg = "Yellow" },
  ---LSP
  LspCodeLens = { link = "Comment" },
  ---DAP
  DapBreakpoint = { fg = fg .. "Red" },
  DapLogPoint = { fg = fg .. "Blue" },
  DapStopped = { fg = fg .. "Cyan" },
  ---Aerial
  AerialLine = { fg = fg .. "Cyan", ctermfg = 14, bg = bg .. "Grey3" },
  ---Overseer
  OverseerRUNNING = { fg = fg .. "Cyan" },
  OverseerField = { fg = fg .. "Cyan" },
  OverseerComponent = { fg = fg .. "Yellow" },
  OverseerTask = { fg = fg .. "Blue" },
  ---Diffview
  DiffviewCursorLine = { ctermfg = 14, bg = bg .. "Grey3" },
  CocFloatingSuggest = { bg = bg .. "Grey3" },
  qfDirName = { link = "Directory", default = true },
  qfFileName = { link = "CursorLineNr", default = true },
  qfSubmatch = { fg = fg .. "Red" },
  qfSeparatorLeft = { fg = bg .. "Grey4" },
  CustomOperatorPending = { bg = fg .. "Blue" },
  CustomDapReplBg = { bg = "#192335" },
  CustomAIChatBg = { bg = "#323a50" },
  CustomAerialBg = { bg = "#242529" },
  DiagnosticUnderlineError = { sp = fg .. "Red", undercurl = true },
  DiagnosticUnderlineWarn = { sp = fg .. "Yellow", undercurl = true },
  DiagnosticUnderlineInfo = { sp = fg .. "Cyan", undercurl = true },
  DiagnosticUnderlineHint = { sp = fg .. "Blue", undercurl = true },
  DiagnosticUnderlineOk = { sp = fg .. "Green", undercurl = true },
  MsgArea = { bg = "Black" },
  ["@markup.heading.2.markdown"] = { fg = fg .. "Green", bg = bg .. "Green", bold = true },
  ["@markup.heading.3.markdown"] = { fg = fg .. "Blue", bg = bg .. "Blue", bold = true },
  ["@markup.heading.4.markdown"] = { fg = fg .. "Yellow", bg = bg .. "Yellow", bold = true },
  ["@markup.heading.5.markdown"] = { fg = fg .. "Cyan", bg = bg .. "Cyan", bold = true },
}

vim.g.terminal_color_0 = vim.g.terminal_color_0 or (bg .. "Grey1")
vim.g.terminal_color_8 = vim.g.terminal_color_8 or (bg .. "Grey1")

for group, opts in pairs(groups) do
  vim.api.nvim_set_hl(0, group, opts)
end
