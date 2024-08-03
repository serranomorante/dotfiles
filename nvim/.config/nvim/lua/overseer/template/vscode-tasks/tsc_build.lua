local utils = require("serranomorante.utils")
if not utils.is_available("overseer.nvim") then return {} end
local overseer = require("overseer")

return {
  name = "tsc: build - tsconfig.json",
  builder = function()
    return {
      cmd = { "tsc" },
      components = {
        { "on_output_parse", problem_matcher = "$tsc" },
        "on_result_diagnostics",
        "on_result_diagnostics_quickfix",
        "default",
      },
    }
  end,
  tags = { overseer.TAG.BUILD },
  condition = {
    filetype = { "typescript" },
  },
}
