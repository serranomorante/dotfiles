local tools = require("serranomorante.tools")
local utils = require("serranomorante.utils")

return {
  "stevearc/conform.nvim",
  dependencies = "mfussenegger/nvim-lint",
  cmd = "ConformInfo",
  keys = {
    {
      "<leader>lf",
      function()
        require("conform").format(
          {
            lsp_fallback = true, -- Make it compatible with `clang-format`
            async = false,
            timeout_ms = 10000,
          }, ---@param err string|nil
          function(err)
            ---https://github.com/stevearc/conform.nvim/issues/250#issuecomment-1868544121
            if err then return vim.notify(err, vim.log.levels.WARN) end
            if utils.is_available("nvim-lint") then require("lint").try_lint() end
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
      javascript = tools.by_filetype.javascript.formatters,
      typescript = { tools.by_filetype.javascript.formatters },
      javascriptreact = tools.by_filetype.javascript.formatters,
      typescriptreact = { tools.by_filetype.javascript.formatters },
      python = tools.by_filetype.python.formatters,
      go = tools.by_filetype.go.formatters,
      json = { tools.by_filetype.json.formatters },
      jsonc = { tools.by_filetype.json.formatters },
      markdown = { tools.by_filetype.markdown.formatters },
      fish = { tools.by_filetype.fish.formatters },
      bash = { tools.by_filetype.bash.formatters },
      sh = { tools.by_filetype.bash.formatters },
    },
    log_level = vim.log.levels[vim.env.CONFORM_LOG_LEVEL or "ERROR"],
  },
}
