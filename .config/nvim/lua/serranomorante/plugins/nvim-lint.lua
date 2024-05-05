local tools = require("serranomorante.tools")
local augroup = vim.api.nvim_create_augroup
local autocmd = vim.api.nvim_create_autocmd

return {
  "mfussenegger/nvim-lint",
  event = { "BufReadPre", "BufReadPost" },
  keys = {
    {
      "<leader>lt",
      function() require("lint").try_lint() end,
      desc = "Linting: Lint current file",
    },
  },
  init = function()
    autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, {
      desc = "Run linters",
      group = augroup("run_linters", { clear = true }),
      callback = function() require("lint").try_lint() end,
    })
    autocmd("User", {
      desc = "Run linters on undo redo",
      group = augroup("run_linter_on_undo_redo", { clear = true }),
      pattern = { "CustomUndo", "CustomRedo" },
      callback = function() require("lint").try_lint() end,
    })
  end,
  config = function()
    local lint = require("lint")
    lint.linters_by_ft = {
      javascript = tools.by_filetype.javascript.linters,
      typescript = tools.by_filetype.javascript.linters,
      javascriptreact = tools.by_filetype.javascript.linters,
      typescriptreact = tools.by_filetype.javascript.linters,
      python = tools.by_filetype.python.linters,
    }
    lint.try_lint() -- Trigger on first load
  end,
}
