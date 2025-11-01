---@type overseer.TemplateDefinition
---@diagnostic disable-next-line: missing-fields
local M = {}

local TASK_NAME = "nnn-explorer"

M.name = TASK_NAME
M.desc = "Explore in NNN"
M.hide = true
M.params = {
  startdir = {
    desc = "Path",
    type = "string",
    optional = true,
  },
}

function M.builder(params)
  local args = {
    "-JRHdaAog",
    "-Tt",
    "-c",
  }
  if params.startdir then table.insert(args, string.format("'%s'", params.startdir)) end
  return {
    name = TASK_NAME,
    cmd = "nnn",
    args = args,
    env = {
      EDITOR = "open_in_nvim.sh nnn_explorer",
      VISUAL = "open_in_nvim.sh nnn_explorer",
      NNN_OPENER = "open_in_nvim.sh nnn_explorer",
      NNN_TRASH = "trash",
      NVIM_KITTY_LISTEN_ADDRESS = vim.v.servername,
      TERM = vim.env.TERM,
    },
    components = {
      { "system-components/COMPONENT__start_insert_mode" },
      { "open_output", direction = "float", on_start = "always", focus = true },
      { "on_complete_dispose", timeout = 1, statuses = { require("overseer.parser").STATUS.SUCCESS } },
      "unique",
      "defaults_without_notification",
    },
  }
end

M.condition = {}
function M.condition.callback() return vim.fn.executable("nnn") == 1 end

return M
