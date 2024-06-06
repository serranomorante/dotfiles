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
    if vim.api.nvim_win_get_config(win).relative ~= "" then
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
local function on_coc_enabled(buf)
  local opts = { noremap = true, silent = true, buffer = buf }

  local response
  vim.fn.CocActionAsync("ensureDocument", function(err, result) response = { err = err, result = result } end)
  local wait_result = vim.wait(4000, function() return response ~= nil and response ~= vim.NIL end, 10)

  if wait_result then
    if response.err ~= nil and response.err ~= vim.NIL then
      vim.notify("Couldn't set coc mappings: " .. response.err, vim.log.levels.WARN)
    else
      vim.fn.CocActionAsync("hasProvider", "reference", function(_, result)
        if result == true then
          opts.desc = "COC: Show references"
          vim.keymap.set("n", "gr", "<Plug>(coc-references)", opts)
        end
      end)

      vim.fn.CocActionAsync("hasProvider", "definition", function(_, result)
        if result == true then
          opts.desc = "COC: Show definitions"
          vim.keymap.set("n", "gd", "<Plug>(coc-definition)", opts)
        end
      end)

      vim.fn.CocActionAsync("hasProvider", "implementation", function(_, result)
        if result == true then
          opts.desc = "COC: Show implementations"
          vim.keymap.set("n", "gI", "<Plug>(coc-implementation)", opts)
        end
      end)

      vim.fn.CocActionAsync("hasProvider", "typeDefinition", function(_, result)
        if result == true then
          opts.desc = "COC: Show type definitions"
          vim.keymap.set("n", "gy", "<Plug>(coc-type-definition)", opts)
        end
      end)

      vim.fn.CocActionAsync("hasProvider", "codeAction", function(_, result)
        if result == true then
          opts.desc = "COC: See available code actions"
          vim.keymap.set("n", "<leader>la", "<Plug>(coc-codeaction-cursor)", opts)
          vim.keymap.set("x", "<leader>la", "<Plug>(coc-codeaction-selected)", opts)
        end
      end)

      vim.fn.CocActionAsync("hasProvider", "documentSymbol", function(_, result)
        if result == true then
          opts.desc = "COC: Document symbols"
          vim.keymap.set("n", "<leader>ls", function()
            if utils.is_available("aerial.nvim") then require("aerial").toggle() end
          end, opts)
        end
      end)

      vim.fn.CocActionAsync("hasProvider", "declaration", function(_, result)
        if result == true then
          opts.desc = "COC: Go to declaration"
          vim.keymap.set("n", "gD", "<Plug>(coc-declaration)", opts)
        end
      end)

      vim.fn.CocActionAsync("hasProvider", "rename", function(_, result)
        if result == true then
          opts.desc = "COC: Smart rename"
          vim.keymap.set("n", "<leader>lr", "<Plug>(coc-rename)", opts)
        end
      end)

      vim.fn.CocActionAsync("hasProvider", "hover", function(_, result)
        if result == true then
          opts.desc = "COC: Hover"
          vim.keymap.set("n", "K", "<cmd>lua _G.show_docs()<CR>", opts)
        end
      end)

      vim.fn.CocActionAsync("hasProvider", "signature", function(_, result)
        if result == true then
          opts.desc = "COC: Signature help"
          vim.keymap.set("n", "<leader>lh", function() vim.fn.CocActionAsync("showSignatureHelp") end, opts)
        end
      end)

      local coc_completion_opts = vim.tbl_extend("force", opts, { expr = true, desc = "COC: Completion" })
      vim.keymap.set("i", "<C-x><C-o>", function()
        if vim.b[buf].coc_enabled == 1 then return vim.api.nvim_eval("coc#refresh()") end
        return "<C-x><C-o>"
      end, coc_completion_opts)

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
  end
end

return {
  "neoclide/coc.nvim",
  branch = "release",
  event = {
    "User CustomLSPjavascript,CustomLSPjavascriptreact,CustomLSPtypescript,CustomLSPtypescriptreact",
  },
  init = function()
    local user_config = {
      ["suggest.autoTrigger"] = "trigger",
      ["suggest.noselect"] = true,
      ["diagnostic.enableHighlightLineNumber"] = false,
      ["diagnostic.enableSign"] = false,
      ["diagnostic.virtualText"] = true,
      ["diagnostic.virtualTextCurrentLineOnly"] = false,
      ["diagnostic.messageTarget"] = "float",
      ["coc.preferences.useQuickfixForLocations"] = true,
      ["hover.floatConfig"] = { border = true, focusable = true },
      ["diagnostic.floatConfig"] = { border = true, focusable = true },
      ["diagnostic.enableMessage"] = "jump",
      ["coc.preferences.promptInput"] = false,
    }

    vim.g.coc_user_config = user_config
    vim.g.coc_quickfix_open_command = "botright copen"
    vim.g.coc_global_extensions = utils.merge_tools("coc", tools.by_filetype.javascript)
    vim.api.nvim_set_hl(0, "CocMenuSel", { link = "PmenuSel" }) -- fix highlight
  end,
  config = function()
    local setup_coc_augroup = vim.api.nvim_create_augroup("setup_coc", { clear = true })
    vim.api.nvim_create_autocmd("User", {
      desc = "Setup coc per buffer on coc events",
      group = vim.api.nvim_create_augroup("setup_coc_per_buffer", { clear = true }),
      pattern = { "CocNvimInit" },
      callback = function(args) utils.setup_coc_per_buffer(args.buf, on_coc_enabled) end,
    })

    vim.api.nvim_create_autocmd({ "BufEnter", "TabEnter" }, {
      desc = "Setup coc per buffer on buffer enter",
      group = setup_coc_augroup,
      callback = function(args)
        if args.match:match("^diffview") then return end -- exclude unnecessary matches
        utils.setup_coc_per_buffer(args.buf, on_coc_enabled)
      end,
    })

    vim.api.nvim_create_autocmd("VimLeavePre", {
      desc = "Teardown coc when exit vim",
      group = vim.api.nvim_create_augroup("teardown_coc", { clear = true }),
      callback = function()
        if vim.g.coc_process_pid then utils.cmd({ "kill", "-9", vim.g.coc_process_pid }) end
      end,
    })
  end,
}
