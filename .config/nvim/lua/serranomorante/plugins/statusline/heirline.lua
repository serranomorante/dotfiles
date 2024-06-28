return {
  "rebelot/heirline.nvim",
  event = "UiEnter",
  dependencies = "stevearc/aerial.nvim",
  init = function()
    ---Force triggering `disable_winbar_cb` as the default events are not enough for my setup
    ---These are the default events: "VimEnter", "UIEnter", "BufWinEnter", "FileType", "TermOpen"
    local function trigger_winbar_cb() vim.api.nvim_exec_autocmds("FileType", { group = "Heirline_init_winbar" }) end

    local trigger_winbar_cb_augroup = vim.api.nvim_create_augroup("trigger_winbar_cb", { clear = true })
    vim.api.nvim_create_autocmd("LspAttach", {
      desc = "Trigger disable_winbar_cb on LspAttach",
      group = trigger_winbar_cb_augroup,
      callback = trigger_winbar_cb,
    })
    vim.api.nvim_create_autocmd("User", {
      desc = "Trigger disable_winbar_cb on CocNvimInit",
      pattern = "CocNvimInit",
      group = trigger_winbar_cb_augroup,
      callback = vim.schedule_wrap(trigger_winbar_cb),
    })
  end,
  opts = function()
    local conditions = require("heirline.conditions")
    local components = require("serranomorante.plugins.statusline.components")
    local winbar_components = require("serranomorante.plugins.statusline.winbar-components")
    local tabline_components = require("serranomorante.plugins.statusline.tabline-components")

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
      components.GrappleStatusline,
      components.Space,
      components.LspProgress,
      components.Align,

      components.LSPActive,
      components.Space,
      components.Indent,
      components.Space,
      components.Ruler,
    }

    local InactiveStatusLine = {
      condition = conditions.is_not_active,
      components.FileNameBlock,
      components.Align,
    }

    local DAPUIStatusLine = {
      condition = function() return conditions.is_active() and conditions.buffer_matches({ filetype = { "^dap-.*" } }) end,
      components.Mode,
      components.Space,
      components.FileNameBlock,
      components.Align,
    }

    local QuickfixStatusLine = {
      condition = function() return conditions.is_active() and conditions.buffer_matches({ filetype = { "qf" } }) end,
      components.QuickfixTitle,
    }

    local StatusLines = {
      hl = function() return conditions.is_active() and "StatusLine" or "StatusLineNC" end,
      fallthrough = false,
      DAPUIStatusLine,
      QuickfixStatusLine,
      InactiveStatusLine,
      DefaultStatusLine,
    }

    local WinBars = {
      fallthrough = false,
      winbar_components.Oil,
      winbar_components.Breadcrumb,
    }

    local TabLines = { tabline_components.TabPages }

    return {
      statusline = StatusLines,
      winbar = WinBars,
      tabline = TabLines,
      opts = {
        ---Winbar should be disabled by default and only enabled after these conditions
        disable_winbar_cb = function(args)
          ---Show winbar on these filetypes
          if conditions.buffer_matches({ filetype = { "oil" } }, args.buf) then return false end
          ---Show winbar if these lsp servers are ready
          if vim.b[args.buf].coc_enabled ~= 1 and vim.tbl_count(vim.lsp.get_clients({ bufnr = args.buf })) > 0 then
            return false
          end
          ---Show winbar if coc extensions are ready
          if vim.b[args.buf].coc_enabled == 1 then return false end
          return true -- hide winbar by default
        end,
      },
    }
  end,
}
