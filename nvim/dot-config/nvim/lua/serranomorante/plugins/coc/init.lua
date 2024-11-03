local M = {}

local utils = require("serranomorante.utils")
local tools = require("serranomorante.tools")
local event_handlers = require("serranomorante.plugins.coc.event_handlers")
local binaries = require("serranomorante.binaries")

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
    tools.by_filetype.all
  )
  vim.b.coc_force_attach = 1
  vim.api.nvim_set_hl(0, "CocMenuSel", { link = "PmenuSel" }) -- fix highlight
  vim.api.nvim_set_hl(0, "CocInlayHint", { link = "CursorColumn" })
  local ok, override_node = pcall(binaries.system_default_node)
  if ok and override_node then vim.g.coc_node_path = override_node end
end

M.config = function()
  init()

  vim.api.nvim_create_autocmd("User", {
    desc = "Setup coc per buffer on coc events",
    group = vim.api.nvim_create_augroup("setup_coc_on_init", { clear = true }),
    pattern = { "CocNvimInit" },
    callback = function(args) utils.setup_coc_per_buffer(args.buf, event_handlers.attach) end,
  })

  vim.api.nvim_create_autocmd({ "BufEnter", "TabEnter", "BufNew", "BufWritePost" }, {
    desc = "Setup coc per buffer on buffer enter",
    group = vim.api.nvim_create_augroup("setup_coc_per_buffer", { clear = true }),
    callback = function(args)
      if vim.g.coc_service_initialized == 1 then -- don't interfere with CocNvimInit
        if args.match:match("^diffview") then return end -- exclude unnecessary matches
        utils.setup_coc_per_buffer(args.buf, event_handlers.attach)
      end
    end,
  })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    desc = "Teardown coc when exit vim",
    group = vim.api.nvim_create_augroup("teardown_coc", { clear = true }),
    callback = function()
      if vim.g.coc_process_pid then utils.cmd({ "kill", "-9", vim.g.coc_process_pid }) end
    end,
  })
end

return M
