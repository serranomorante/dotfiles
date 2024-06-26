local tools = require("serranomorante.tools")
local augroup = vim.api.nvim_create_augroup
local autocmd = vim.api.nvim_create_autocmd

local function run_linters(args)
  if vim.b[args.buf].large_buf then
    require("lint").linters_by_ft[vim.bo[args.buf].filetype] = {}
    return vim.diagnostic.reset(nil, args.buf)
  end
  require("lint").try_lint()
end

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
    local linters_augroup = augroup("run_linters", { clear = true })
    autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, {
      desc = "Run linters",
      group = linters_augroup,
      callback = run_linters,
    })
    autocmd("User", {
      desc = "Run linters on undo redo",
      pattern = { "CustomUndo", "CustomRedo" },
      group = linters_augroup,
      callback = run_linters,
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
    run_linters({ buf = vim.api.nvim_get_current_buf() }) -- Trigger on first load
  end,
}
