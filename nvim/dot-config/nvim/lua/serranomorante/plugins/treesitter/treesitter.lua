local utils = require("serranomorante.utils")
local tools = require("serranomorante.tools")

local parser_dir = vim.fn.stdpath("data") .. "/treesitter"
if not utils.is_directory(parser_dir) then vim.fn.mkdir(parser_dir, "p") end

local M = {}

local init = function() vim.opt.runtimepath:prepend(parser_dir) end

local opts = function()
  return {
    parser_install_dir = parser_dir,
    ensure_installed = utils.merge_tools(
      "treesitter",
      tools.by_filetype.javascript,
      tools.by_filetype.go,
      tools.by_filetype.c,
      tools.by_filetype.rust,
      tools.by_filetype.fish,
      tools.by_filetype.toml,
      tools.by_filetype.lua,
      tools.by_filetype.json,
      tools.by_filetype.yaml,
      tools.by_filetype.bash,
      tools.by_filetype.tmux,
      tools.by_filetype.vim,
      tools.by_filetype.diff,
      tools.by_filetype.markdown,
      tools.by_filetype.gitcommit,
      tools.by_filetype.html,
      tools.by_filetype.xml,
      tools.by_filetype.css,
      tools.by_filetype.python,
      tools.by_filetype.php,
      tools.by_filetype.all
    ),
    highlight = {
      enable = true,
      disable = function(_, bufnr) return vim.b[bufnr].large_buf end,
    },
    incremental_selection = {
      enable = false,
      disable = function(_, bufnr) return vim.b[bufnr].large_buf end,
    },
    indent = {
      enable = true,
      disable = function(_, bufnr) return vim.b[bufnr].large_buf end,
    },
    textobjects = {
      select = {
        enable = true,
        lookahead = true,
        keymaps = {
          ["ak"] = { query = "@block.outer", desc = "Treesitter: around block" },
          ["ik"] = { query = "@block.inner", desc = "Treesitter: inside block" },
          ["ac"] = { query = "@class.outer", desc = "Treesitter: around class" },
          ["ic"] = { query = "@class.inner", desc = "Treesitter: inside class" },
          ["a?"] = { query = "@conditional.outer", desc = "Treesitter: around conditional" },
          ["i?"] = { query = "@conditional.inner", desc = "Treesitter: inside conditional" },
          ["af"] = { query = "@function.outer", desc = "Treesitter: around function" },
          ["if"] = { query = "@function.inner", desc = "Treesitter: inside function" },
          ["al"] = { query = "@loop.outer", desc = "Treesitter: around loop" },
          ["il"] = { query = "@loop.inner", desc = "Treesitter: inside loop" },
          ["aa"] = { query = "@parameter.outer", desc = "Treesitter: around argument" },
          ["ia"] = { query = "@parameter.inner", desc = "Treesitter: inside argument" },
        },
      },
      move = {
        enable = true,
        set_jumps = true,
        goto_next_start = {
          ["]k"] = { query = "@block.outer", desc = "Treesitter: Next block start" },
          ["]f"] = { query = "@function.outer", desc = "Treesitter: Next function start" },
          ["]a"] = { query = "@parameter.inner", desc = "Treesitter: Next argument start" },
        },
        goto_next_end = {
          ["]K"] = { query = "@block.outer", desc = "Treesitter: Next block end" },
          ["]F"] = { query = "@function.outer", desc = "Treesitter: Next function end" },
          ["]A"] = { query = "@parameter.inner", desc = "Treesitter: Next argument end" },
        },
        goto_previous_start = {
          ["[k"] = { query = "@block.outer", desc = "Treesitter: Previous block start" },
          ["[f"] = { query = "@function.outer", desc = "Treesitter: Previous function start" },
          ["[a"] = { query = "@parameter.inner", desc = "Treesitter: Previous argument start" },
        },
        goto_previous_end = {
          ["[K"] = { query = "@block.outer", desc = "Treesitter: Previous block end" },
          ["[F"] = { query = "@function.outer", desc = "Treesitter: Previous function end" },
          ["[A"] = { query = "@parameter.inner", desc = "Treesitter: Previous argument end" },
        },
      },
    },
  }
end

M.config = function()
  init()
  require("nvim-treesitter.configs").setup(opts())

  vim.treesitter.language.register("git_config", "systemd")
  vim.treesitter.language.register("git_config", "conf")
end

return M
