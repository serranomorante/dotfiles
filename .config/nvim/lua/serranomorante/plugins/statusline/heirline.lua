return {
  "rebelot/heirline.nvim",
  event = "UiEnter",
  opts = function()
    local conditions = require("heirline.conditions")
    local components = require("serranomorante.plugins.statusline.components")

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
      components.Mode,
      components.Space,
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
        ---Only enable winbar on oil.nvim buffers
        disable_winbar_cb = function(args) return not conditions.buffer_matches({ filetype = { "oil" } }, args.buf) end,
      },
    }
  end,
}
