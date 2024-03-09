return {
  "stevearc/oil.nvim",
  lazy = false,
  keys = {
    {
      "<leader>e",
      function()
        ---https://github.com/stevearc/oil.nvim/issues/153#issuecomment-1675154847
        if vim.bo.filetype == "oil" then
          require("oil").close()
        else
          require("oil").open()
        end
      end,
      desc = "Oil: File navigation",
    },
  },
  opts = function()
    local oil_actions = require("oil.actions")

    return {
      view_options = {
        show_hidden = true,
      },
      ---https://github.com/stevearc/oil.nvim/issues/201#issuecomment-1771146785
      cleanup_delay_ms = false,
      skip_confirm_for_simple_edits = true,
      delete_to_trash = true,
      ---Copied here for readability
      keymaps = {
        ["<C-p>"] = false,
        ["<C-l>"] = false,
        ["<C-h>"] = false,
        ["g?"] = {
          callback = oil_actions.show_help.callback,
          desc = "Oil: Show default keymaps",
        },
        ["<CR>"] = {
          callback = oil_actions.select.callback,
          desc = "Oil: Open the entry under the cursor",
        },
        ["sv"] = {
          callback = oil_actions.select_vsplit.callback,
          desc = "Oil: Open the entry under the cursor in a vertical split",
        },
        ["ss"] = {
          callback = oil_actions.select_split.callback,
          desc = "Oil: Open the entry under the cursor in a horizontal split",
        },
        ["<C-t>"] = {
          callback = oil_actions.select_tab.callback,
          desc = "Oil: Open the entry under the cursor in a new tab",
        },
        ["<C-c>"] = {
          callback = oil_actions.close.callback,
          desc = "Oil: Close oil and restore original buffer",
        },
        ["<leader>rr"] = {
          callback = oil_actions.refresh.callback,
          desc = "Oil: Refresh current directory list",
        },
        ["-"] = {
          callback = oil_actions.parent.callback,
          desc = "Oil: Navigate to the parent path",
        },
        ["_"] = {
          callback = oil_actions.open_cwd.callback,
          desc = "Oil: Open oil in Neovim's current working directory",
        },
        ["`"] = {
          callback = oil_actions.cd.callback,
          desc = "Oil: `:cd` to the current oil directory",
        },
        ["~"] = {
          callback = oil_actions.tcd.callback,
          desc = "Oil: `:tcd` to the current oil directory",
        },
        ["gs"] = {
          callback = oil_actions.change_sort.callback,
          desc = "Oil: Change the sort order",
        },
        ["gx"] = {
          callback = oil_actions.open_external.callback,
          desc = "Oil: Open the entry under the cursor in an external program",
        },
        ["g."] = {
          callback = oil_actions.toggle_hidden.callback,
          desc = "Oil: Toggle hidden files and directories",
        },
        ["g\\"] = {
          callback = oil_actions.toggle_trash.callback,
          desc = "Oil: Jump to and from the trash for the current directory",
        },
        ["<leader>yy"] = {
          callback = oil_actions.copy_entry_path.callback,
          desc = "Oil: Yank the filepath of the entry under the cursor to a register",
        },
      },
    }
  end,
}
