local M = {}

local utils = require("serranomorante.utils")

M.fzf_lua = {
  "ibhagwan/fzf-lua",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  lazy = false,
  keys = {
    {
      "<leader>f<CR>",
      function() require("fzf-lua").resume() end,
      desc = "FZF: Resume last fzf session",
    },
    {
      "<leader>fb",
      function() require("fzf-lua").buffers() end,
      desc = "FZF: Buffers",
    },
    {
      "<leader>fh",
      function() require("fzf-lua").help_tags() end,
      desc = "FZF: Help tags",
    },
    {
      "<leader>fk",
      function() require("fzf-lua").keymaps() end,
      desc = "FZF: Keymaps",
    },
    {
      "<leader>fr",
      function() require("fzf-lua").registers() end,
      desc = "FZF: Registers",
    },
    {
      "<leader>f'",
      function() require("fzf-lua").marks() end,
      desc = "FZF: Find marks",
    },
    {
      "<leader>fc",
      function() require("fzf-lua").grep_cword() end,
      desc = "FZF: Find word under cursor",
    },
    {
      "<leader>fv",
      function() require("fzf-lua").grep_visual() end,
      mode = "v",
      desc = "FZF: Find visual selection",
    },
    {
      "<leader>ff",
      function() require("fzf-lua").files() end,
      desc = "FZF: Find files",
    },
    {
      "<leader>fw",
      function() require("fzf-lua").live_grep() end,
      desc = "FZF: Live grep",
    },
    {
      "<leader>gc",
      function() require("fzf-lua").git_bcommits() end,
      desc = "FZF: List commits for current buffer (bcommits)",
    },
    {
      "<leader>gC",
      function() require("fzf-lua").git_commits() end,
      desc = "FZF: List commits for current directory",
    },
    {
      "<leader>gt",
      function() require("fzf-lua").git_status() end,
      desc = "FZF: Show git status",
    },
    {
      "<leader>df",
      function() require("fzf-lua").dap_breakpoints() end,
      desc = "FZF: DAP breakpoints",
    },
  },
  opts = function()
    local fzf_lua = require("fzf-lua")
    local fzf_lua_path = vim.fn.stdpath("data") .. "/fzf-lua"
    if not utils.is_directory(fzf_lua_path) then vim.fn.mkdir(fzf_lua_path, "p") end

    return {
      defaults = { formatter = "path.filename_first" },
      fzf_colors = {
        bg = { "bg", "Normal" },
        gutter = { "bg", "Normal" },
        info = { "fg", "Conditional" },
        scrollbar = { "bg", "Normal" },
        separator = { "fg", "Comment" },
      },
      winopts = {
        width = 999,
        border = "single",
        preview = {
          default = "bat", -- seems to be faster than builtin (treesitter)
          border = "noborder",
          horizontal = "right:40%",
        },
      },
      previewers = {
        bat = { args = "--color=always --style=numbers,changes --line-range=:" .. vim.g.max_file.lines },
      },
      fzf_opts = {
        ["--history"] = utils.join_paths(fzf_lua_path, "fzf-lua-history"),
      },
      keymap = {
        builtin = {
          ["<C-d>"] = "preview-page-down",
          ["<C-u>"] = "preview-page-up",
          ["<C-z>"] = "toggle-fullscreen",
          ["<F4>"] = "toggle-preview",
        },
        fzf = {
          ["ctrl-f"] = "half-page-down",
          ["ctrl-b"] = "half-page-up",
          ["ctrl-a"] = "beginning-of-line",
          ["ctrl-e"] = "end-of-line",
          ---Only valid with fzf previewers (bat/cat/git/etc)
          ["f4"] = "toggle-preview",
          ["ctrl-d"] = "preview-page-down",
          ["ctrl-u"] = "preview-page-up",
          ---https://github.com/ibhagwan/fzf-lua/issues/546#issuecomment-1736076539
          ["ctrl-q"] = "select-all+accept",
          ["ctrl-h"] = "previous-history",
          ["ctrl-l"] = "next-history",
          ["ctrl-n"] = "down",
          ["ctrl-p"] = "up",
        },
      },
      actions = {
        files = {
          ["default"] = fzf_lua.actions.file_edit_or_qf,
        },
        buffers = {
          ["default"] = fzf_lua.actions.buf_edit_or_qf,
        },
      },
      grep = {
        rg_opts = "--column --line-number --no-heading --color=always --hidden --smart-case --max-columns=4096 -e",
        rg_glob = true,
      },
      dap = {
        breakpoints = {
          actions = {
            ["ctrl-q"] = function(_, opts)
              ---Lists all breakpoints and log points in quickfix window.
              ---https://github.com/ibhagwan/fzf-lua/wiki/Advanced#keybind-handlers
              require("dap").list_breakpoints()
              vim.cmd(opts.copen or "botright copen")
            end,
          },
        },
      },
      helptags = {
        actions = {
          ["default"] = fzf_lua.actions.help_tab,
        },
      },
      lsp = {
        formatter = "path.filename_first",
        code_actions = {
          previewer = "codeaction_native",
        },
      },
    }
  end,
  config = function(_, opts)
    local fzf_lua = require("fzf-lua")
    fzf_lua.setup(opts)
    ---https://github.com/ibhagwan/fzf-lua?tab=readme-ov-file#neovim-api
    ---https://github.com/ibhagwan/fzf-lua/wiki#automatic-sizing-of-heightwidth-of-vimuiselect
    fzf_lua.register_ui_select(function(_, items)
      local min_h, max_h = 0.15, 0.70
      local h = (#items + 4) / vim.o.lines
      if h < min_h then
        h = min_h
      elseif h > max_h then
        h = max_h
      end
      return { winopts = { height = h, width = 0.60, row = 0.40 } }
    end)
  end,
}

return M.fzf_lua
