---Don't increase width if terminal is for preview only (from the overseer task list)
---@param buf integer
local function is_preview(buf) return vim.api.nvim_win_get_config(vim.fn.bufwinid(buf)).row == 1 end

---@type overseer.ComponentFileDefinition
local comp = {
  desc = "Force fullscreen on float",
  -- Doesn't make sense for user to add this using a form.
  editable = false,
  constructor = function()
    return {
      on_init = function(_, task)
        vim.api.nvim_create_autocmd("BufEnter", {
          buffer = task:get_bufnr(),
          callback = function(args)
            if vim.api.nvim_get_option_value("buftype", { buf = args.buf }) ~= "terminal" then return end
            if is_preview(args.buf) then return end
            vim.cmd.wincmd({ "|" })
          end,
        })
      end,
    }
  end,
}

return comp
