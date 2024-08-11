local tools = require("serranomorante.tools")
local utils = require("serranomorante.utils")

return {
  "stevearc/conform.nvim",
  cmd = "ConformInfo",
  keys = {
    {
      "<leader>lf",
      function()
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
      end,
      mode = { "n", "v" },
      desc = "Formatting: Format file or range",
    },
  },
  opts = {
    formatters_by_ft = {
      lua = tools.by_filetype.lua.formatters,
      javascript = vim.tbl_extend("force", tools.by_filetype.javascript.formatters, { stop_after_first = true }),
      typescript = vim.tbl_extend("force", tools.by_filetype.typescript.formatters, { stop_after_first = true }),
      javascriptreact = vim.tbl_extend(
        "force",
        tools.by_filetype.javascriptreact.formatters,
        { stop_after_first = true }
      ),
      typescriptreact = vim.tbl_extend(
        "force",
        tools.by_filetype.typescriptreact.formatters,
        { stop_after_first = true }
      ),
      python = { lsp_format = "fallback" },
      json = vim.tbl_extend("force", tools.by_filetype.json.formatters, { stop_after_first = true }),
      jsonc = vim.tbl_extend("force", tools.by_filetype.json.formatters, { stop_after_first = true }),
      markdown = vim.tbl_extend("force", tools.by_filetype.markdown.formatters, { stop_after_first = true }),
      bash = vim.tbl_extend("force", tools.by_filetype.bash.formatters, { stop_after_first = true }),
      sh = vim.tbl_extend("force", tools.by_filetype.bash.formatters, { stop_after_first = true }),
      c = { lsp_format = "fallback" },
    },
    log_level = vim.log.levels[vim.env.CONFORM_LOG_LEVEL or "ERROR"],
  },
}
