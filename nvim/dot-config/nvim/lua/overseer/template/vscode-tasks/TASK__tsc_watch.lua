local utils = require("serranomorante.utils")
local constants = require("serranomorante.constants")
if not utils.is_available("overseer") then return {} end
local overseer = require("overseer")
local typescript_provider = require("overseer.template.vscode.provider.typescript")

return {
  name = "vscode-tasks: TSC watch tsconfig.json (relative)",
  desc = "Watch a typescript project using the tsconfig.json from the current buffer's directory",
  builder = function()
    local tsconfig = vim.fs.find("tsconfig.json", {
      stop = vim.fn.getcwd() .. "/..",
      type = "file",
      upward = true,
      path = vim.fs.dirname(vim.api.nvim_buf_get_name(0)),
    })

    if vim.tbl_count(tsconfig) == 0 then return vim.notify("tsconfig.json not found", vim.log.levels.ERROR) end

    local task_opts = typescript_provider.get_task_opts({
      tsconfig = tsconfig[1],
      option = "watch",
    })

    return {
      cmd = task_opts.cmd,
      components = {
        { "on_output_parse", problem_matcher = "$tsc-watch" },
        "on_result_notify",
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
