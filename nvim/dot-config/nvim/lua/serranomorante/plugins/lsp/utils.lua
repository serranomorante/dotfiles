local tools = require("serranomorante.tools")

local M = {}

---Check if buffer's filetype is compatible with any available lsp tooling
---@param bufnr integer
---@return boolean
function M.has_lsp_server_available(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
  local filetype_tools = vim.tbl_get(tools.by_filetype, filetype, "lsp") or {}
  return vim.tbl_count(filetype_tools) > 0
end

---Rules to detect if we should enable lsp for a buffer
---@param bufnr integer
---@return boolean
function M.should_enable(bufnr)
  local enable = false
  if M.has_lsp_server_available(bufnr) then enable = true end
  if vim.api.nvim_get_option_value("diff", { scope = "local" }) then
    enable = false -- prevent conflict with diffview
  end
  if vim.list_contains({ "nowrite", "nofile" }, vim.api.nvim_get_option_value("buftype", { buf = bufnr })) then
    enable = false -- not a valid buftype
  end
  return enable
end

return M
