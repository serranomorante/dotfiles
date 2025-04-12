local M = {}

local keys = function(bufnr)
  ---@param desc string
  local function opts_for(desc) return { buffer = bufnr, desc = "Git: " .. desc } end

  local gs = require("gitsigns")
  local ts_repeat_move = require("nvim-treesitter.textobjects.repeatable_move")
  local next_hunk_repeat, prev_hunk_repeat = ts_repeat_move.make_repeatable_move_pair(
    function() gs.nav_hunk("next") end,
    function() gs.nav_hunk("prev") end
  )

  vim.keymap.set("n", "<leader>gl", function() gs.blame_line() end, opts_for("Blame line"))
  vim.keymap.set("n", "<leader>gL", function() gs.blame_line({ full = true }) end, opts_for("Blame full buffer"))
  vim.keymap.set("n", "<leader>gd", function() gs.diffthis() end, opts_for("Diff this"))
  vim.keymap.set("n", "<leader>gp", function() gs.preview_hunk() end, opts_for("Preview hunk"))
  vim.keymap.set({ "n", "x", "o" }, "]g", next_hunk_repeat, opts_for("Next hunk"))
  vim.keymap.set({ "n", "x", "o" }, "[g", prev_hunk_repeat, opts_for("Prev hunk"))
  vim.keymap.set({ "n", "x", "o" }, "]G", function() gs.nav_hunk("last") end, opts_for("First hunk"))
  vim.keymap.set({ "n", "x", "o" }, "[G", function() gs.nav_hunk("first") end, opts_for("Last hunk"))
  vim.keymap.set("n", "<leader>gs", function() gs.stage_hunk() end, opts_for("Stage hunk"))
  vim.keymap.set("n", "<leader>gh", function() gs.reset_hunk() end, opts_for("Reset hunk"))
  vim.keymap.set(
    "x",
    "<leader>gs",
    function() gs.stage_hunk({ vim.fn.line("."), vim.fn.line("v") }) end,
    opts_for("Stage hunk (partial)")
  )
  vim.keymap.set(
    "x",
    "<leader>gh",
    function() gs.reset_hunk({ vim.fn.line("."), vim.fn.line("v") }) end,
    opts_for("Reset hunk (partial)")
  )
  vim.keymap.set("n", "<leader>gS", function() gs.stage_buffer() end, opts_for("Stage buffer"))
  vim.keymap.set("n", "<leader>gH", function() gs.reset_buffer() end, opts_for("Reset buffer"))
  vim.keymap.set({ "o", "x" }, "ih", "<cmd>Gitsigns select_hunk<CR>", opts_for("Select hunk"))
  vim.keymap.set("n", "<leader>td", gs.preview_hunk_inline, opts_for("Toggle deleted"))
end

local function opts()
  return {
    worktrees = vim.g.git_worktrees,
    attach_to_untracked = true,
    max_file_length = vim.g.max_file.lines,
    sign_priority = 23,
    on_attach = keys,
  }
end

function M.config() require("gitsigns").setup(opts()) end

return M
