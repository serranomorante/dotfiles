local M = {}

function M.config()
  require("nvim-web-devicons").setup({
    override = {
      md = {
        icon = "",
      },
    },
  })
end

return M
