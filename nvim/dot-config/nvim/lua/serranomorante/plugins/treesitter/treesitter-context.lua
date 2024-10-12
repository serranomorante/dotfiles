local M = {}

local keys = function()
  vim.keymap.set("n", "[c", function() require("treesitter-context").go_to_context(vim.v.count1) end, { silent = true })
end

local opts = function()
  return {
    max_lines = 2,
    trim_scope = "inner", -- outer
    separator = "—",
    on_attach = function(bufnr)
      if vim.b[bufnr].large_buf then return false end
      return nil
    end,
  }
end

M.config = function()
  keys()
  require("treesitter-context").setup(opts())

  ---https://github.com/nvim-treesitter/nvim-treesitter-textobjects?tab=readme-ov-file#text-objects-move
  local ts_repeat_move = require("nvim-treesitter.textobjects.repeatable_move")
  vim.keymap.set({ "n", "x", "o" }, ";", function()
    vim.cmd([[normal! ]] .. "m`") -- set mark
    ts_repeat_move.repeat_last_move()
  end)

  vim.keymap.set({ "n", "x", "o" }, ",", function()
    vim.cmd([[normal! ]] .. "m`") -- set mark
    ts_repeat_move.repeat_last_move_opposite()
  end)

  ---Get the default behaviour again (that behaviour overrided by ts_repeat_move.repeat_last_move)
  vim.keymap.set({ "n", "x", "o" }, "f", function()
    local expression = ts_repeat_move.builtin_f_expr()
    return vim.v.operator ~= "" and expression or "m`" .. vim.v.count1 .. expression
  end, { expr = true })

  vim.keymap.set({ "n", "x", "o" }, "F", function()
    local expression = ts_repeat_move.builtin_F_expr()
    return vim.v.operator ~= "" and expression or "m`" .. vim.v.count1 .. expression
  end, { expr = true })

  vim.keymap.set({ "n", "x", "o" }, "t", function()
    local expression = ts_repeat_move.builtin_t_expr()
    return vim.v.operator ~= "" and expression or "m`" .. vim.v.count1 .. expression
  end, { expr = true })

  vim.keymap.set({ "n", "x", "o" }, "T", function()
    local expression = ts_repeat_move.builtin_T_expr()
    return vim.v.operator ~= "" and expression or "m`" .. vim.v.count1 .. expression
  end, { expr = true })
end

return M
