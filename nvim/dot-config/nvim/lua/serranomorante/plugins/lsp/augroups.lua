local M = {}

---Client id to group id mapping
local augroups = {}

---@param client vim.lsp.Client
---@return integer
function M.get_augroup(client)
  if not augroups[client.id] then
    local group_name = "personal-lsp-" .. client.name .. "-" .. client.id
    local group = vim.api.nvim_create_augroup(group_name, { clear = true })
    augroups[client.id] = group
    return group
  end
  return augroups[client.id]
end

---@param augroup integer
---@param bufnr integer
local function del_autocmds_for_buf(augroup, bufnr)
  local aucmds = vim.api.nvim_get_autocmds({
    group = augroup,
    buffer = bufnr,
  })
  for _, aucmd in ipairs(aucmds) do
    if aucmd.id then vim.api.nvim_del_autocmd(aucmd.id) end
  end
end

---@param client vim.lsp.Client
---@param bufnr integer
function M.del_autocmds_for_buf(client, bufnr)
  local augroup = M.get_augroup(client)
  del_autocmds_for_buf(augroup, bufnr)
end

return M
