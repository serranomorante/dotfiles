local package_loaded = pcall(vim.cmd.packadd, "nvim.undotree")
if not package_loaded then return end

vim.keymap.set("n", "<leader>uu", function()
  require("serranomorante.plugins.undotree").open()
end, { desc = "Toggle undotree" })
