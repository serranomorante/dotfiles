local M = {}

local function keys()
  vim.keymap.set("n", "[c", function() require("treesitter-context").go_to_context(vim.v.count1) end, { silent = true })
end

---@return TSContext.UserConfig
local function opts()
  return {
    max_lines = 4,
    trim_scope = "inner", -- outer
    separator = "—",
    on_attach = function(bufnr)
      if vim.b[bufnr].large_buf then return false end
      return nil
    end,
  }
end

function M.config()
  keys()
  require("treesitter-context").setup(opts())

  ---https://github.com/nvim-treesitter/nvim-treesitter-textobjects?tab=readme-ov-file#text-objects-move
  local ts_repeat_move = require("nvim-treesitter-textobjects.repeatable_move")
  vim.keymap.set({ "n", "x", "o" }, ";", function()
    vim.cmd([[normal! ]] .. "m`") -- set mark
    ts_repeat_move.repeat_last_move()
  end)

  vim.keymap.set({ "n", "x", "o" }, ",", function()
    vim.cmd([[normal! ]] .. "m`") -- set mark
    ts_repeat_move.repeat_last_move_opposite()
  end)

  ---Get the default behaviour again (that behaviour overrided by ts_repeat_move.repeat_last_move)
  for _, operator in ipairs({ "f", "F", "t", "T" }) do
    vim.keymap.set({ "n", "x", "o" }, operator, function()
      local expression = ts_repeat_move[string.format("builtin_%s_expr", operator)]()
      return (vim.api.nvim_get_mode().mode == "niI" or vim.v.operator ~= "") and expression
        or string.format("m`%d%s", vim.v.count1, expression)
    end, { expr = true })
  end

  local function hl()
    local background = vim.api.nvim_get_option_value("background", {}) == "dark" and "NvimDark" or "NvimLight"
    vim.api.nvim_set_hl(0, "TreesitterContextLineNumber", { bg = background .. "Grey1" })
  end
  vim.api.nvim_create_autocmd("OptionSet", {
    desc = "Reload on vim.o.background change",
    group = vim.api.nvim_create_augroup("treesitter-context-hl", { clear = true }),
    pattern = "background",
    callback = hl,
  })
  hl()
end

return M
