---@type overseer.ComponentFileDefinition
local comp = {
  desc = "Force close if current window is terminal and process exit is 0",
  -- Doesn't make sense for user to add this using a form.
  editable = false,
  constructor = function()
    return {
      ---@param status overseer.Status Can be CANCELED, FAILURE, or SUCCESS
      ---@param result table A result table.
      on_complete = function(self, task, status, result)
        if
          status == require("overseer.parser").STATUS.SUCCESS
          and vim.api.nvim_get_option_value("buftype", { buf = task:get_bufnr() }) == "terminal"
        then
          vim.api.nvim_win_close(0, true)
        end
      end,
    }
  end,
}

return comp
