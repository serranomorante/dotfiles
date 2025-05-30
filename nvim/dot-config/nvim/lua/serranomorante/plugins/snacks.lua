local M = {}

---@return snacks.config
local function opts()
  return {
    ---@type snacks.picker.Config
    picker = {
      enabled = true,
      ui_select = true,
      layout = {
        fullscreen = true,
      },
      formatters = {
        file = {
          filename_first = true,
        },
      },
    },
  }
end

function M.config() require("snacks").setup(opts()) end

return M
