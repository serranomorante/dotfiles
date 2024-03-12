local utils = require("serranomorante.utils")

return {
  "stevearc/resession.nvim",
  event = "VeryLazy",
  keys = {
    {
      "<leader>ss",
      function() require("resession").save_tab(vim.fn.getcwd(), { dir = "dirsession", notify = true }) end,
      desc = "Resession: Save session",
    },
    {
      "<leader>sl",
      function()
        require("resession").load(vim.fn.getcwd(), { dir = "dirsession", silence_errors = true, reset = true })
      end,
      desc = "Resession: Load session",
    },
    {
      "<leader>sd",
      function() require("resession").delete(vim.fn.getcwd(), { dir = "dirsession" }) end,
      desc = "Resession: Delete session",
    },
  },
  opts = {
    load_detail = false,
    ---Remove `cmdheight` and `diff` options
    options = {
      "binary",
      "bufhidden",
      "buflisted",
      "filetype",
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
      ---Used to disable the builtin quickfix extension
      quickfix = {
        enable_in_tab = true,
      },
      dap = {
        enable_in_tab = true,
      },
    },
  },
  config = function(_, opts)
    local resession = require("resession")
    resession.setup(opts)

    ---fixes: https://github.com/stevearc/resession.nvim/issues/44#issue-2006411201
    ---also: https://github.com/AstroNvim/AstroNvim/issues/2378#issue-2005950553
    resession.add_hook("post_load", function()
      ---Force the `BufReadPre` on start to disable certain functionality on very large files
      vim.api.nvim_exec_autocmds("BufReadPre", { group = "large_buf" })
      vim.api.nvim_exec_autocmds("BufReadPost", {})
    end)

    ---Autoload session
    local autoload_session = function()
      ---Only load the session if nvim was started with no args
      if vim.fn.argc(-1) == 0 then
        ---Save these to a different directory, so our manual sessions don't get polluted
        resession.load(vim.fn.getcwd(), { dir = "dirsession", silence_errors = true, reset = true })
      end
    end

    if vim.v.vim_did_enter then
      autoload_session()
    else
      vim.api.nvim_create_autocmd("VimEnter", {
        desc = "Load a dir-specific session when you open Neovim",
        group = vim.api.nvim_create_augroup("resession_autoload_session", { clear = true }),
        callback = autoload_session,
      })
    end

    vim.api.nvim_create_autocmd("VimLeavePre", {
      desc = "Save a dir-specific session when you close Neovim",
      group = vim.api.nvim_create_augroup("resession_autosave_session", { clear = true }),
      callback = function()
        -- Only save the session if nvim was started with no args
        if vim.fn.argc(-1) == 0 then resession.save_tab(vim.fn.getcwd(), { dir = "dirsession", notify = false }) end
      end,
    })
  end,
}
