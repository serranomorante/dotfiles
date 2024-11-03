local tools = require("serranomorante.tools")
local utils = require("serranomorante.utils")

local M = {}

local function init()
  ---https://github.com/stevearc/conform.nvim/pull/238#issuecomment-1846253082
  vim.api.nvim_create_autocmd("FileType", {
    desc = "Set formatexpr per buffer using conform.formatexpr",
    pattern = vim.tbl_keys(require("conform").formatters_by_ft),
    group = vim.api.nvim_create_augroup("conform_formatexpr", { clear = true }),
    callback = function() vim.opt_local.formatexpr = [[v:lua.require'conform'.formatexpr({ 'lsp_format': 'never' })]] end,
  })
end

local keys = function()
  vim.keymap.set({ "n", "v" }, "<leader>lf", function()
    require("conform").format(nil, function(err)
      ---https://github.com/stevearc/conform.nvim/issues/250#issuecomment-1868544121
      if err then return vim.notify(err, vim.log.levels.WARN) end
      utils.refresh_codelens()
      vim.notify("[Conform] format done.", vim.log.levels.INFO)
    end)
  end, {
    desc = "Conform: Format file or range",
  })
end

local function opts()
  return {
    formatters_by_ft = {
      c = { lsp_format = "fallback" },
      lua = tools.by_filetype.lua.formatters,
      python = { lsp_format = "fallback" },
      javascript = { stop_after_first = true, unpack(tools.by_filetype.javascript.formatters) },
      typescript = { stop_after_first = true, unpack(tools.by_filetype.typescript.formatters) },
      javascriptreact = { stop_after_first = true, unpack(tools.by_filetype.javascriptreact.formatters) },
      typescriptreact = { stop_after_first = true, unpack(tools.by_filetype.typescriptreact.formatters) },
      sh = { stop_after_first = true, unpack(tools.by_filetype.bash.formatters) },
      bash = { stop_after_first = true, unpack(tools.by_filetype.bash.formatters) },
      json = { stop_after_first = true, unpack(tools.by_filetype.json.formatters) },
      jsonc = { stop_after_first = true, unpack(tools.by_filetype.json.formatters) },
      markdown = { stop_after_first = true, unpack(tools.by_filetype.markdown.formatters) },
    },
    default_format_opts = {
      lsp_format = "never",
    },
    log_level = vim.log.levels[vim.env.CONFORM_LOG_LEVEL or "ERROR"],
  }
end

M.config = function()
  init()
  keys()
  require("conform").setup(opts())
end

return M
