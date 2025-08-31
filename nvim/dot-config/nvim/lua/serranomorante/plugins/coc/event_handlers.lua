local utils = require("serranomorante.utils")
local keymapper = require("serranomorante.plugins.coc.keymapper")
local coc_utils = require("serranomorante.plugins.coc.utils")

local M = {}

---Use K to show documentation in preview window
---https://github.com/neoclide/coc.nvim?tab=readme-ov-file#example-lua-configuration
---@param buf integer
local function show_docs(buf)
  ---K do nothing if already on floating window
  if vim.api.nvim_win_get_config(0).relative ~= "" then return end
  ---K focus floating window if present
  if vim.api.nvim_eval("coc#float#has_float()") ~= 0 then
    vim.cmd('execute "normal \\<Plug>(coc-float-jump)"')
    vim.schedule(function()
      for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
        if map.lhs == "q" then return end
      end
      vim.keymap.set("n", "q", "<cmd>close<CR>", {
        desc = "Close window with q",
        buffer = buf,
        silent = true,
        nowait = true,
      })
    end)
    return
  end
  local cw = vim.fn.expand("<cword>")
  if vim.fn.index({ "vim", "help" }, vim.bo.filetype) >= 0 then
    vim.api.nvim_command("h " .. cw)
  elseif vim.api.nvim_eval("coc#rpc#ready()") ~= 0 then
    coc_utils.action_async("doHover")
  else
    vim.api.nvim_command("!" .. vim.o.keywordprg .. " " .. cw)
  end
end

---Called when coc.nvim successfully attaches to a document (buffer)
---@param buf integer
function M.attach(buf)
  local opts_with_desc = keymapper.opts_for(buf)

  vim.keymap.set("n", "grr", "<Plug>(coc-references)", opts_with_desc("Show references"))

  vim.keymap.set("n", "gd", "<Plug>(coc-definition)", opts_with_desc("Show definitions"))

  vim.keymap.set("n", "gI", "<Plug>(coc-implementation)", opts_with_desc("Show implementations"))

  vim.keymap.set("n", "gy", "<Plug>(coc-type-definition)", opts_with_desc("Show type definitions"))

  vim.keymap.set("n", "gra", "<Plug>(coc-codeaction-cursor)", opts_with_desc("See available code actions"))

  vim.keymap.set("n", "grf", "<Plug>(coc-codeaction-source)", opts_with_desc("See available code actions"))

  vim.keymap.set("x", "gra", "<Plug>(coc-codeaction-selected)", opts_with_desc("See available code actions"))

  vim.keymap.set("n", "<leader>ls", function()
    if utils.is_available("aerial") then
      require("aerial").toggle()
    else
      coc_utils
        .action_async("documentSymbols", buf)
        :catch(function(err) vim.api.nvim_echo({ { err } }, false, { err = true }) end)
    end
  end, opts_with_desc("Document symbols"))

  vim.keymap.set("n", "gD", "<Plug>(coc-declaration)", opts_with_desc("Go to declaration"))

  vim.keymap.set("n", "grn", "<Plug>(coc-rename)", opts_with_desc("Smart rename"))

  vim.keymap.set("n", "K", function() show_docs(buf) end, opts_with_desc("Hover"))

  vim.keymap.set(
    "i",
    "<C-S>",
    function() coc_utils.action_async("showSignatureHelp") end,
    opts_with_desc("Signature help")
  )

  vim.keymap.set("n", "<leader>uH", function()
    vim.g.coc_inlay_hints = not vim.g.coc_inlay_hints
    vim.api.nvim_echo({
      { "Inlay hints " },
      { utils.bool2str(vim.g.coc_inlay_hints), vim.g.coc_inlay_hints and "DiagnosticOk" or "Comment" },
    }, false, {})
    return "<cmd>CocCommand document.toggleInlayHint<CR>"
  end, vim.tbl_extend("force", opts_with_desc("Toggle inlay hints"), { expr = true }))

  vim.keymap.set("i", "<C-x><C-o>", function()
    if coc_utils.is_coc_attached(buf) then return vim.api.nvim_eval("coc#refresh()") end
    return "<C-x><C-o>"
  end, vim.tbl_extend("force", opts_with_desc("Completion"), { expr = true }))

  vim.keymap.set("n", "gl", vim.diagnostic.open_float, opts_with_desc("Show line diagnostics")) -- ALE is required for this to work with coc

  vim.keymap.set("n", "<leader>rS", vim.diagnostic.reset, opts_with_desc("Reset diagnostics"))

  vim.keymap.set("n", "<leader>li", "<cmd>CocRestart<CR>", opts_with_desc("Restart coc service"))

  vim.keymap.set("n", "<leader>li", "<cmd>CocInfo<CR>", opts_with_desc("Show info"))
end

return M
