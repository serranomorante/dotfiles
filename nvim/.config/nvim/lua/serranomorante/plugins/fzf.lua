local utils = require("serranomorante.utils")

local M = {}

local keys = function()
  vim.keymap.set(
    "n",
    "<leader>f<CR>",
    function() require("fzf-lua").resume() end,
    { desc = "FZF: Resume last fzf session" }
  )
  vim.keymap.set("n", "<leader>fb", function() require("fzf-lua").buffers() end, { desc = "FZF: Buffers" })
  vim.keymap.set("n", "<leader>fh", function() require("fzf-lua").help_tags() end, { desc = "FZF: Help tags" })
  vim.keymap.set("n", "<leader>fk", function() require("fzf-lua").keymaps() end, { desc = "FZF: Keymaps" })
  vim.keymap.set("n", "<leader>fr", function() require("fzf-lua").registers() end, { desc = "FZF: Registers" })
  vim.keymap.set("n", "<leader>f'", function() require("fzf-lua").marks() end, { desc = "FZF: Find marks" })
  vim.keymap.set(
    "n",
    "<leader>fc",
    function() require("fzf-lua").grep_cword() end,
    { desc = "FZF: Find word under cursor" }
  )
  vim.keymap.set(
    "v",
    "<leader>fv",
    function() require("fzf-lua").grep_visual() end,
    { desc = "FZF: Find visual selection" }
  )
  vim.keymap.set("n", "<leader>ff", function() require("fzf-lua").files() end, { desc = "FZF: Find files" })
  vim.keymap.set("n", "<leader>fw", function() require("fzf-lua").live_grep() end, { desc = "FZF: Live grep" })
  vim.keymap.set(
    "n",
    "<leader>gc",
    function() require("fzf-lua").git_bcommits() end,
    { desc = "FZF: List commits for current buffer (bcommits)" }
  )
  vim.keymap.set(
    "n",
    "<leader>gC",
    function() require("fzf-lua").git_commits() end,
    { desc = "FZF: List commits for current directory" }
  )
  vim.keymap.set("n", "<leader>gt", function() require("fzf-lua").git_status() end, { desc = "FZF: Show git status" })
  vim.keymap.set(
    "n",
    "<leader>df",
    function() require("fzf-lua").dap_breakpoints() end,
    { desc = "FZF: DAP breakpoints" }
  )
end

local opts = function()
  local fzf_lua = require("fzf-lua")
  local fzf_lua_path = vim.fn.stdpath("data") .. "/fzf-lua"
  if not utils.is_directory(fzf_lua_path) then vim.fn.mkdir(fzf_lua_path, "p") end

  return {
    defaults = { formatter = "path.filename_first" },
    winopts = {
      width = 999,
      border = "single",
      preview = {
        wrap = "wrap",
        default = "bat", -- better performance than treesitter
        border = "noborder",
        horizontal = "right:40%",
      },
    },
    previewers = {
      bat = { args = "--color=always --style=numbers,changes --line-range=:" .. vim.g.max_file.lines },
      builtin = {
        syntax_limit_l = vim.g.max_file.lines,
        syntax_limit_b = vim.g.max_file.size,
      },
    },
    fzf_opts = {
      ["--header-lines"] = false, -- https://github.com/ibhagwan/fzf-lua/issues/569#issuecomment-1329342154
      ["--history"] = utils.join_paths(fzf_lua_path, "fzf-lua-history"),
    },
    keymap = {
      builtin = {
        ["<C-d>"] = "preview-half-page-down",
        ["<C-u>"] = "preview-half-page-up",
        ["<C-z>"] = "toggle-fullscreen",
        ["<F4>"] = "toggle-preview",
      },
      fzf = {
        ["ctrl-a"] = "beginning-of-line",
        ["ctrl-e"] = "end-of-line",
        ---Only valid with fzf previewers (bat/cat/git/etc)
        ["f4"] = "toggle-preview",
        ["ctrl-d"] = "preview-half-page-down",
        ["ctrl-u"] = "preview-half-page-up",
        ---https://github.com/ibhagwan/fzf-lua/issues/546#issuecomment-1736076539
        ["ctrl-q"] = "select-all+accept",
      },
    },
    actions = {
      files = {
        ["enter"] = fzf_lua.actions.file_edit_or_qf,
      },
    },
    grep = {
      rg_glob = true,
      RIPGREP_CONFIG_PATH = vim.env.RIPGREP_CONFIG_PATH,
      rg_glob_fn = function(query, opts)
        local regex, flags = query:match("^(.-)%s%-%-(.*)$")
        -- If no separator is detected will return the original query
        return (regex or query), flags
      end,
      multiline = 1, -- https://github.com/ibhagwan/fzf-lua/commit/b2d6b82aae8103f3390a685339394252ddd69ebf
      keymap = { fzf = { start = "beginning-of-line" } },
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
        ["enter"] = fzf_lua.actions.help_tab,
      },
    },
    lsp = {
      formatter = "path.filename_first",
      code_actions = {
        previewer = "codeaction_native",
      },
    },
  }
end

M.config = function()
  keys()
  local fzf_lua = require("fzf-lua")
  fzf_lua.setup(opts())
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
end

return M
