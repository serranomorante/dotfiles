local utils = require("serranomorante.utils")
local constants = require("serranomorante.constants")
if not utils.is_available("overseer") then return {} end
local overseer = require("overseer")
local typescript_provider = require("overseer.template.vscode.provider.typescript")

local task_name = "vscode-tasks-tsc-watch"

---@type overseer.TemplateDefinition
return {
  name = task_name,
  desc = "Watch a typescript project using the tsconfig.json from the current buffer's directory",
  builder = function()
    local tsconfig = vim.fs.find("tsconfig.json", {
      stop = vim.fn.getcwd() .. "/..",
      type = "file",
      upward = true,
      path = vim.fs.dirname(vim.api.nvim_buf_get_name(0)),
    })

    local task_opts = typescript_provider.get_task_opts({
      tsconfig = vim.tbl_count(tsconfig) ~= 0 and tsconfig[1] or nil,
      option = "watch",
    })
    local command = vim.list_extend(task_opts.cmd, { "--pretty", "false" })
    return {
      cmd = { "tmux" },
      args = utils.wrap_overseer_args_with_tmux(command, { session_name = task_name }),
      env = {
        NO_COLOR = "1",
      },
      components = {
        { "on_output_parse", problem_matcher = "$tsc-watch" },
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
