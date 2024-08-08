vim.cmd.highlight("clear")
if vim.fn.exists("syntax_on") then vim.cmd.syntax("reset") end

vim.g.colors_name = "default"
vim.o.background = "dark"
vim.o.termguicolors = true

---https://github.com/neovim/neovim/pull/26540#issue-2038341661
---https://github.com/neovim/neovim/issues/26857
local bg = vim.o.background == "dark" and "NvimDark" or "NvimLight"
local fg = bg == "NvimDark" and "NvimLight" or "NvimDark"

local groups = {
  ---Builtin
  DiffChange = { bg = bg .. "Grey3" },
  QuickFixLine = { ctermfg = "NONE", fg = "NONE", bold = true, bg = bg .. "Blue" },
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
  ---nvim-bqf
  BqfPreviewThumb = { link = "PmenuSel" },
  ---Diffview
  DiffviewCursorLine = { ctermfg = 14, bg = bg .. "Grey3" },
}

vim.g.terminal_color_0 = vim.g.terminal_color_0 or (bg .. "Grey1")
vim.g.terminal_color_8 = vim.g.terminal_color_8 or (bg .. "Grey1")

for group, opts in pairs(groups) do
  vim.api.nvim_set_hl(0, group, opts)
end
