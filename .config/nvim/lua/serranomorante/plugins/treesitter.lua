local utils = require("serranomorante.utils")
local tools = require("serranomorante.tools")

return {
  {
    "JoosepAlviste/nvim-ts-context-commentstring",
    lazy = true,
    opts = { enable_autocmd = false },
    init = function() vim.g.skip_ts_context_commentstring_module = true end,
  },
  {
    "kevinhwang91/nvim-treesitter", -- see: https://github.com/kevinhwang91/nvim-bqf/issues/110#issuecomment-1509896444
    lazy = false,
    dependencies = "nvim-treesitter/nvim-treesitter-textobjects",
    cmd = {
      "TSBufDisable",
      "TSBufEnable",
      "TSBufToggle",
      "TSDisable",
      "TSEnable",
      "TSToggle",
      "TSInstall",
      "TSInstallInfo",
      "TSInstallSync",
      "TSModuleInfo",
      "TSUninstall",
      "TSUpdate",
      "TSUpdateSync",
    },
    build = ":TSUpdate",
    opts = {
      ensure_installed = utils.merge_tools(
        "treesitter",
        tools.by_filetype.javascript,
        tools.by_filetype.go,
        tools.by_filetype.c,
        tools.by_filetype.rust,
        tools.by_filetype.fish,
        tools.by_filetype.toml,
        tools.by_filetype.lua
      ),
      highlight = {
        enable = true,
        disable = function(_, bufnr) return vim.b[bufnr].large_buf end,
      },
      incremental_selection = {
        enable = true,
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
        swap = {
          enable = true,
          swap_next = {
            [">K"] = { query = "@block.outer", desc = "Treesitter: Swap next block" },
            [">F"] = { query = "@function.outer", desc = "Treesitter: Swap next function" },
            [">A"] = { query = "@parameter.inner", desc = "Treesitter: Swap next argument" },
          },
          swap_previous = {
            ["<K"] = { query = "@block.outer", desc = "Treesitter: Swap previous block" },
            ["<F"] = { query = "@function.outer", desc = "Treesitter: Swap previous function" },
            ["<A"] = { query = "@parameter.inner", desc = "Treesitter: Swap previous argument" },
          },
        },
      },
    },
    config = function(_, opts)
      require("nvim-treesitter.configs").setup(opts)
      local parser_config = require("nvim-treesitter.parsers").get_parser_configs()

      for _, parser in ipairs({ "typescript", "tsx" }) do
        parser_config[parser] = {
          install_info = {
            url = "~/repos/tree-sitter-typescript/" .. parser,
            files = { "src/parser.c", "src/scanner.c" },
            branch = "master",
            requires_generate_from_grammar = false, -- if folder contains pre-generated src/parser.c
            -- generate_requires_npm = false, -- if stand-alone parser without npm dependencies
          },
        }
      end
    end,
  },
}
