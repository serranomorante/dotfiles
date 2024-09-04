local M = {}

local opts = function()
  return {
    worktrees = vim.g.git_worktrees,
    attach_to_untracked = true,
    max_file_length = vim.g.max_file.lines,
  }
end

local keys = function()
  local gs = require("gitsigns")
  local ts_repeat_move = require("nvim-treesitter.textobjects.repeatable_move")
  local next_hunk_repeat, prev_hunk_repeat = ts_repeat_move.make_repeatable_move_pair(gs.next_hunk, gs.prev_hunk)

  vim.keymap.set("n", "<leader>gl", function() gs.blame_line() end, { desc = "Git: Blame line" })
  vim.keymap.set("n", "<leader>gL", function() gs.blame_line({ full = true }) end, { desc = "Git: Blame full buffer" })
  vim.keymap.set("n", "<leader>gd", function() gs.diffthis() end, { desc = "Git: Diff this" })
  vim.keymap.set("n", "<leader>gp", function() gs.preview_hunk() end, { desc = "Git: Preview hunk" })
  vim.keymap.set({ "n", "x", "o" }, "]g", next_hunk_repeat, { desc = "Git: Next hunk" })
  vim.keymap.set({ "n", "x", "o" }, "[g", prev_hunk_repeat, { desc = "Git: Prev hunk" })
  vim.keymap.set("n", "<leader>gh", function() gs.reset_hunk() end, { desc = "Git: Reset hunk" })
  vim.keymap.set({ "n", "v" }, "<leader>gh", ":Gitsigns reset_hunk<CR>", { desc = "Git: Reset hunk (partial)" })
  vim.keymap.set("n", "<leader>gH", function() gs.reset_buffer() end, { desc = "Git: Reset buffer" })
  vim.keymap.set("n", "<leader>gS", function() gs.stage_buffer() end, { desc = "Git: Stage buffer" })
  vim.keymap.set("n", "<leader>gs", function() gs.stage_hunk() end, { desc = "Git: Stage hunk" })
  vim.keymap.set({ "n", "v" }, "<leader>gs", ":Gitsigns stage_hunk<CR>", { desc = "Git: Stage hunk (partial)" })
  vim.keymap.set("n", "<leader>gu", function() gs.undo_stage_hunk() end, { desc = "Git: Unstage hunk" })
end

M.config = function()
  keys()
  require("gitsigns").setup(opts())
end

return M
