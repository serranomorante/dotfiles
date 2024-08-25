local M = {}

local opts = function()
  return {
    worktrees = vim.g.git_worktrees,
    attach_to_untracked = true,
    max_file_length = vim.g.max_file.lines,
  }
end

local keys = function()
  vim.keymap.set("n", "<leader>gl", function() require("gitsigns").blame_line() end, { desc = "Git: Blame line" })
  vim.keymap.set(
    "n",
    "<leader>gL",
    function() require("gitsigns").blame_line({ full = true }) end,
    { desc = "Git: Blame full buffer" }
  )
  vim.keymap.set("n", "<leader>gd", function() require("gitsigns").diffthis() end, { desc = "Git: Diff this" })
  vim.keymap.set("n", "<leader>gp", function() require("gitsigns").preview_hunk() end, { desc = "Git: Preview hunk" })
  vim.keymap.set("n", "]g", function() require("gitsigns").next_hunk() end, { desc = "Git: Next hunk" })
  vim.keymap.set("n", "[g", function() require("gitsigns").prev_hunk() end, { desc = "Git: Prev hunk" })
  vim.keymap.set("n", "<leader>gh", function() require("gitsigns").reset_hunk() end, { desc = "Git: Reset hunk" })
  vim.keymap.set({ "n", "v" }, "<leader>gh", ":Gitsigns reset_hunk<CR>", { desc = "Git: Reset hunk (partial)" })
  vim.keymap.set("n", "<leader>gH", function() require("gitsigns").reset_buffer() end, { desc = "Git: Reset buffer" })
  vim.keymap.set("n", "<leader>gS", function() require("gitsigns").stage_buffer() end, { desc = "Git: Stage buffer" })
  vim.keymap.set("n", "<leader>gs", function() require("gitsigns").stage_hunk() end, { desc = "Git: Stage hunk" })
  vim.keymap.set({ "n", "v" }, "<leader>gs", ":Gitsigns stage_hunk<CR>", { desc = "Git: Stage hunk (partial)" })
  vim.keymap.set(
    "n",
    "<leader>gu",
    function() require("gitsigns").undo_stage_hunk() end,
    { desc = "Git: Unstage hunk" }
  )
end

M.config = function()
  keys()
  require("gitsigns").setup(opts())
end

return M
