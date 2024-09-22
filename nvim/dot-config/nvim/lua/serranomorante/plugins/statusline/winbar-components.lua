local heirline_conditions = require("heirline.conditions")
local heirline_utils = require("heirline.utils")
local utils = require("serranomorante.utils")

local M = {}

local AerialBreadcrumb = {
  condition = function() return utils.is_available("aerial") end,
  init = function(self)
    local data = require("aerial").get_location(true) or {}
    local children = {}
    local max_depth = 5
    local separator = " > "

    local start_idx = 0
    if max_depth > 0 then
      start_idx = #data - max_depth
      if start_idx > 0 then table.insert(children, {
        provider = "…" .. separator,
      }) end
    end

    for i, d in pairs(data) do
      if i > start_idx then
        ---Symbol name
        local child = {
          {
            provider = string.gsub(d.name, "%%", "%%%%"):gsub("%s*->%s*", ""),
          },
        }
        ---Icon
        table.insert(child, 1, {
          provider = string.format("%s ", d.icon),
        })
        if #data > 1 and i < #data then table.insert(child, { provider = separator }) end
        table.insert(children, child)
      end
    end

    self[1] = self:new(children, 1)
  end,
}

M.Breadcrumb = {
  init = require("serranomorante.plugins.statusline.utils").update_events({
    {
      "LspAttach",
      callback = vim.schedule_wrap(function() vim.cmd.redrawstatus() end),
    },
    {
      "User",
      pattern = "CocNvimInit",
      callback = vim.schedule_wrap(function() vim.cmd.redrawstatus() end),
    },
  }),
  heirline_utils.insert(AerialBreadcrumb),
}

M.Oil = {
  condition = function()
    return heirline_conditions.buffer_matches({ filetype = { "oil" } })
      and (not heirline_conditions.buffer_matches({ filetype = { "oil_preview" } }))
  end,
  init = function(self) self.dir = require("oil").get_current_dir() end,
  {
    provider = function(self)
      local cwd = vim.fn.getcwd()
      local parent = vim.fn.fnamemodify(cwd, ":p"):gsub("^" .. vim.env.HOME, "~")
      if self.dir and not string.find(self.dir, cwd) then
        ---This means we are outside of our current working directory
        return "(" .. parent .. ") "
      end
      return parent
    end,
    hl = { fg = "NvimLightCyan", bold = true },
  },
  {
    provider = function(self) return vim.fn.fnamemodify(self.dir, ":.") end,
  },
}

return M
