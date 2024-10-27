local utils = require("serranomorante.utils")

local M = {}

local opts = function()
  return {
    load_detail = false,
    ---Remove `cmdheight` and `diff` options
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
    buf_filter = function(bufnr)
      ---Because `tab_buf_filter` is not enough to filter all files outside cwd
      return utils.buf_inside_cwd(bufnr) and require("resession").default_buf_filter(bufnr)
    end,
    tab_buf_filter = function(tabpage, bufnr)
      ---Only save buffers in the current tabpage directory
      ---https://github.com/stevearc/resession.nvim?tab=readme-ov-file#use-tab-scoped-sessions
      local cwd = vim.fn.getcwd(-1, vim.api.nvim_tabpage_get_number(tabpage))
      return utils.buf_inside_cwd(bufnr, cwd)
    end,
    extensions = {
      quickfix = {
        enable_in_tab = true,
      },
      dap = {
        enable_in_tab = true,
      },
      oil = {
        enable_in_tab = true,
      },
      aerial = {
        enable_in_tab = true,
      },
      overseer = {
        enable_in_tab = true,
        name = {},
      },
    },
  }
end

M.config = function()
  local resession = require("resession")
  resession.setup(opts())

  local group = vim.api.nvim_create_augroup("resession_custom_group", { clear = true })

  vim.api.nvim_create_autocmd("VimEnter", {
    desc = "Load a dir-specific session when you open Neovim",
    group = group,
    callback = function()
      ---Only load the session if nvim was started with no args
      ---https://github.com/stevearc/resession.nvim?tab=readme-ov-file#create-one-session-per-directory
      if vim.fn.argc(-1) == 0 then
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
      ---Only save the session if nvim was started with no args
      if vim.fn.argc(-1) == 0 then resession.save_tab(vim.fn.getcwd(), { dir = "dirsession", notify = false }) end
    end,
  })
end

return M
