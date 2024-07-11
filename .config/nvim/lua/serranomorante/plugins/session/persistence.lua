local dap = require("serranomorante.plugins.session.dap_ext")
local session_utils = require("serranomorante.plugins.session.session-utils")

vim.api.nvim_create_autocmd("User", {
  desc = "Do stuff before saving the session",
  group = vim.api.nvim_create_augroup("persistence-pre-save", { clear = true }),
  pattern = "PersistenceSavePre",
  callback = vim.schedule_wrap(function()
    local persistence = require("persistence")
    local filename = vim.fn.fnameescape(persistence.current())
    session_utils.clean_before_session_save()
    local dap_data = dap.on_save()
    local data = { dap = dap_data }
    session_utils.save(filename, data)
  end),
})

return {
  "folke/persistence.nvim",
  event = "VeryLazy", -- restore a session automatically on startup
  init = function()
    ---No `tabpages`
    ---https://github.com/rmagatti/auto-session?tab=readme-ov-file#recommended-sessionoptions-config
    vim.o.sessionoptions = "blank,buffers,winsize,winpos,terminal"
  end,
  config = function(_, opts)
    local persistence = require("persistence")
    persistence.setup(opts)

    ---Called on start when loading the session
    local function autoload_session()
      if vim.fn.argc(-1) == 0 then ---Only load the session if nvim was started with no args
        persistence.load()
        ---Execute necessary events on start
        local current_buf = vim.api.nvim_get_current_buf()
        vim.api.nvim_exec_autocmds("BufReadPre", { group = "large_buf", buffer = current_buf, modeline = false })
        if vim.b[current_buf].large_buf then return end
        vim.api.nvim_exec_autocmds("BufReadPost", { modeline = false })

        ---Load custom saved data like dap breakpoints
        local filename = vim.fn.fnameescape(persistence.current())
        local user_data = session_utils.load_json_file(filename)
        if not user_data then return end
        dap.on_post_load(user_data.dap)
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
