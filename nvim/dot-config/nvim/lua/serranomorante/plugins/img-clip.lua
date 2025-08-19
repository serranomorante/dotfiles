local M = {}

local function keys()
  vim.keymap.set("n", "<leader>p", "<cmd>PasteImage<CR>", { desc = "IMG: Paste image from system clipboard" })
end

local function opts()
  return {
    filetypes = {
      codecompanion = {
        prompt_for_file_name = false,
        template = "[Image]($FILE_PATH)",
        use_absolute_path = true,
      },
    },
  }
end

function M.config()
  keys()
  require("img-clip").setup(opts())
end

return M
