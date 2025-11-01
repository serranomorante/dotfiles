local constants = require("serranomorante.constants")
local utils = require("serranomorante.utils")

if not utils.is_available("overseer") then return {} end
local overseer = require("overseer")

local task_name = "vscode-tasks-tsc-build"

return {
  name = task_name,
  builder = function()
    return {
      name = task_name,
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
    filetype = constants.javascript_aliases,
  },
}
