local constants = require("serranomorante.constants")
local heirline_conditions = require("heirline.conditions")
local heirline_utils = require("heirline.utils")

local M = {}

M.priority = {
  lsp = 40,
  filename = 30,
  overseer = 20,
}

M.Align = {
  provider = "%=",
}

M.Space = {
  provider = " ",
}

---https://github.com/rebelot/heirline.nvim/blob/master/cookbook.md#crash-course-the-vimode
M.Mode = {
  init = function(self) self.mode = vim.fn.mode() end,
  static = { modes = constants.modes },
  provider = function(self)
    ---Control the padding and make sure our string is always at least 2
    ---characters long.
    return "%2(" .. self.modes[self.mode][1] .. "%)"
  end,
  hl = function(self)
    ---Change the foreground according to the current mode
    return { fg = self.modes[self.mode][2], bold = true }
  end,
  update = {
    "ModeChanged",
    pattern = "*:*",
    callback = vim.schedule_wrap(function() vim.cmd("redrawstatus") end),
  },
}

---https://github.com/rebelot/heirline.nvim/blob/master/cookbook.md#crash-course-part-ii-filename-and-friends
M.FileNameBlock = {
  init = function(self) self.filename = vim.api.nvim_buf_get_name(0) end,
}

M.FileIcon = {
  init = function(self)
    local filename = self.filename
    local extension = vim.fn.fnamemodify(filename, ":e")
    self.icon, self.icon_color = require("nvim-web-devicons").get_icon_color(filename, extension, { default = true })
  end,
  provider = function(self) return self.icon and (self.icon .. " ") end,
  hl = function(self) return { fg = self.icon_color } end,
}

M.FileName = {
  init = function(self)
    self.filename = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":.")
    if self.filename == "" then self.filename = "[No Name]" end
  end,
  hl = { fg = "directory" },
  flexible = M.priority.filename,
  {
    provider = function(self) return self.filename end,
  },
  {
    provider = function(self) return vim.fn.fnamemodify(self.filename, ":t") end,
  },
}

M.FileFlags = {
  {
    condition = function() return vim.bo.modified end,
    provider = "[+]",
    hl = { fg = "green" },
  },
  {
    condition = function() return not vim.bo.modifiable or vim.bo.readonly end,
    provider = "",
    hl = { fg = "orange" },
  },
}

M.FileNameModifier = {
  hl = function()
    if vim.bo.modified then return { fg = "cyan", bold = true, force = true } end
  end,
}

M.FileNameBlock = {
  flexible = M.priority.filename,
  heirline_utils.insert(
    M.FileNameBlock,
    M.FileIcon,
    heirline_utils.insert(M.FileNameModifier, M.FileName),
    M.FileFlags,
    { provider = "%<" }
  ),
}

---https://github.com/rebelot/heirline.nvim/blob/master/cookbook.md#cursor-position-ruler-and-scrollbar
M.Ruler = {
  -- %l = current line number
  -- %L = number of lines in the buffer
  -- %c = column number
  -- %P = percentage through file of displayed window
  provider = "%P",
}

---https://github.com/rebelot/heirline.nvim/blob/master/cookbook.md#lsp
M.LSPActive = {
  init = function(self)
    local names = {}
    for _, server in pairs(vim.lsp.get_clients({ bufnr = 0 })) do
      table.insert(names, server.name)
    end
    if package.loaded.lint ~= nil then
      local buf_lint_clients = require("lint").linters_by_ft[vim.bo.filetype]
      if buf_lint_clients and #buf_lint_clients > 0 then
        for _, lint_client in pairs(buf_lint_clients) do
          table.insert(names, lint_client or "")
        end
      end
    end
    self.names = names
  end,
  static = {
    surround = function(_, names) return vim.tbl_count(names) > 0 and " " .. table.concat(names, ",") or "" end,
    truncate = function(_, value) return value and (value):sub(1, 5) .. ".." or "" end,
  },
  condition = heirline_conditions.lsp_attached,
  hl = { fg = "green", bold = true },
  flexible = M.priority.lsp,
  {
    provider = function(self) return self:surround(self.names) end,
  },
  {
    provider = function(self) return self:surround({ self.names[1], self.names[2], self:truncate(self.names[3]) }) end,
  },
  {
    provider = function(self) return self:surround({ self.names[1], self:truncate(self.names[2]) }) end,
  },
  {
    provider = function(self) return self:surround({ self:truncate(self.names[1]) }) end,
  },
  {
    provider = function(self) return self:surround({ "LSP" }) end,
  },
}
---https://github.com/rebelot/heirline.nvim/blob/master/cookbook.md#diagnostics
---https://github.com/neovim/neovim/commit/4ee656e4f35766bef4e27c5afbfa8e3d8d74a76c
M.Diagnostics = {
  condition = heirline_conditions.has_diagnostics,
  static = {
    error_icon = " ",
    warn_icon = " ",
    hint_icon = "󰌵 ",
    info_icon = "󰋼 ",
  },
  init = function(self)
    local diagnostics = vim.diagnostic.count(0) or {}
    self.errors = diagnostics[vim.diagnostic.severity.ERROR]
    self.warns = diagnostics[vim.diagnostic.severity.WARN]
    self.info = diagnostics[vim.diagnostic.severity.INFO]
    self.hints = diagnostics[vim.diagnostic.severity.HINT]
    self.diagnostics = diagnostics
  end,
  {
    condition = function(self) return #self.diagnostics end,
    M.Space,
  },
  {
    provider = function(self) return self.errors and (self.error_icon .. self.errors) end,
    hl = { fg = "diag_error" },
  },
  {
    condition = function(self) return self.warns end,
    M.Space,
  },
  {
    provider = function(self) return self.warns and (self.warn_icon .. self.warns) end,
    hl = { fg = "diag_warn" },
  },
  {
    condition = function(self) return self.info end,
    M.Space,
  },
  {
    provider = function(self) return self.info and (self.info_icon .. self.info) end,
    hl = { fg = "diag_info" },
  },
  {
    condition = function(self) return self.hints end,
    M.Space,
  },
  {
    provider = function(self) return self.hints and (self.hint_icon .. self.hints) end,
    hl = { fg = "diag_hint" },
  },
}

