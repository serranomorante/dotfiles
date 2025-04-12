local coc_utils = require("serranomorante.plugins.coc.utils")

local M = {}

local function init()
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
end

local function opts()
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
    components.Overseer,
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
    condition = function() return conditions.buffer_matches({ filetype = { "^dap-.*" } }) end,
    components.Mode,
    components.Space,
    components.FileNameBlock,
    components.Align,
  }

  local QuickfixStatusLine = {
    condition = function() return conditions.buffer_matches({ filetype = { "qf" } }) end,
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

  local TabLines = {
    fallthrough = false,
    tabline_components.TabPages,
  }

  return {
    statusline = StatusLines,
    winbar = WinBars,
    tabline = TabLines,
    opts = {
      ---Winbar should be disabled by default and only enabled after these conditions
      disable_winbar_cb = function(args)
        if not vim.api.nvim_buf_is_valid(args.buf) then return true end
        ---Show winbar on these filetypes
        if conditions.buffer_matches({ filetype = { "oil" } }, args.buf) then return false end
        ---Show winbar if these lsp servers are ready
        if not coc_utils.is_coc_attached(args.buf) and vim.tbl_count(vim.lsp.get_clients({ bufnr = args.buf })) > 0 then
          return false
        end
        ---Show winbar if coc extensions are ready
        if coc_utils.is_coc_attached(args.buf) then return false end
        return true -- hide winbar by default
      end,
    },
  }
end

function M.config()
  init()
  require("heirline").setup(opts())
end

return M
