local conditions = require("heirline.conditions")

local M = {}

M.Breadcrumb = {
  condition = function() return package.loaded["aerial"] end,
  update = "CursorMoved",
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

    for i, d in ipairs(data) do
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

M.Oil = {
  condition = function() return conditions.buffer_matches({ filetype = { "oil" } }) end,
  init = function(self) self.dir = require("oil").get_current_dir() end,
  {
    provider = function() return vim.fn.fnamemodify(vim.fn.getcwd(), ":p"):gsub("^" .. vim.env.HOME, "~") end,
    hl = { fg = "NvimLightCyan", bold = true },
  },
  {
    provider = function(self) return vim.fn.fnamemodify(self.dir, ":.") end,
  },
}

return M