---https://github.com/rebelot/heirline.nvim/blob/master/cookbook.md#git
M.Git = {
  condition = heirline_conditions.is_git_repo,
  init = function(self)
    self.status_dict = vim.b.gitsigns_status_dict
    self.has_changes = (self.status_dict.added ~= 0 and self.status_dict.added ~= nil)
      or (self.status_dict.removed ~= 0 and self.status_dict.removed ~= nil)
      or (self.status_dict.changed ~= 0 and self.status_dict.changed ~= nil)
    self.branch = self.status_dict.head
  end,
  hl = { fg = "orange" },
  {
    provider = function(self) return " " .. (self.branch ~= "" and self.branch or "?") end,
    hl = { bold = true },
  },
  {
    condition = function(self) return self.has_changes end,
    provider = "(",
  },
  {
    provider = function(self)
      local count = self.status_dict.added or 0
      return count > 0 and ("+" .. count)
    end,
    hl = { fg = "git_add" },
  },
  {
    provider = function(self)
      local count = self.status_dict.removed or 0
      return count > 0 and ("-" .. count)
    end,
    hl = { fg = "git_del" },
  },
  {
    provider = function(self)
      local count = self.status_dict.changed or 0
      return count > 0 and ("~" .. count)
    end,
    hl = { fg = "git_change" },
  },
  {
    condition = function(self) return self.has_changes end,
    provider = ")",
  },
}

---https://github.com/rebelot/heirline.nvim/blob/master/cookbook.md#debugger
M.DAPMessages = {
  condition = function()
    if not package.loaded.dap then return false end
    local session = require("dap").session()
    return session ~= nil
  end,
  provider = function() return " " .. require("dap").status() end,
  hl = "Debug",
}

local function OverseerTasksForStatus(status)
  return {
    condition = function(self) return self.tasks[status] end,
    provider = function(self) return string.format("%s%d", self.status[status][1], #self.tasks[status]) end,
    hl = function()
      return {
        fg = heirline_utils.get_highlight(string.format("Overseer%s", status)).fg,
      }
    end,
  }
end

M.Overseer = {
  condition = function() return package.loaded.overseer end,
  init = function(self)
    local tasks = require("overseer.task_list").list_tasks({ unique = true })
    local tasks_by_status = require("overseer.util").tbl_group_by(tasks, "status")
    self.tasks = tasks_by_status
  end,
  flexible = M.priority.overseer,
  static = {
    status = constants.overseer_status,
  },
  {
    OverseerTasksForStatus("CANCELED"),
    { condition = function(self) return self.tasks.RUNNING end, M.Space },
    OverseerTasksForStatus("RUNNING"),
    { condition = function(self) return self.tasks.SUCCESS end, M.Space },
    OverseerTasksForStatus("SUCCESS"),
    { condition = function(self) return self.tasks.FAILURE end, M.Space },
    OverseerTasksForStatus("FAILURE"),
  },
  { provider = "" },
}

M.Indent = {
  provider = function() return "S:" .. vim.api.nvim_get_option_value("shiftwidth", { buf = 0 }) end,
  hl = { fg = "blue" },
}

return M
