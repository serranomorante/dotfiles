local keymap_prefix = "COC:"

local M = {}

---@param bufnr integer
---@return fun(string): vim.keymap.set.Opts
function M.opts_for(bufnr)
  return function(desc)
    return {
      buffer = bufnr,
      desc = keymap_prefix .. " " .. desc,
      silent = true,
    }
  end
end

return M
