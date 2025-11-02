---Don't increase width if terminal is for preview only (from the overseer task list)
---@param buf integer
local function is_preview(buf) return vim.api.nvim_win_get_config(vim.fn.bufwinid(buf)).row == 1 end

---@type overseer.ComponentFileDefinition
local comp = {
  desc = "Dispose task if still running after window closes",
  -- Doesn't make sense for user to add this using a form.
  editable = false,
  constructor = function()
    return {
      ---@param data string[] Output of process. See :help channel-lines
      on_output = function(self, task, data)
        vim.api.nvim_create_autocmd("WinLeave", {
          desc = "Dispose task if still running after window closes",
          buffer = task:get_bufnr(),
          callback = function(args)
            if is_preview(args.buf) then return end
            if vim.api.nvim_get_option_value("buftype", { buf = args.buf }) ~= "terminal" then return end
            if task.status == require("overseer.parser").STATUS.RUNNING then task:dispose(true) end
          end,
        })
      end,
    }
  end,
}

return comp
