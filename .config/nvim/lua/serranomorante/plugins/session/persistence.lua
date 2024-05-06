return {
  "folke/persistence.nvim",
  event = "VeryLazy", -- restore a session automatically on startup
  opts = {
    ---No `tabpages`
    ---https://github.com/rmagatti/auto-session?tab=readme-ov-file#recommended-sessionoptions-config
    options = { "blank", "buffers", "winsize", "winpos", "terminal" },
  },
  config = function(_, opts)
    local persistence = require("persistence")
    local Config = require("persistence.config")
    local dap = require("serranomorante.plugins.session.dap_ext")
    local session_utils = require("serranomorante.plugins.session.session-utils")

    Config.setup(opts) -- required for `persistence.get_current` to work
    local filename = vim.fn.fnameescape(persistence.get_current())

    opts.pre_save = function()
      session_utils.clean_before_session_save()
      local dap_data = dap.on_save()
      local data = { dap = dap_data }
      session_utils.save(filename, data)
    end

    persistence.setup(opts)

    local autoload_session = function()
      ---Only load the session if nvim was started with no args
      if vim.fn.argc(-1) == 0 then
        persistence.load()
        local current_buf = vim.api.nvim_get_current_buf()
        vim.api.nvim_exec_autocmds("BufReadPre", { group = "large_buf", buffer = current_buf, modeline = false })
        if vim.b[current_buf].large_buf then return end
        vim.api.nvim_exec_autocmds("BufReadPost", { modeline = false })
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

    local user_data = session_utils.load_json_file(filename)
    if not user_data then return end
    dap.on_post_load(user_data.dap)
  end,
}
