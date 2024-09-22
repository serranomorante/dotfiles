local utils = require("serranomorante.utils")
if not utils.is_available("overseer") then return {} end
local overseer = require("overseer")
local variables = require("overseer.template.vscode.variables")

---Emulates the default `C/C++: gcc build active file` vscode task on lua
return {
  name = "vscode-tasks: C/C++: gcc build active file",
  desc = "Build active file into executable of the same name without extension",
  builder = function()
    local precalculated_vars = variables.precalculate_vars()
    return {
      cmd = { "/usr/bin/gcc" },
      args = {
        "-fdiagnostics-color=always",
        "-g",
        precalculated_vars.file,
        "-o",
        precalculated_vars.fileDirname .. "/" .. precalculated_vars.fileBasenameNoExtension,
      },
      components = {
        { "on_output_quickfix", open = false },
        "default",
      },
    }
  end,
  condition = {
    filetype = { "c" },
  },
  tags = { overseer.TAG.BUILD },
}
