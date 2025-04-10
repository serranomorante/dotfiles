---@diagnostic disable: missing-fields

local M = {}

local FILE_HISTORY_PANEL_HEIGHT = 6

local function keys()
  vim.keymap.set("n", "<leader>vd", "<cmd>DiffviewOpen<CR>", { desc = "Diffview: compare against current index" })
  vim.keymap.set("n", "<leader>vs", ":DiffviewFileHistory -S=", { desc = "Diffview: search in git history" })
  vim.keymap.set(
    "n",
    "<leader>vf",
    "<cmd>DiffviewFileHistory %<CR>",
    { desc = "Diffview: all commits affecting the current file" }
  )
end

local function init()
  local group = vim.api.nvim_create_augroup("diffview-options-panel", { clear = true })
  vim.api.nvim_create_autocmd("BufWinLeave", {
    desc = "Fix issue with file history panel height after closing options panel",
    group = group,
    pattern = "DiffviewFHOptionPanel",
    callback = function() vim.api.nvim_win_set_height(0, FILE_HISTORY_PANEL_HEIGHT) end,
  })
end

local function opts()
  ---@type DiffviewConfig
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
      ---Remember: diffview will not give you the filehistorypanel's bufnr. That's why you have
      ---to use `0` instead of `bufnr`.
      diff_buf_read = function(bufnr)
        ---fix coc.nvim lsp error on diff window
        vim.api.nvim_buf_set_var(bufnr, "coc_enabled", 0)
        ---make sure file history panel is selected before next commands
        vim.cmd("3wincmd w")
        ---force cursor position on first history item
        if vim.api.nvim_buf_get_name(0):match("DiffviewFileHistoryPanel") then vim.cmd("normal jk") end
      end,
      diff_buf_win_enter = function(_, winid) vim.wo[winid].wrap = true end,
    },
  }
end

function M.config()
  init()
  keys()
  require("diffview").setup(opts())
end

return M
