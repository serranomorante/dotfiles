local M = {}

local FILE_HISTORY_PANEL_HEIGHT = 6

local keys = function()
  vim.keymap.set("n", "<leader>vd", "<cmd>DiffviewOpen<CR>", { desc = "Diffview: compare against current index" })
  vim.keymap.set(
    "n",
    "<leader>vf",
    "<cmd>DiffviewFileHistory %<CR>",
    { desc = "Diffview: all commits affecting the current file" }
  )
end

local function init()
  vim.api.nvim_create_autocmd("BufWinLeave", {
    desc = "Fix issue with file history panel height after closing options panel",
    group = vim.api.nvim_create_augroup("diffview-options-panel", { clear = true }),
    pattern = "DiffviewFHOptionPanel",
    callback = function() vim.api.nvim_win_set_height(0, FILE_HISTORY_PANEL_HEIGHT) end,
  })
end

local opts = function()
  return {
    show_help_hints = false,
    watch_index = true,
    default_args = {
      DiffviewFileHistory = { "--no-merges" },
    },
    view = {
      default = {
        winbar_info = true,
      },
      merge_tool = {
        layout = "diff4_mixed",
      },
      file_history = {
        winbar_info = true,
      },
    },
    file_panel = {
      win_config = {
        width = 50,
        win_opts = {
          number = true,
          cursorlineopt = "line,number",
        },
      },
    },
    file_history_panel = {
      win_config = {
        height = FILE_HISTORY_PANEL_HEIGHT,
        win_opts = {
          number = true,
          cursorlineopt = "line,number",
        },
      },
    },
    hooks = {
      ---Fixes issue with coc.nvim
      diff_buf_read = function(bufnr) vim.api.nvim_buf_set_var(bufnr, "coc_enabled", 0) end,
    },
  }
end

M.config = function()
  init()
  keys()
  require("diffview").setup(opts())
end

return M
