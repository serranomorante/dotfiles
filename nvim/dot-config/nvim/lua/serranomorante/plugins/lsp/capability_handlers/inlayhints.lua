local utils = require("serranomorante.utils")
local inlayhints_is_enabled = false

---@type CapabilityHandler
return {
  attach = function(data)
    local keymapper = require("serranomorante.plugins.lsp.keymapper")
    local bufnr = data.bufnr
    local opts_with_desc = keymapper.opts_for(bufnr)

    vim.keymap.set("n", "<leader>uH", function()
      inlayhints_is_enabled = not inlayhints_is_enabled
      vim.notify(string.format("Inlay hints %s", utils.bool2str(inlayhints_is_enabled)), vim.log.levels.INFO)

      vim.lsp.inlay_hint.enable(inlayhints_is_enabled)
    end, opts_with_desc("Toggle inlay hints"))
  end,

  detach = function(_, bufnr)
    vim.lsp.inlay_hint.enable(false)
    vim.api.nvim_buf_del_keymap(bufnr, "n", "<leader>uH")
  end,
}
