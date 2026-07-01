local persistent_scratch = require("serranomorante.persistent_scratch")

persistent_scratch.setup()

vim.keymap.set("n", "<leader>ss", function() persistent_scratch.toggle() end, { desc = "Toggle persistent scratch" })
vim.keymap.set({ "x", "v" }, "<leader>sp", function() persistent_scratch.append_visual_selection() end, {
  desc = "Append visual selection to persistent scratch",
})
