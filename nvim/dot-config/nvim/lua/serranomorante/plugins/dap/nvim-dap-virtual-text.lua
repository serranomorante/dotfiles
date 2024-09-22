local constants = require("serranomorante.constants")

local M = {}

local opts = function()
  ---@type nvim_dap_virtual_text_options
  return {
    highlight_new_as_changed = true,
    display_callback = function(variable, buf, stackframe, node, options)
      local filetype = vim.api.nvim_get_option_value("filetype", { buf = buf })
      if vim.list_contains(constants.javascript_aliases, filetype) then
        if variable.type == "Function" then return " = " .. string.format("%.10s%s", variable.value, "…") end
      end
      ---by default, strip out new line characters
      if options.virt_text_pos == "inline" then
        return " = " .. variable.value:gsub("%s+", " ")
      else
        return variable.name .. " = " .. variable.value:gsub("%s+", " ")
      end
    end,
  }
end

M.config = function() require("nvim-dap-virtual-text").setup(opts()) end

return M
