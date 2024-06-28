local constants = require("serranomorante.constants")
local heirline_conditions = require("heirline.conditions")
local heirline_utils = require("heirline.utils")
local utils = require("serranomorante.utils")
local events = require("serranomorante.events")

local M = {}

M.priority = {
  lsp = 40,
  filename = 30,
  trailblazer = 10,
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
    return " %2(" .. self.modes[self.mode][1] .. "%) "
  end,
  hl = function(self)
    ---Change the foreground according to the current mode
    if self.modes[self.mode][2] == "normal" then return { bg = "NvimLightGrey4", bold = true } end
    return { fg = "white", bg = "NvimDarkGrey1", bold = true }
  end,
  update = {
    "ModeChanged",
    pattern = "[^t]*:[^t]*", -- fixes issue with fzf-lua terminal buffers
    callback = vim.schedule_wrap(function() vim.cmd.redrawstatus() end),
  },
}

M.FileIcon = {
  init = function(self)
    local extension = vim.fn.fnamemodify(self.filename, ":e")
    self.icon, self.icon_color =
      require("nvim-web-devicons").get_icon_color(self.filename, extension, { default = true })
  end,
  provider = function(self) return self.icon and (self.icon .. " ") end,
}

M.FileName = {
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
    condition = function(self) return vim.api.nvim_get_option_value("modified", { buf = self.bufnr }) end,
    provider = "[+]",
    hl = { fg = "green" },
  },
  {
    condition = function(self)
      return not vim.api.nvim_get_option_value("modifiable", { buf = self.bufnr })
        or vim.api.nvim_get_option_value("readonly", { buf = self.bufnr })
    end,
    provider = " ",
    hl = { fg = "orange" },
  },
}

M.FileNameModifier = {
  hl = function()
    if vim.bo.modified then return { bold = true, underline = true } end
  end,
}

M.FileNameBlock = {
  init = function(self)
    self.bufnr = vim.api.nvim_get_current_buf()
    self.filename = utils.get_escaped_filename(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(self.bufnr), ":."))
    if self.filename == "" then self.filename = "[No Name]" end
  end,
  flexible = M.priority.filename,
  heirline_utils.insert(
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
  provider = "%P ",
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
    DEFAULT_LSP_TRUNC = 99,
    wrap = function(self, names, trunc)
      local limit = trunc or self.DEFAULT_LSP_TRUNC
      return " " .. string.format("%." .. limit .. "s%s", table.concat(names, ","), trunc and "…" or "")
    end,
  },
  condition = heirline_conditions.lsp_attached,
  flexible = M.priority.lsp,
  {
    provider = function(self) return self:wrap(self.names) end,
  },
  {
    provider = function(self) return self:wrap(self.names, 15) end,
  },
  {
    provider = function(self) return self:wrap(self.names, 10) end,
  },
  {
    provider = function(self) return self:wrap(self.names, 5) end,
  },
  {
    provider = function(self) return self:wrap({ "LSP" }) end,
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
    hl = { fg = "NvimDarkRed", ctermfg = 9, bold = true },
  },
  {
    condition = function(self) return self.warns end,
    M.Space,
  },
  {
    provider = function(self) return self.warns and (self.warn_icon .. self.warns) end,
    hl = { fg = "NvimDarkYellow", ctermfg = 11, bold = true },
  },
  {
    condition = function(self) return self.info end,
    M.Space,
  },
  {
    provider = function(self) return self.info and (self.info_icon .. self.info) end,
    hl = { fg = "NvimDarkCyan", ctermfg = 14, bold = true },
  },
  {
    condition = function(self) return self.hints end,
    M.Space,
  },
  {
    provider = function(self) return self.hints and (self.hint_icon .. self.hints) end,
    hl = { fg = "NvimDarkBlue", ctermfg = 12, bold = true },
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
    hl = { fg = "NvimDarkGreen", ctermfg = 10, bold = true },
  },
  {
    provider = function(self)
      local count = self.status_dict.removed or 0
      return count > 0 and ("-" .. count)
    end,
    hl = { fg = "NvimDarkRed", ctermfg = 9, bold = true },
  },
  {
    provider = function(self)
      local count = self.status_dict.changed or 0
      return count > 0 and ("~" .. count)
    end,
    hl = { fg = "NvimDarkCyan", ctermfg = 14, bold = true },
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
}

M.Indent = {
  condition = function() return utils.is_available("vim-sleuth") end,
  provider = function() return vim.fn.call("SleuthIndicator", {}) end,
  hl = { bold = true },
}

M.GrappleStatusline = {
  condition = function() return package.loaded["grapple"] and require("grapple").exists() end,
  provider = function() return "󰛢 " .. require("grapple").name_or_index() end,
}

M.TrailblazerCurrentStackName = {
  flexible = M.priority.trailblazer,
  condition = function() return package.loaded.trailblazer end,
  {
    provider = function()
      local stacks = require("trailblazer.trails.stacks")
      local current_stack = stacks.current_trail_mark_stack_name
      local stack_count = vim.tbl_count(stacks.trail_mark_stack_list) > 1 and "<" or ""
      return string.format("[%s%s]", current_stack, stack_count)
    end,
  },
  { provider = "" },
}

M.QuickfixTitle = {
  provider = function() return vim.w.quickfix_title end,
  hl = { bold = true },
}

local CocProgress = {
  condition = function()
    local current_buf = vim.api.nvim_get_current_buf()
    return vim.b[current_buf].coc_enabled == 1
  end,
  provider = "%{coc#status()}%{get(b:,'coc_current_function','')}",
  update = {
    "User",
    pattern = "CocStatusChange",
    callback = vim.schedule_wrap(function() vim.cmd.redrawstatus() end),
  },
}

local LspProgress = {
  init = require("serranomorante.plugins.statusline.utils").update_events({
    {
      "User",
      pattern = "CustomClearLspProgress",
      callback = vim.schedule_wrap(function(self)
        self.message = ""
        vim.cmd.redrawstatus()
      end),
    },
    {
      "LspProgress",
      pattern = { "begin", "end" },
      callback = vim.schedule_wrap(function(self, args)
        ---Inspired by: https://github.com/rockyzhang24/dotfiles/blob/master/.config/nvim/lua/rockyz/lsp/progress.lua
        local id = args.data.client_id
        local kind = args.data.params.value.kind
        local title = args.data.params.value.title
        local icons = { ["begin"] = "⣾", ["end"] = "" }
        local client_name = vim.lsp.get_client_by_id(id).name
        local suffix_when_done = kind == "end" and "DONE!" or ""

        --[[
          # Assemble the output progress message
          #  - General: ⣾ [client_name] title: message
          #  - Done:      [client_name] title: DONE!
        ]]
        self.message = string.format("%s [%s] %s: %s", icons[kind], client_name, title, suffix_when_done)
        if suffix_when_done ~= "" then utils.set_timeout(2000, function() events.event("ClearLspProgress") end) end
        vim.cmd.redrawstatus()
      end),
    },
  }),
  condition = function()
    local current_buf = vim.api.nvim_get_current_buf()
    local is_attached = vim.tbl_count(vim.lsp.get_clients({ bufnr = current_buf })) > 0
    return is_attached and vim.b[current_buf].coc_enabled ~= 1
  end,
  provider = function(self) return self.message or "" end,
}

M.LspProgress = {
  CocProgress,
  LspProgress,
  hl = { bold = true },
}

return M
