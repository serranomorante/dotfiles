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
    local session_name = task_name .. vim.fn.fnameescape(vim.v.servername)
    return {
      cmd = { "tmux" },
      args = utils.wrap_overseer_args_with_tmux({
        "/usr/bin/gcc",
        "-fdiagnostics-color=always",
        "-g",
        precalculated_vars.file,
        "-o",
        precalculated_vars.fileDirname .. "/" .. precalculated_vars.fileBasenameNoExtension,
      }, session_name),
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
