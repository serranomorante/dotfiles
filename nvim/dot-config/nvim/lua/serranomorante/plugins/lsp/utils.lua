local tools = require("serranomorante.tools")

local M = {}

local MARKSMAN_ROOT_MARKERS = { ".marksman.toml", ".git" }
local MARKSMAN_EXCLUDED_ROOTS = {
  vim.fn.expand("~/dotfiles/for-my-eyes-only"),
}

local function normalize_path(path)
  if not path or path == "" then return "" end
  local real = vim.uv.fs_realpath(path)
  local normalized = real or vim.fn.fnamemodify(vim.fn.expand(path), ":p")
  normalized = normalized:gsub("/+$", "")
  return normalized == "" and "/" or normalized
end

local function path_is_under(path, root)
  local normalized_path = normalize_path(path)
  local normalized_root = normalize_path(root)
  return normalized_path == normalized_root or normalized_path:sub(1, #normalized_root + 1) == normalized_root .. "/"
end

---Check if buffer's filetype is compatible with any available lsp tooling
---@param bufnr integer
---@return boolean
function M.has_lsp_server_available(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
  local filetype_tools = vim.tbl_get(tools.by_filetype, filetype, "lsp") or {}
  return vim.tbl_count(filetype_tools) > 0
end

---@param bufnr integer
---@return boolean
function M.should_enable_marksman(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not M.should_enable(bufnr) then return false end

  local bufname = vim.api.nvim_buf_get_name(bufnr)
  if bufname == "" then return false end

  local root = vim.fs.root(bufname, MARKSMAN_ROOT_MARKERS)
  if not root then return false end

  for _, excluded_root in ipairs(MARKSMAN_EXCLUDED_ROOTS) do
    if path_is_under(root, excluded_root) then return false end
  end

  return true
end

---Rules to detect if we should enable lsp for a buffer
---@param bufnr integer
---@return boolean
function M.should_enable(bufnr)
  local enable = false
  if vim.g.lsp_enabled == false then return false end
  if M.has_lsp_server_available(bufnr) then enable = true end
  if vim.b[bufnr].persistent_scratch_disable_lsp then enable = false end
  if vim.api.nvim_get_option_value("diff", { scope = "local" }) then
    enable = false -- prevent conflict with diffview
  end
  if vim.list_contains({ "nowrite", "nofile" }, vim.api.nvim_get_option_value("buftype", { buf = bufnr })) then
    enable = false -- not a valid buftype
  end
  return enable
end

---@param configs string|string[]
---@param bufnr integer
function M.enable(configs, bufnr)
  if M.should_enable(bufnr) then
    vim.lsp.enable(configs)
    vim.api.nvim_exec_autocmds("FileType", { group = "nvim.lsp.enable" })
  else
    require("serranomorante.plugins.nvim-ufo").config()
  end
end

return M
