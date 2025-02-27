local tools = require("serranomorante.tools")
local utils = require("serranomorante.utils")

local M = {}

local function init()
  ---https://github.com/stevearc/conform.nvim/pull/238#issuecomment-1846253082
  vim.api.nvim_create_autocmd("FileType", {
    desc = "Set formatexpr per buffer using conform.formatexpr",
    pattern = vim.tbl_keys(require("conform").formatters_by_ft),
    group = vim.api.nvim_create_augroup("conform_formatexpr", { clear = true }),
    callback = function(args)
      vim.bo[args.buf].formatexpr = [[v:lua.require'conform'.formatexpr({ 'lsp_format': 'never' })]]
    end,
  })
end

local keys = function()
  vim.keymap.set({ "n", "v" }, "<leader>lf", function()
    require("conform").format(nil, function(err)
      ---https://github.com/stevearc/conform.nvim/issues/250#issuecomment-1868544121
      if err then return vim.notify(err, vim.log.levels.WARN) end
      utils.refresh_codelens()
      vim.notify("[Conform]: format done.", vim.log.levels.INFO)
    end)
  end, {
    desc = "Conform: Format file or range",
  })
end

---@param fmts string[]
---@param opts table
---@return conform.FiletypeFormatter
local function gen_fmt(fmts, opts) return vim.tbl_extend("force", fmts, opts) end

local function opts()
  local ft_tools = tools.by_filetype
  ---@type conform.setupOpts
  return {
    formatters_by_ft = {
      c = { lsp_format = "fallback" },
      python = { lsp_format = "fallback" },
      lua = ft_tools.lua.fmts,
      sh = gen_fmt(ft_tools.bash.fmts, { stop_after_first = true }),
      bash = gen_fmt(ft_tools.bash.fmts, { stop_after_first = true }),
      json = gen_fmt(ft_tools.json.fmts, { stop_after_first = true }),
      jsonc = gen_fmt(ft_tools.json.fmts, { stop_after_first = true }),
      markdown = gen_fmt(ft_tools.markdown.fmts, { stop_after_first = true }),
      javascript = gen_fmt(ft_tools.javascript.fmts, { stop_after_first = true }),
      typescript = gen_fmt(ft_tools.typescript.fmts, { stop_after_first = true }),
      javascriptreact = gen_fmt(ft_tools.javascriptreact.fmts, { stop_after_first = true }),
      typescriptreact = gen_fmt(ft_tools.typescriptreact.fmts, { stop_after_first = true }),
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
