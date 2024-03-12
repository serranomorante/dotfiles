return {
  "folke/persistence.nvim",
  event = "VeryLazy", -- restore a session automatically on startup
  opts = {
    options = vim.opt.sessionoptions:get(),
  },
  config = function(_, opts)
    local persistence = require("persistence")
    persistence.setup(opts)

    local autoload_session = function()
      ---Only load the session if nvim was started with no args
      if vim.fn.argc(-1) == 0 then
        persistence.load()
        vim.api.nvim_exec_autocmds("BufReadPre", { group = "large_buf" })
        vim.api.nvim_exec_autocmds("BufReadPost", {})
      end
    end

    if vim.v.vim_did_enter then
      autoload_session()
    else
      vim.api.nvim_create_autocmd("VimEnter", {
        desc = "Load a dir-specific session when you open Neovim",
        group = vim.api.nvim_create_augroup("autoload_session", { clear = true }),
        callback = autoload_session,
      })
    end
  end,
}
