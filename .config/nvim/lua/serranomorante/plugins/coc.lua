--[[
  # I'm using coc only for javascript/typescript
  # What I'm not doing with coc.nvim?
  #  - Formatting, for that I still use conform
  #  - Linting, for that I still use conform
  #  - Folding, lucky me, folding works with coc.nvim
]]

local utils = require("serranomorante.utils")
local tools = require("serranomorante.tools")

---Use K to show documentation in preview window
---https://github.com/neoclide/coc.nvim?tab=readme-ov-file#example-lua-configuration
function _G.show_docs()
  ---K do nothing if already on floating window
  if vim.api.nvim_win_get_config(0).relative ~= "" then return end
  ---K focus floating window if present
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(win).relative ~= "" then return utils.feedkeys("<C-w><C-w>", "n") end
  end
  local cw = vim.fn.expand("<cword>")
  if vim.fn.index({ "vim", "help" }, vim.bo.filetype) >= 0 then
    vim.api.nvim_command("h " .. cw)
  elseif vim.api.nvim_eval("coc#rpc#ready()") then
    vim.fn.CocActionAsync("doHover")
  else
    vim.api.nvim_command("!" .. vim.o.keywordprg .. " " .. cw)
  end
end

---Called when coc.nvim successfully attaches to a document (buffer)
local function on_attach(buf)
  ---Make sure coc is ready
  if vim.g.coc_service_initialized ~= 1 then return end

  local opts = { noremap = true, silent = true, buffer = buf }

  if vim.fn.CocAction("hasProvider", "reference") then
    opts.desc = "COC: Show references"
    vim.keymap.set("n", "gr", "<Plug>(coc-references)", opts)
  end

  if vim.fn.CocAction("hasProvider", "definition") then
    opts.desc = "COC: Show definitions"
    vim.keymap.set("n", "gd", "<Plug>(coc-definition)", opts)
  end

  if vim.fn.CocAction("hasProvider", "implementation") then
    opts.desc = "COC: Show implementations"
    vim.keymap.set("n", "gI", "<Plug>(coc-implementation)", opts)
  end

  if vim.fn.CocAction("hasProvider", "typeDefinition") then
    opts.desc = "COC: Show type definitions"
    vim.keymap.set("n", "gy", "<Plug>(coc-type-definition)", opts)
  end

  if vim.fn.CocAction("hasProvider", "codeAction") then
    opts.desc = "COC: See available code actions"
    vim.keymap.set("n", "<leader>la", "<Plug>(coc-codeaction-cursor)", opts)
    vim.keymap.set("x", "<leader>la", "<Plug>(coc-codeaction-selected)", opts)
  end

  if vim.fn.CocAction("hasProvider", "declaration") then
    opts.desc = "COC: Go to declaration"
    vim.keymap.set("n", "gD", "<Plug>(coc-declaration)", opts)
  end

  if vim.fn.CocAction("hasProvider", "rename") then
    opts.desc = "COC: Smart rename"
    vim.keymap.set("n", "<leader>lr", "<Plug>(coc-rename)", opts)
  end

  if vim.fn.CocAction("hasProvider", "hover") then
    opts.desc = "COC: Hover"
    vim.keymap.set("n", "K", "<cmd>lua _G.show_docs()<CR>", opts)
  end

  if vim.fn.CocAction("hasProvider", "signature") then
    opts.desc = "COC: Signature help"
    vim.keymap.set("n", "<leader>lh", function() vim.fn.CocActionAsync("showSignatureHelp") end, opts)
  end

  opts.desc = "COC: Show line diagnostics"
  vim.keymap.set("n", "gl", "<Plug>(coc-diagnostic-info)", opts)

  opts.desc = "COC: Go to previous diagnostic"
  vim.keymap.set("n", "[d", "<Plug>(coc-diagnostic-prev)", opts)

  opts.desc = "COC: Go to next diagnostic"
  vim.keymap.set("n", "]d", "<Plug>(coc-diagnostic-next)", opts)

  opts.desc = "COC: Restart coc service"
  vim.keymap.set("n", "<leader>li", "<cmd>CocRestart<CR>", opts)

  opts.desc = "COC: Show info"
  vim.keymap.set("n", "<leader>li", "<cmd>CocInfo<CR>", opts)
end

return {
  "neoclide/coc.nvim",
  branch = "release",
  event = "User CustomFile",
  init = function()
    local user_config = {
      ["diagnostic.enableHighlightLineNumber"] = false,
      ["diagnostic.enableSign"] = false,
      ["diagnostic.virtualText"] = true,
      ["diagnostic.virtualTextCurrentLineOnly"] = false,
      ["diagnostic.messageTarget"] = "float",
      ["coc.preferences.useQuickfixForLocations"] = true,
      ["hover.floatConfig"] = { border = true, focusable = true },
      ["diagnostic.floatConfig"] = { border = true, focusable = true },
      ["diagnostic.enableMessage"] = "jump",
    }

    vim.g.coc_user_config = user_config
    vim.g.coc_start_at_startup = 0
    vim.g.coc_global_extensions = utils.merge_tools("coc", tools.by_filetype.javascript)
  end,
  config = function()
    local current_buffer = vim.api.nvim_get_current_buf()
    utils.setup_coc_per_buffer(current_buffer)

    vim.api.nvim_create_autocmd("User", {
      desc = "Attach coc to buffer",
      group = vim.api.nvim_create_augroup("attach_coc_to_buffer", { clear = true }),
      pattern = { "CocNvimInit", "CustomFile" },
      callback = function(args) utils.setup_coc_per_buffer(args.buf, on_attach) end,
    })

    vim.api.nvim_set_hl(0, "CocMenuSel", { link = "PmenuSel" }) -- fix highlight
  end,
}
