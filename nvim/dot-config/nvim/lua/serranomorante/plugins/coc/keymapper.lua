local keymap_prefix = "COC:"

local M = {}

---@param bufnr integer
---@return fun(string): vim.keymap.set.Opts
M.opts_for = function(bufnr)
  return function(desc)
    return {
      buffer = bufnr,
      desc = keymap_prefix .. " " .. desc,
    }
  end
end

return M
