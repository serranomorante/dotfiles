local tools = require("serranomorante.tools")
local utils = require("serranomorante.utils")

local M = {}

local keys = function()
  vim.keymap.set({ "n", "v" }, "<leader>lf", function()
    require("conform").format(
      { async = true },
      ---@param err string|nil
      function(err)
        ---https://github.com/stevearc/conform.nvim/issues/250#issuecomment-1868544121
        if err then return vim.notify(err, vim.log.levels.WARN) end
        utils.refresh_codelens()
        vim.notify("Formatted", vim.log.levels.INFO)
      end
    )
  end, {
    desc = "Formatting: Format file or range",
  })
end

local opts = function()
  return {
    formatters_by_ft = {
      lua = tools.by_filetype.lua.formatters,
      javascript = tools.by_filetype.javascript.formatters,
      typescript = tools.by_filetype.typescript.formatters,
      javascriptreact = tools.by_filetype.javascriptreact.formatters,
      typescriptreact = tools.by_filetype.typescriptreact.formatters,
      python = { lsp_format = "fallback" },
      json = vim.tbl_extend("force", tools.by_filetype.json.formatters, { stop_after_first = true }),
      jsonc = vim.tbl_extend("force", tools.by_filetype.json.formatters, { stop_after_first = true }),
      markdown = vim.tbl_extend("force", tools.by_filetype.markdown.formatters, { stop_after_first = true }),
      bash = vim.tbl_extend("force", tools.by_filetype.bash.formatters, { stop_after_first = true }),
      sh = vim.tbl_extend("force", tools.by_filetype.bash.formatters, { stop_after_first = true }),
      c = { lsp_format = "fallback" },
    },
    log_level = vim.log.levels[vim.env.CONFORM_LOG_LEVEL or "ERROR"],
  }
end

M.config = function()
  keys()
  require("conform").setup(opts())
end

return M
