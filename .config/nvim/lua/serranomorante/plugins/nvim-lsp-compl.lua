local utils = require("serranomorante.utils")

return {
  "mfussenegger/nvim-lsp-compl",
  init = function() vim.bo.omnifunc = "" end,
  config = function()
    local lsp_compl = require("lsp_compl")

    vim.keymap.set(
      "i",
      "<C-y>",
      function() return lsp_compl.accept_pum() and "<C-y>" or "<CR>" end,
      { expr = true, desc = "Compl: accept completion" }
    )

    vim.keymap.set("i", "<ESC>", function()
      local info = vim.fn.complete_info({ "pum_visible", "selected" })
      if info.pum_visible == 1 then vim.schedule(function() utils.feedkeys("<ESC>", "n") end) end
      if info.pum_visible == 1 and info.selected ~= -1 then
        return lsp_compl.accept_pum() and "<C-y>" or "<C-e>"
      elseif info.pum_visible == 1 and info.selected == -1 then
        return "<C-e>"
      end
      return "<ESC>"
    end, { expr = true, desc = "Compl: Escape and accept or cancel" })

    vim.keymap.set(
      "i",
      "<C-x><C-o>",
      function() lsp_compl.trigger_completion() end,
      { desc = "Compl: Trigger completion" }
    )

    local function try_jump(direction, key)
      if vim.snippet.active({ direction = direction }) then
        return string.format("<cmd>lua vim.snippet.jump(%d)<cr>", direction)
      end
      return key
    end
    vim.keymap.set(
      { "i", "s" },
      "<Tab>",
      function() return try_jump(1, "<Tab>") end,
      { expr = true, desc = "Compl: go to next jump" }
    )
    vim.keymap.set(
      { "i", "s" },
      "<S-Tab>",
      function() return try_jump(-1, "<S-Tab>") end,
      { expr = true, desc = "Compl: go to prev jump" }
    )
  end,
}
