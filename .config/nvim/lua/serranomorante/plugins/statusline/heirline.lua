return {
  "rebelot/heirline.nvim",
  event = "UiEnter",
  dependencies = {
    "stevearc/aerial.nvim",
    opts = {
      filter_kind = false,
      disable_max_lines = vim.g.max_file.lines,
      disable_max_size = vim.g.max_file.size,
    },
  },
  init = function()
    vim.api.nvim_create_autocmd("LspAttach", {
      desc = "Re-trigger disable_winbar_cb on attach",
      group = vim.api.nvim_create_augroup("retrigger_disable_winbar_cb_on_attach", { clear = true }),
      callback = function() vim.api.nvim_exec_autocmds("Filetype", { group = "Heirline_init_winbar" }) end,
    })
  end,
  opts = function()
    local conditions = require("heirline.conditions")
    local components = require("serranomorante.plugins.statusline.components")
    local winbar_components = require("serranomorante.plugins.statusline.winbar-components")

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
      components.TrailblazerCurrentStackName,
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
        winbar_components.Oil,
      },
      {
        condition = function() return conditions.lsp_attached end,
        winbar_components.Breadcrumb,
      },
    }

    return {
      statusline = StatusLines,
      winbar = WinBars,
      opts = {
        disable_winbar_cb = function(args)
          if conditions.buffer_matches({ filetype = { "oil" } }, args.buf) then return false end
          if vim.tbl_count(vim.lsp.get_clients({ bufnr = args.buf })) > 0 then return false end
          return true
        end,
      },
    }
  end,
}
