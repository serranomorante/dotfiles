vim.cmd.highlight("clear")
if vim.fn.exists("syntax_on") then vim.cmd.syntax("reset") end

vim.g.colors_name = "default"
vim.o.background = "dark"
vim.o.termguicolors = true

local palette = {
  red = "#C94F6D",
  blue = "#719CD6",
  cyan = "#63CDCF",
}

local groups = {
  StatusLine = { link = "CursorLine" },
  ---LSP
  LspCodeLens = { link = "Comment" },
  ---DAP
  DapBreakpoint = { fg = palette.red },
  DapLogPoint = { fg = palette.blue },
  DapStopped = { fg = palette.cyan },
}

for group, opts in pairs(groups) do
  vim.api.nvim_set_hl(0, group, opts)
end
