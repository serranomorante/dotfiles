local utils = require("serranomorante.utils")
local keymapper = require("serranomorante.plugins.coc.keymapper")
local coc_utils = require("serranomorante.plugins.coc.utils")

local M = {}

---Use K to show documentation in preview window
---https://github.com/neoclide/coc.nvim?tab=readme-ov-file#example-lua-configuration
local function show_docs()
  ---K do nothing if already on floating window
  if vim.api.nvim_win_get_config(0).relative ~= "" then return end
  ---K focus floating window if present
  if vim.api.nvim_eval("coc#float#has_float()") ~= 0 then
    utils.feedkeys("<C-w><C-w>", "n")
    vim.schedule(function()
      if vim.fn.maparg("q", "n") == "" then
        vim.keymap.set("n", "q", "<cmd>close<cr>", {
          desc = "Close window",
          buffer = vim.api.nvim_get_current_buf(),
          silent = true,
          nowait = true,
        })
      end
    end)
    return
  end
  local cw = vim.fn.expand("<cword>")
  if vim.fn.index({ "vim", "help" }, vim.bo.filetype) >= 0 then
    vim.api.nvim_command("h " .. cw)
  elseif vim.api.nvim_eval("coc#rpc#ready()") ~= 0 then
    vim.fn.CocActionAsync("doHover")
  else
    vim.api.nvim_command("!" .. vim.o.keywordprg .. " " .. cw)
  end
end

---Called when coc.nvim successfully attaches to a document (buffer)
---@param buf integer
function M.attach(buf)
  local fzf_lua = require("fzf-lua")

  ---@param msg string
  local notify_keymap_error = function(msg)
    local prefix = "COC: couldn't set keymap"
    vim.notify(prefix .. " " .. msg, vim.log.levels.WARN)
  end

  local opts_with_desc = keymapper.opts_for(buf)

  coc_utils.coc_ensure_document():thenCall(function()
    coc_utils.coc_ext_supports_method("reference"):thenCall(
      function() vim.keymap.set("n", "grr", "<Plug>(coc-references)", opts_with_desc("Show references")) end,
      function() notify_keymap_error("Show references") end
    )

    coc_utils.coc_ext_supports_method("definition"):thenCall(
      function() vim.keymap.set("n", "gd", "<Plug>(coc-definition)", opts_with_desc("Show definitions")) end,
      function() notify_keymap_error("Show definitions") end
    )

    coc_utils.coc_ext_supports_method("implementation"):thenCall(
      function() vim.keymap.set("n", "gI", "<Plug>(coc-implementation)", opts_with_desc("Show implementations")) end,
      function() notify_keymap_error("Show implementations") end
    )

    coc_utils.coc_ext_supports_method("typeDefinition"):thenCall(
      function() vim.keymap.set("n", "gy", "<Plug>(coc-type-definition)", opts_with_desc("Show type definitions")) end,
      function() notify_keymap_error("Show type definitions") end
    )

    coc_utils.coc_ext_supports_method("codeAction"):thenCall(function()
      vim.keymap.set("n", "gra", "<Plug>(coc-codeaction-cursor)", opts_with_desc("See available code actions"))
      vim.keymap.set("x", "gra", "<Plug>(coc-codeaction-selected)", opts_with_desc("See available code actions"))
    end, function() notify_keymap_error("See available code actions") end)

    coc_utils.coc_ext_supports_method("documentSymbol"):thenCall(function()
      vim.keymap.set("n", "<leader>ls", function()
        if utils.is_available("aerial.nvim") then require("aerial").toggle() end
      end, opts_with_desc("Document symbols"))
    end, function() notify_keymap_error("Document symbols") end)

    coc_utils.coc_ext_supports_method("declaration"):thenCall(
      function() vim.keymap.set("n", "gD", "<Plug>(coc-declaration)", opts_with_desc("Go to declaration")) end,
      function() notify_keymap_error("Go to declaration") end
    )

    coc_utils.coc_ext_supports_method("rename"):thenCall(
      function() vim.keymap.set("n", "grn", "<Plug>(coc-rename)", opts_with_desc("Smart rename")) end,
      function() notify_keymap_error("Smart rename") end
    )

    coc_utils.coc_ext_supports_method("hover"):thenCall(
      function() vim.keymap.set("n", "K", show_docs, opts_with_desc("Hover")) end,
      function() notify_keymap_error("Hover") end
    )

    coc_utils.coc_ext_supports_method("signature"):thenCall(function()
      vim.keymap.set(
        "i",
        "<C-S>",
        function() vim.fn.CocActionAsync("showSignatureHelp") end,
        opts_with_desc("Signature help")
      )
    end, function() notify_keymap_error("Signature help") end)

    coc_utils.coc_ext_supports_method("inlayHint"):thenCall(
      function()
        vim.keymap.set(
          "n",
          "<leader>uH",
          "<cmd>CocCommand document.toggleInlayHint<CR>",
          opts_with_desc("Toggle inlay hints")
        )
      end,
      function() notify_keymap_error("Toggle inlay hints") end
    )

    local coc_completion_opts = vim.tbl_extend("force", opts_with_desc("Completion"), { expr = true })
    vim.keymap.set("i", "<C-x><C-o>", function()
      if vim.b[buf].coc_enabled == 1 then return vim.api.nvim_eval("coc#refresh()") end
      return "<C-x><C-o>"
    end, coc_completion_opts)

    vim.keymap.set(
      "n",
      "<leader>ld",
      function() fzf_lua.diagnostics_document() end,
      opts_with_desc("Show document diagnostics")
    )

    vim.keymap.set("n", "gl", vim.diagnostic.open_float, opts_with_desc("Show line diagnostics")) -- ALE is required for this to work with coc

    vim.keymap.set("n", "<leader>rS", vim.diagnostic.reset, opts_with_desc("Reset diagnostics"))

    vim.keymap.set("n", "<leader>li", "<cmd>CocRestart<CR>", opts_with_desc("Restart coc service"))

    vim.keymap.set("n", "<leader>li", "<cmd>CocInfo<CR>", opts_with_desc("Show info"))
  end, function() vim.notify("ensureDocument didn't work", vim.log.levels.WARN) end)
end

return M
