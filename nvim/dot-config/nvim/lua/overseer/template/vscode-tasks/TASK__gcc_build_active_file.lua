local utils = require("serranomorante.utils")
if not utils.is_available("overseer") then return {} end
local overseer = require("overseer")
local variables = require("overseer.template.vscode.variables")

local task_name = "vscode-tasks-gcc-build-active-file"

---Emulates the default `C/C++: gcc build active file` vscode task on lua
return {
  name = task_name,
  desc = "Build active file into executable of the same name without extension",
  builder = function()
    local precalculated_vars = variables.precalculate_vars()
    local command = {
      "/usr/bin/gcc",
      "-fdiagnostics-color=always",
      "-g",
      precalculated_vars.file,
      "-o",
      precalculated_vars.fileDirname .. "/" .. precalculated_vars.fileBasenameNoExtension,
    }
    return {
      name = task_name,
      cmd = { "tmux" },
      args = utils.wrap_overseer_args_with_tmux(command, { session_name = task_name, retain_shell = true }),
      components = {
        "defaults_without_notification",
      },
    }
  end,
  condition = {
    filetype = { "c", "cpp" },
  },
  tags = { overseer.TAG.BUILD },
}
