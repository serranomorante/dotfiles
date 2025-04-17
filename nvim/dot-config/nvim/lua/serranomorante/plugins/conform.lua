local tools = require("serranomorante.tools")
local utils = require("serranomorante.utils")

local M = {}

M.PLUGIN = "conform"

---@type conform.DefaultFormatOpts
local FORMAT_OPTS = {
  async = true,
  timeout_ms = 5000, -- we still have to use this for the `formatexpr` to work, maybe a bug?
  lsp_format = "never",
}

local function init()
  ---https://github.com/stevearc/conform.nvim/pull/238#issuecomment-1846253082
  vim.api.nvim_create_autocmd("FileType", {
    desc = "Set formatexpr per buffer using conform.formatexpr",
    pattern = vim.tbl_keys(require("conform").formatters_by_ft),
    group = vim.api.nvim_create_augroup("conform_formatexpr", { clear = true }),
    callback = function(args)
      vim.bo[args.buf].formatexpr = string.format("v:lua.require'conform'.formatexpr(%s)", vim.fn.string(FORMAT_OPTS))
    end,
  })
end

local function keys()
  vim.keymap.set({ "n", "v" }, "<leader>lf", function() require("conform").format(FORMAT_OPTS) end, {
    desc = "Conform: Format file or range",
  })
end

---@param fmts string[]
---@param opts conform.DefaultFiletypeFormatOpts?
---@return conform.FiletypeFormatter
local function gen_fmt(fmts, opts) return vim.tbl_extend("force", fmts, opts or {}) end

function M.opts()
  local ft_tools = tools.by_filetype
  ---@type conform.setupOpts
  return {
    formatters_by_ft = {
      c = { lsp_format = "fallback" },
      python = { lsp_format = "fallback" },
      lua = ft_tools.lua.fmts,
      html = gen_fmt(ft_tools.html.fmts, { stop_after_first = true }),
      go = gen_fmt(ft_tools.go.fmts, { stop_after_first = true }),
      sh = gen_fmt(ft_tools.sh.fmts, { stop_after_first = true }),
      bash = gen_fmt(ft_tools.bash.fmts, { stop_after_first = true }),
      json = gen_fmt(ft_tools.json.fmts, { stop_after_first = true }),
      jsonc = gen_fmt(ft_tools.json.fmts, { stop_after_first = true }),
      markdown = gen_fmt(ft_tools.markdown.fmts, { stop_after_first = true }),
      javascript = gen_fmt(ft_tools.javascript.fmts, { stop_after_first = true }),
      typescript = gen_fmt(ft_tools.typescript.fmts, { stop_after_first = true }),
      javascriptreact = gen_fmt(ft_tools.javascriptreact.fmts, { stop_after_first = true }),
      typescriptreact = gen_fmt(ft_tools.typescriptreact.fmts, { stop_after_first = true }),
      ["yaml.ansible"] = gen_fmt(vim.tbl_get(ft_tools, "yaml.ansible").fmts),
    },
    default_format_opts = FORMAT_OPTS,
    log_level = vim.log.levels[vim.env.CONFORM_LOG_LEVEL or "ERROR"],
  }
end

function M.config()
  init()
  keys()

  local conform = require(M.PLUGIN)
  conform.setup(M.opts())

  local format = conform.format
  ---Patch `conform.format(...)` to always have a callback, even on `conform.formatexpr()` calls.
  ---@param opts? conform.FormatOpts
  ---@param callback? fun(err: nil|string, did_edit: nil|boolean) Called once formatting has completed
  ---@return boolean True if any formatters were attempted
  local function format_patch(opts, callback)
    _ = callback
    vim.api.nvim_echo({ { "[Conform]: formatting...", "DiagnosticInfo" } }, false, {})
    return format(opts, function(err)
      ---https://github.com/stevearc/conform.nvim/issues/250#issuecomment-1868544121
      if err then return vim.notify(err, vim.log.levels.WARN) end
      utils.refresh_codelens()
      vim.api.nvim_echo({ { "[Conform]: format done.", "DiagnosticOk" } }, false, {})
    end)
  end
  conform.format = format_patch

  conform.formatters["ansible-lint"] = {
    prepend_args = {
      "--config-file",
      vim.fn.stdpath("config") .. "/lua/serranomorante/plugins/coc/ansible-lint-dev.yaml",
    },
  }
end

return M
