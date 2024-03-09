return {
  "rebelot/heirline.nvim",
  event = "UiEnter",
  opts = function()
    local conditions = require("heirline.conditions")
    local heirline_utils = require("heirline.utils")
    local components = require("serranomorante.plugins.statusline.components")

    local Function = heirline_utils.get_highlight("Function")
    local Constant = heirline_utils.get_highlight("Constant")
    local String = heirline_utils.get_highlight("String")
    local Statement = heirline_utils.get_highlight("Statement")
    local DiagnosticError = heirline_utils.get_highlight("DiagnosticError")
    local NonText = heirline_utils.get_highlight("NonText")
    local Special = heirline_utils.get_highlight("Special")
    local DiagnosticOk = heirline_utils.get_highlight("DiagnosticOk")
    local DiagnosticWarn = heirline_utils.get_highlight("DiagnosticWarn")
    local DiagnosticHint = heirline_utils.get_highlight("DiagnosticHint")
    local DiagnosticInfo = heirline_utils.get_highlight("DiagnosticInfo")
    local Directory = heirline_utils.get_highlight("Directory")

    local colors = {
      normal = Function.fg,
      insert = Constant.fg,
      command = String.fg,
      terminal = Constant.fg,
      visual = Statement.fg,
      replace = DiagnosticError.fg,
      directory = Directory.fg,
      ---https://github.com/rebelot/heirline.nvim/blob/master/cookbook.md#colors-colors-more-colors
      red = DiagnosticError.fg,
      green = String.fg,
      blue = Function.fg,
      gray = NonText.fg,
      orange = Constant.fg,
      cyan = Special.fg,
      diag_warn = DiagnosticWarn.fg,
      diag_error = DiagnosticError.fg,
      diag_hint = DiagnosticHint.fg,
      diag_info = DiagnosticInfo.fg,
      git_add = DiagnosticOk.fg,
      git_change = DiagnosticWarn.fg,
      git_del = DiagnosticError.fg,
    }

    local DefaultStatusLine = {
      components.Mode,
      components.Space,
      components.FileNameBlock,
      components.Space,
      components.Git,
      components.Diagnostics,
      components.Align,

      components.DAPMessages,
      components.Space,
      components.Overseer,
      components.Align,

      components.LSPActive,
      components.Space,
      components.Indent,
      components.Space,
      components.Ruler,
    }

    local InactiveStatusLine = {
      condition = conditions.is_not_active,
      components.FileName,
      components.Align,
    }

    local DAPUIStatusLine = {
      condition = function() return conditions.is_active() and conditions.buffer_matches({ filetype = { "^dap-.*" } }) end,
      components.FileNameBlock,
      components.Align,
    }

    local StatusLines = {
      hl = function() return conditions.is_active() and "StatusLine" or "StatusLineNC" end,
      fallthrough = false,
      DAPUIStatusLine,
      InactiveStatusLine,
      DefaultStatusLine,
    }

    local WinBars = {
      fallthrough = false,
      {
        condition = function() return conditions.buffer_matches({ filetype = { "oil" } }) end,
        {
          provider = function() return vim.fn.fnamemodify(require("oil").get_current_dir(), ":.") end,
        },
      },
    }

    return {
      statusline = StatusLines,
      winbar = WinBars,
      opts = {
        colors = colors,
        ---Only enable winbar on oil.nvim buffers
        disable_winbar_cb = function(args) return not conditions.buffer_matches({ filetype = { "oil" } }, args.buf) end,
      },
    }
  end,
}
