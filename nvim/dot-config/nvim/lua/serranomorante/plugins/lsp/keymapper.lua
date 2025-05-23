local keymap_prefix = "LSP:"

local M = {}

---@param bufnr integer
---@return fun(string): table
function M.opts_for(bufnr)
  return function(desc) return { buffer = bufnr, desc = keymap_prefix .. " " .. desc } end
end

---@param bufnr integer
function M.clear(bufnr)
  for _, mode in ipairs({ "n", "i", "v" }) do
    ---@type vim.api.keyset.keymap
    local keymaps = vim.api.nvim_buf_get_keymap(bufnr, mode)
    for _, keymap in ipairs(keymaps) do
      if keymap.desc and keymap.lhs then
        if vim.startswith(keymap.desc, keymap_prefix) then vim.api.nvim_buf_del_keymap(bufnr, mode, keymap.lhs) end
      end
    end
  end
end

return M
