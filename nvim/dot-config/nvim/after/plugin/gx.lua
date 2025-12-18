local MARKDOWN_FILENAME_PAT = "[^]]*](\\zs/[^)]*\\ze)"

vim.keymap.set("n", "gx", function()
  local line_string = vim.api.nvim_get_current_line()
  local match = vim.fn.matchstr(line_string, MARKDOWN_FILENAME_PAT)
  if match ~= "" then return vim.ui.open("editor://" .. match) end
  vim.api.nvim_echo({ { "Not a valid URI", "DiagnosticWarn" } }, false, {})
end, { desc = "Use custom handlers for gx" })
