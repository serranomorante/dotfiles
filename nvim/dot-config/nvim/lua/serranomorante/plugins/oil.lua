local utils = require("serranomorante.utils")

local detail = false
local show_hidden = false

local M = {}

---Helper function to parse output
local function parse_output(proc)
  local result = proc:wait()
  local ret = {}
  if result.code == 0 then
    for line in vim.gsplit(result.stdout, "\n", { plain = true, trimempty = true }) do
      ---Remove trailing slash
      line = line:gsub("/$", "")
      ret[line] = true
    end
  end
  return ret
end

---Build git status cache
local function new_git_status()
  return setmetatable({}, {
    __index = function(self, key)
      local ignore_proc = vim.system(
        { "git", "ls-files", "--ignored", "--exclude-standard", "--others", "--directory" },
        {
          cwd = key,
          text = true,
        }
      )
      local tracked_proc = vim.system({ "git", "ls-tree", "HEAD", "--name-only" }, {
        cwd = key,
        text = true,
      })
      local ret = {
        ignored = parse_output(ignore_proc),
        tracked = parse_output(tracked_proc),
      }

      rawset(self, key, ret)
      return ret
    end,
  })
end

local function keys()
  vim.keymap.set("n", "<leader>e", function()
    ---https://github.com/stevearc/oil.nvim/issues/153#issuecomment-1675154847
    if vim.bo.filetype == "oil" then
      require("oil").close()
    else
      local parent_dir = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":h")
      if not utils.is_directory(parent_dir) then
        vim.notify(string.format('"%s" not found. Opening cwd...', parent_dir), vim.log.levels.WARN)
        return require("oil").open(vim.fn.getcwd())
      end
      require("oil").open()
    end
  end, { desc = "Oil: File navigation" })
end

local init = function()
  vim.api.nvim_create_autocmd("User", {
    desc = "Perform actions after OilActionsPost event",
    group = vim.api.nvim_create_augroup("unlist_buffers_after_oil", { clear = true }),
    pattern = "OilActionsPost",
    callback = function(args)
      ---https://github.com/stevearc/oil.nvim/issues/310#issuecomment-2002783192
      if args.data.err then return end
      local util = require("oil.util")
      local original_alternate_file = vim.fn.bufname("#")
      local new_empty_buffer = nil

      for _, action in pairs(args.data.actions) do
        ---Automatically add title to new markdown files created from oil buffer
        if action.type == "create" and action.entry_type == "file" then
          local _, filename = util.parse_url(action.url)
          if filename == nil then return end
          local file_ext = vim.fn.fnamemodify(filename, ":e")
          if file_ext == "md" then
            local fd = assert(vim.uv.fs_open(filename, "w", 420))
            vim.uv.fs_write(fd, "# " .. vim.fn.fnamemodify(filename, ":t"):gsub("." .. file_ext, ""))
            vim.uv.fs_close(fd)
          end
          ---Remove deleted file from buffer list
        elseif action.type == "delete" and action.entry_type == "file" then
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
end

---@return oil.SetupOpts
local function opts()
  local oil_actions = require("oil.actions")
  local git_status = new_git_status()

  ---Clear git status cache on refresh
  local refresh = require("oil.actions").refresh
  local orig_refresh = refresh.callback
  refresh.callback = function(...)
    git_status = new_git_status()
    orig_refresh(...)
  end

  return {
    watch_for_changes = true,
    buf_options = {
      syntax = "ON",
    },
    win_options = {
      signcolumn = "yes:2",
    },
    view_options = {
      show_hidden = show_hidden,
      is_hidden_file = function(name, bufnr)
        local dir = require("oil").get_current_dir(bufnr)
        local is_dotfile = vim.startswith(name, ".") and name ~= ".."
        ---If no local directory (e.g. for ssh connections), just hide dotfiles
        if not dir then return is_dotfile end
        ---Dotfiles are considered hidden unless tracked
        if is_dotfile then
          return not git_status[dir].tracked[name]
        else
          ---Check if file is gitignored
          return git_status[dir].ignored[name]
        end
      end,
    },
    ---https://github.com/stevearc/oil.nvim/issues/201#issuecomment-1771146785
    cleanup_delay_ms = false,
    skip_confirm_for_simple_edits = true,
    delete_to_trash = true,
    git = {
      ---Return true to automatically git add/mv/rm files
      add = function(path)
        local relative_path = vim.fn.fnamemodify(path, ":.")
        local is_ignored = utils.cmd({ "git", "check-ignore", relative_path }, false)
        if is_ignored then return false end -- don't use git if file is ignored
        return true
      end,
      mv = function(src_path, dest_path) return true end,
      rm = function(path) return true end,
    },
    ---Copied here for readability
    keymaps = {
      ["<C-p>"] = false,
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
      ["C-l"] = {
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
        callback = function()
          oil_actions.toggle_hidden.callback()
          show_hidden = not show_hidden
          vim.notify(show_hidden == true and "Oil: show hidden: ON" or "Oil: show hidden: OFF")
        end,
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
      ["gd"] = {
        callback = function()
          detail = not detail
          if detail then
            require("oil").set_columns({ "icon", "permissions", "size", "mtime" })
          else
            require("oil").set_columns({ "icon" })
          end
        end,
        desc = "Oil: Toggle file detail view",
      },
      ["<leader>fw"] = {
        callback = function()
          local options = {
            ---https://github.com/ibhagwan/fzf-lua/wiki/Options#grep-providers-options
            search = " -- " .. vim.fn.fnamemodify(require("oil").get_current_dir() or "", ":~"),
            no_esc = true, -- Do not escape regex characters
          }
          require("fzf-lua").live_grep(options)
        end,
        desc = "Oil: Grep into this directory with FZF",
      },
      ["<leader>ff"] = {
        callback = function()
          require("fzf-lua").files({
            cwd = vim.fn.fnamemodify(require("oil").get_current_dir() or "", ":.:~"),
          })
        end,
        desc = "Oil: Search files into this directory with FZF",
      },
    },
  }
end

M.config = function()
  init()
  keys()
  require("oil").setup(opts())
end

return M
