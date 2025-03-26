local M = {}

local utils = require("serranomorante.utils")
local tools = require("serranomorante.tools")
local event_handlers = require("serranomorante.plugins.coc.event_handlers")
local coc_utils = require("serranomorante.plugins.coc.utils")
local binaries = require("serranomorante.binaries")

local coc_custom_group = vim.api.nvim_create_augroup("coc_custom_config", { clear = true })

local init = function()
  vim.g.coc_start_at_startup = 0
  vim.g.coc_user_config = vim.fn.stdpath("config") .. "/lua/serranomorante/plugins/coc"
  vim.g.coc_config_home = vim.fn.stdpath("config") .. "/lua/serranomorante/plugins/coc"
  vim.g.coc_quickfix_open_command = 'lua require("serranomorante.utils").open_quickfix_list()'
  vim.g.coc_filetype_map = {
    ["yaml.ansible"] = "ansible",
  }
  vim.g.coc_global_extensions = utils.merge_tools(
    "coc",
    tools.by_filetype.javascript,
    tools.by_filetype.markdown,
    tools.by_filetype.json,
    tools.by_filetype.yaml,
    tools.by_filetype.html,
    tools.by_filetype.css,
    tools.by_filetype.php,
    tools.by_filetype.vue,
    tools.by_filetype.c,
    tools.by_filetype.all
  )
  vim.b.coc_force_attach = 1
  vim.api.nvim_set_hl(0, "CocMenuSel", { link = "PmenuSel" }) -- fix highlight
  vim.api.nvim_set_hl(0, "CocInlayHint", { link = "CursorColumn" })
  local ok, override_node = pcall(binaries.system_default_node)
  if ok and override_node then vim.g.coc_node_path = override_node end

  vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
    desc = "Disable coc on all buffers by default (before FileType event)",
    group = coc_custom_group,
    callback = function(args) vim.api.nvim_buf_set_var(args.buf, "coc_enabled", 0) end,
  })
end

M.config = function()
  init()

  vim.api.nvim_create_autocmd("VimLeavePre", {
    desc = "Teardown coc when exit vim",
    group = vim.api.nvim_create_augroup("teardown_coc", { clear = true }),
    callback = function()
      if vim.g.coc_process_pid then utils.cmd({ "kill", "-9", vim.g.coc_process_pid }) end
    end,
  })
end

---@class CocStartOpts
---@field bufnr integer

---Start and attach to buffer
---@param _ any reserved
---@param opts CocStartOpts
function M.start(_, opts)
  vim.api.nvim_buf_set_var(opts.bufnr, "coc_enabled", 1)
  vim.cmd.CocStart()

  local WAIT_MS = 20000 -- some servers can take a really long time
  utils.wait_until(function() return coc_utils.extension_ready(opts.bufnr) end, WAIT_MS):thenCall(
    function() event_handlers.attach(opts.bufnr) end,
    function(err) vim.notify(string.format("[COC]: failed to attach buf %d. %s", opts.bufnr, err), vim.log.levels.WARN) end
  )
end

return M
