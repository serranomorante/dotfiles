local constants = require("serranomorante.constants")
local utils = require("serranomorante.utils")
if not utils.is_available("overseer") then return {} end
local overseer = require("overseer")

local task_name = "vscode-tasks-tsc-build"

return {
  name = task_name,
  builder = function()
    local session_name = task_name .. vim.fn.fnameescape(vim.v.servername)
    return {
      cmd = { "tmux" },
      args = utils.wrap_overseer_args_with_tmux({ "tsc" }, session_name),
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
