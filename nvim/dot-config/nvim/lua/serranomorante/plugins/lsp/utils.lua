local M = {}

---Rules to detect if we should enable lsp for a buffer
---@param bufnr integer
---@return boolean
function M.should_enable(bufnr)
  local enable = true
  if vim.api.nvim_get_option_value("diff", { scope = "local" }) then
    enable = false -- prevent conflict with diffview
  end
  if vim.list_contains({ "nowrite", "nofile" }, vim.api.nvim_get_option_value("buftype", { buf = bufnr })) then
    enable = false -- not a valid buftype
  end
  return enable
end

return M
