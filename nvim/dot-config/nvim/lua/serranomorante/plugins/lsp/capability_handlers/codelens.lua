local utils = require("serranomorante.utils")
local codelens_is_enabled = true

---@type CapabilityHandler
return {
  attach = function(data)
    local keymapper = require("serranomorante.plugins.lsp.keymapper")

    local augroup = data.augroup
    local bufnr = data.bufnr
    local client = data.client

    vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, {
      desc = "Refresh codelens",
      group = augroup,
      buffer = bufnr,
      callback = function(event)
        if not codelens_is_enabled then return end
        vim.lsp.codelens.enable(true, { bufnr = event.buf })
      end,
    })

    vim.api.nvim_create_autocmd("User", {
      desc = "Refresh codelens on undo redo events",
      buffer = bufnr,
      group = augroup,
      callback = function(event)
        if not vim.list_contains({ "CustomUndo", "CustomRedo" }, event.match) then return end
        if not codelens_is_enabled then return end
        vim.lsp.codelens.enable(true, { bufnr = event.buf })
      end,
    })

    local opts_with_desc = keymapper.opts_for(bufnr)

    vim.keymap.set("n", "<leader>uL", function()
      codelens_is_enabled = not codelens_is_enabled
      vim.api.nvim_echo({
        { "CodeLens " },
        { utils.bool2str(codelens_is_enabled), codelens_is_enabled and "DiagnosticOk" or "Comment" },
      }, false, {})
      return codelens_is_enabled and vim.lsp.codelens.enable(true, { bufnr = bufnr })
        or vim.lsp.codelens.enable(false, { client_id = client.id, bufnr = bufnr })
    end, opts_with_desc("Toggle codelens"))

    vim.keymap.set("n", "<leader>ll", function()
      if not codelens_is_enabled then return end
      vim.lsp.codelens.enable(true, { bufnr = bufnr })
    end, opts_with_desc("Refresh codelens"))

    ---Refresh manually right now for a start
    if codelens_is_enabled then vim.lsp.codelens.enable(true, { bufnr = bufnr }) end
  end,

  detach = function(client_id, bufnr)
    vim.lsp.codelens.enable(false, { client_id = client_id, bufnr = bufnr })
    vim.api.nvim_buf_del_keymap(bufnr, "n", "<leader>uL")
    vim.api.nvim_buf_del_keymap(bufnr, "n", "<leader>ll")
  end,
}
