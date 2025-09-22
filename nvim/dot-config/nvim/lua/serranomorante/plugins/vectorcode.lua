local M = {}

local function opts()
  ---@type VectorCode.Opts
  return {
    notify = true,
    n_query = 3,
    async_opts = {
      n_query = 3,
    },
  }
end

function M.config() require("vectorcode").setup(opts()) end

return M
