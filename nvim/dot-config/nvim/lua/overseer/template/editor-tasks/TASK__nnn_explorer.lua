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
    "--open-in-nvim",
    "-c",
  }
  local startdir = params.startdir
  if utils.is_directory(params.startdir) then
    startdir = startdir:sub(-1) ~= "/" and startdir .. "/" or startdir
  elseif not utils.exists(params.startdir) then
    startdir = vim.fn.fnamemodify(startdir, ":h")
  end
  if startdir then table.insert(args, startdir) end
  return {
    name = TASK_NAME,
    cmd = "nnn-with-defaults",
    args = args,
    env = {
      TERM = vim.env.TERM,
    },
    components = {
      { "open_output", direction = "float", on_start = "always", focus = true },
      { "on_complete_dispose", timeout = 1, statuses = { require("overseer.constants").STATUS.SUCCESS } },
      "unique",
      "defaults_without_notification",
    },
  }
end

return M
