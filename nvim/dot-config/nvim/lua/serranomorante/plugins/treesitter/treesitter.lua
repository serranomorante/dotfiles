local utils = require("serranomorante.utils")
local tools = require("serranomorante.tools")

local M = {}

local function keys()
  local ts_select = require("nvim-treesitter-textobjects.select")
  local ts_move = require("nvim-treesitter-textobjects.move")
  --- SELECT
  vim.keymap.set(
    { "x", "o" },
    "ak",
    function() ts_select.select_textobject("@block.outer") end,
    { desc = "Treesitter: around block" }
  )
  vim.keymap.set(
    { "x", "o" },
    "ik",
    function() ts_select.select_textobject("@block.inner") end,
    { desc = "Treesitter: inside block" }
  )
  vim.keymap.set(
    { "x", "o" },
    "ac",
    function() ts_select.select_textobject("@class.outer") end,
    { desc = "Treesitter: around class" }
  )
  vim.keymap.set(
    { "x", "o" },
    "ic",
    function() ts_select.select_textobject("@class.inner") end,
    { desc = "Treesitter: inside class" }
  )
  vim.keymap.set(
    { "x", "o" },
    "a?",
    function() ts_select.select_textobject("@conditional.outer") end,
    { desc = "Treesitter: around conditional" }
  )
  vim.keymap.set(
    { "x", "o" },
    "i?",
    function() ts_select.select_textobject("@conditional.inner") end,
    { desc = "Treesitter: inside conditional" }
  )
  vim.keymap.set(
    { "x", "o" },
    "af",
    function() ts_select.select_textobject("@function.outer") end,
    { desc = "Treesitter: around function" }
  )
  vim.keymap.set(
    { "x", "o" },
    "if",
    function() ts_select.select_textobject("@function.inner") end,
    { desc = "Treesitter: inside function" }
  )
  vim.keymap.set(
    { "x", "o" },
    "al",
    function() ts_select.select_textobject("@loop.outer") end,
    { desc = "Treesitter: around loop" }
  )
  vim.keymap.set(
    { "x", "o" },
    "il",
    function() ts_select.select_textobject("@loop.inner") end,
    { desc = "Treesitter: inside loop" }
  )
  vim.keymap.set(
    { "x", "o" },
    "aa",
    function() ts_select.select_textobject("@parameter.outer") end,
    { desc = "Treesitter: around argument" }
  )
  vim.keymap.set(
    { "x", "o" },
    "ia",
    function() ts_select.select_textobject("@parameter.inner") end,
    { desc = "Treesitter: inside argument" }
  )

  --- MOVE
  vim.keymap.set(
    { "n", "x", "o" },
    "]k",
    function() ts_move.goto_next_start("@block.outer") end,
    { desc = "Treesitter: Next block start" }
  )
  vim.keymap.set(
    { "n", "x", "o" },
    "]f",
    function() ts_move.goto_next_start("@function.outer") end,
    { desc = "Treesitter: Next function start" }
  )
  vim.keymap.set(
    { "n", "x", "o" },
    "]a",
    function() ts_move.goto_next_start("@parameter.inner") end,
    { desc = "Treesitter: Next argument start" }
  )
  vim.keymap.set(
    { "n", "x", "o" },
    "]K",
    function() ts_move.goto_next_end("@block.outer") end,
    { desc = "Treesitter: Next block end" }
  )
  vim.keymap.set(
    { "n", "x", "o" },
    "]F",
    function() ts_move.goto_next_end("@function.outer") end,
    { desc = "Treesitter: Next function end" }
  )
  vim.keymap.set(
    { "n", "x", "o" },
    "]A",
    function() ts_move.goto_next_end("@parameter.inner") end,
    { desc = "Treesitter: Next argument end" }
  )
  vim.keymap.set(
    { "n", "x", "o" },
    "[k",
    function() ts_move.goto_previous_start("@block.outer") end,
    { desc = "Treesitter: Previous block start" }
  )
  vim.keymap.set(
    { "n", "x", "o" },
    "[f",
    function() ts_move.goto_previous_start("@function.outer") end,
    { desc = "Treesitter: Previous function start" }
  )
  vim.keymap.set(
    { "n", "x", "o" },
    "[a",
    function() ts_move.goto_previous_start("@parameter.inner") end,
    { desc = "Treesitter: Previous argument start" }
  )
  vim.keymap.set(
    { "n", "x", "o" },
    "[K",
    function() ts_move.goto_previous_end("@block.outer") end,
    { desc = "Treesitter: Previous block end" }
  )
  vim.keymap.set(
    { "n", "x", "o" },
    "[F",
    function() ts_move.goto_previous_end("@function.outer") end,
    { desc = "Treesitter: Previous function end" }
  )
  vim.keymap.set(
    { "n", "x", "o" },
    "[A",
    function() ts_move.goto_previous_end("@parameter.inner") end,
    { desc = "Treesitter: Previous argument end" }
  )
end

function M.config()
  require("nvim-treesitter").install(
    utils.merge_tools(
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
      tools.by_filetype.sshconfig,
      tools.by_filetype.gitignore,
      tools.by_filetype.editorconfig,
      tools.by_filetype.all
    )
  )

  require("nvim-treesitter-textobjects").setup({
    select = { lookahead = true },
    move = { set_jumps = true },
  })

  keys()

  vim.treesitter.language.register("git_config", "systemd")
  vim.treesitter.language.register("git_config", "conf")
  vim.treesitter.language.register("vue", "html")
  vim.treesitter.language.register("ssh_config", "sshdconfig")
  vim.treesitter.language.register("git_config", "cfg")

  vim.api.nvim_create_autocmd("User", {
    pattern = "TSUpdate",
    callback = function()
      for filetype, tool in pairs({ kitty = tools.by_filetype.kitty, org = tools.by_filetype.org }) do
        for _, parser in ipairs(tool.parsers) do
          if parser:sub(1, #"file:") == "file:" then -- "file:" is only from my dotfiles
            require("nvim-treesitter.parsers")[filetype] = {
              install_info = {
                path = "~/.config/nvim/parser/",
              },
            }
          end
        end
      end
    end,
  })
end

return M
