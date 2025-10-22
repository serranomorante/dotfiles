local M = {}

local function keys()
  vim.keymap.set("n", "<leader>p", "<cmd>PasteImage<CR>", { desc = "IMG: Paste image from system clipboard" })
end

local function opts()
  return {
    default = {
      use_absolute_path = true,
      relative_template_path = false,
      prompt_for_file_name = false,
    },
    filetypes = {
      codecompanion = {
        template = "[Image]($FILE_PATH)",
      },
    },
  }
end

function M.config()
  keys()
  require("img-clip").setup(opts())
end

return M
