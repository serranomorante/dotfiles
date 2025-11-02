local utils = require("serranomorante.utils")

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
  local startdir = params.startdir
  if not utils.exists(params.startdir) then startdir = vim.fn.fnamemodify(startdir, ":h") end
  if startdir then table.insert(args, "'" .. startdir .. "'") end
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
      { "system-components/COMPONENT__dispose_on_window_close" },
      { "system-components/COMPONENT__close_window_on_exit_0" },
      { "system-components/COMPONENT__force_very_fullscreen_float" },
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
