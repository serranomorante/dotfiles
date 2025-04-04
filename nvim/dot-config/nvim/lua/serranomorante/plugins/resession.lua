local utils = require("serranomorante.utils")

local M = {}

local function opts()
  local resession = require("resession")
  ---@type overseer.ListTaskOpts
  local overseer_ext_conf = {
    enable_in_tab = true,
    filter = require("serranomorante.plugins.overseer").task_allowed_to_store_in_session,
  }

  return {
    load_detail = false,
    ---removed options: diff
    options = {
      "binary",
      "bufhidden",
      "buflisted",
      "modifiable",
      "previewwindow",
      "readonly",
      "scrollbind",
      "winfixheight",
      "winfixwidth",
      "cmdheight",
    },
    buf_filter = function(bufnr) return utils.buf_inside_cwd(bufnr) and resession.default_buf_filter(bufnr) end,
    extensions = {
      quickfix = {
        enable_in_tab = true,
      },
      dap = {
        enable_in_tab = true,
      },
      aerial = {
        enable_in_tab = true,
      },
      overseer = overseer_ext_conf,
    },
  }
end

function M.config()
  local resession = require("resession")
  resession.setup(opts())

  local group = vim.api.nvim_create_augroup("resession_custom_group", { clear = true })

  vim.api.nvim_create_autocmd("VimEnter", {
    desc = "Load a dir-specific session when you open Neovim",
    group = group,
    callback = function()
      ---https://github.com/stevearc/resession.nvim?tab=readme-ov-file#create-one-session-per-directory
      if utils.nvim_started_without_args() and not utils.cwd_is_home() then
        ---Save these to a different directory, so our manual sessions don't get polluted
        resession.load(vim.fn.getcwd(), { dir = "dirsession", silence_errors = true, reset = true })
      end
    end,
    nested = true,
  })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    desc = "Save a dir-specific session when you close Neovim",
    group = group,
    callback = function()
      if utils.nvim_started_without_args() and not utils.cwd_is_home() then
        resession.save(vim.fn.getcwd(), { dir = "dirsession", notify = false })
      end
    end,
  })

  ---https://github.com/stevearc/resession.nvim/commit/271a6fd7afa90142be59fca3a5c3b9865e40e6b9
  vim.api.nvim_create_autocmd("StdinReadPre", {
    desc = "Set global variable when loading from stdin",
    group = group,
    callback = function() vim.g.using_stdin = true end,
  })
end

return M
