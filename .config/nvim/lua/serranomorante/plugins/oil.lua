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
  init = function()
    vim.api.nvim_create_autocmd("User", {
      desc = "Unlist buffers after deleted by Oil. Also set alternate file correctly.",
      group = vim.api.nvim_create_augroup("unlist_buffers_after_oil", { clear = true }),
      pattern = "OilActionsPost",
      callback = function(args)
        ---https://github.com/stevearc/oil.nvim/issues/310#issuecomment-2002783192
        if args.data.err then return end
        local util = require("oil.util")
        local original_alternate_file = vim.fn.bufname("#")
        local new_empty_buffer = nil

        for _, action in ipairs(args.data.actions) do
          if action.type == "delete" and action.entry_type == "file" then
            local _, path = util.parse_url(action.url)
            ---Set alternate file to a new empty buffer
            if new_empty_buffer == nil and path == original_alternate_file then
              new_empty_buffer = vim.api.nvim_create_buf(true, false)
              vim.w.oil_original_buffer = new_empty_buffer
            end
            ---Unlist removed buffer
            vim.cmd("silent! bw! " .. path)
          end
        end
      end,
    })
  end,
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
        ["<leader>fw"] = {
          callback = function()
            local current_dir = vim.fn.fnamemodify(require("oil").get_current_dir(), ":.")
            require("fzf-lua").live_grep({
              ---https://github.com/ibhagwan/fzf-lua/wiki/Options#grep-providers-options
              search = string.format(" -- %s**", current_dir),
              no_esc = true, -- Do not escape regex characters
            })
          end,
          desc = "Oil: Grep into this directory with FZF",
        },
        ["<leader>ff"] = {
          callback = function()
            local current_dir = vim.fn.fnamemodify(require("oil").get_current_dir(), ":.")
            require("fzf-lua").files({ cwd = current_dir })
          end,
          desc = "Oil: Search files into this directory with FZF",
        },
      },
    }
  end,
}
