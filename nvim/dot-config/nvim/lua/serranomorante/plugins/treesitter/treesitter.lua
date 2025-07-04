local utils = require("serranomorante.utils")
local tools = require("serranomorante.tools")

local M = {}

local function opts()
  return {
    ensure_installed = utils.merge_tools(
      "treesitter",
      tools.by_filetype.asm,
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
      tools.by_filetype.svelte,
      tools.by_filetype.all
    ),
    highlight = {
      enable = true,
      disable = function(_, bufnr) return vim.b[bufnr].large_buf end,
      additional_vim_regex_highlighting = { "html" },
    },
    incremental_selection = {
      enable = false,
      disable = function(_, bufnr) return vim.b[bufnr].large_buf end,
    },
    indent = {
      enable = true,
      disable = function(_, bufnr)
        if vim.api.nvim_get_option_value("filetype", { buf = bufnr }) == "html" then return true end
        local ok, large_buf = pcall(vim.api.nvim_buf_get_var, bufnr, "large_buf")
        return ok and large_buf
      end,
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

function M.config()
  require("nvim-treesitter.configs").setup(opts())

  ---@class CustomParserInfo: ParserInfo
  ---@field org ParserInfo
  ---@type CustomParserInfo
  local parser_config = require("nvim-treesitter.parsers").get_parser_configs()

  parser_config.org = {
    install_info = {
      url = "https://github.com/milisims/tree-sitter-org",
      revision = "main",
      files = { "src/parser.c", "src/scanner.c" },
    },
    filetype = "org",
    maintainers = { "@milisims" },
  }

  vim.treesitter.language.register("git_config", "systemd")
  vim.treesitter.language.register("git_config", "conf")
  vim.treesitter.language.register("vue", "html")
  vim.treesitter.language.register("ssh_config", "sshdconfig")
  vim.treesitter.language.register("git_config", "cfg")
end

return M
