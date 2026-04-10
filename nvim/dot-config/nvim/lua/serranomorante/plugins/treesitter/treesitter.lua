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

local function register_language_aliases()
  local aliases = {
    bash = { "sh" },
    git_config = { "gitconfig", "systemd", "conf", "cfg" },
    javascript = { "javascriptreact" },
    json = { "jsonc" },
    ssh_config = { "sshconfig", "sshdconfig" },
    tsx = { "typescriptreact" },
    udev = { "udevrules" },
    vue = { "html" },
    yaml = { "yaml.ansible" },
  }

  for lang, filetypes in pairs(aliases) do
    vim.treesitter.language.register(lang, filetypes)
  end
end

function M.config()
  require("nvim-treesitter-textobjects").setup({
    select = { lookahead = true },
    move = { set_jumps = true },
  })

  keys()

  register_language_aliases()
end

return M
