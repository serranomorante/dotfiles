--[[
  # I'm using coc only for javascript/typescript
  # What I'm not doing with coc.nvim?
  #  - Formatting, for that I still use conform
  #  - Linting, for that I still use nvim-lint
  #  - Folding, lucky me, folding works with coc.nvim
]]

local M = {}

local utils = require("serranomorante.utils")
local tools = require("serranomorante.tools")

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
local function on_coc_enabled(buf)
  local fzf_lua = require("fzf-lua")

  ---@param msg? string
  ---@param opts vim.keymap.set.Opts
  local notify_keymap_error = function(msg, opts)
    local message = msg or "Coc keymap failed"
    local printable = message .. " | " .. opts.desc
    vim.notify(printable, vim.log.levels.ERROR)
    vim.print(printable)
  end

  ---@type vim.keymap.set.Opts
  local opts = { noremap = true, silent = true, buffer = buf }

  local response
  vim.fn.CocActionAsync("ensureDocument", function(err, result) response = { err = err, result = result } end)
  local wait_result = vim.wait(4000, function() return response ~= nil and response ~= vim.NIL end, 10)

  if wait_result then
    if response.err ~= nil and response.err ~= vim.NIL then
      vim.notify("Couldn't set coc mappings: " .. response.err, vim.log.levels.WARN)
    else
      vim.fn.CocActionAsync("hasProvider", "reference", function(_, result)
        opts.desc = "COC: Show references"
        if result == true then
          vim.keymap.set("n", "grr", "<Plug>(coc-references)", opts)
        elseif result == vim.NIL then
          notify_keymap_error(nil, opts)
        end
      end)

      vim.fn.CocActionAsync("hasProvider", "definition", function(_, result)
        opts.desc = "COC: Show definitions"
        if result == true then
          vim.keymap.set("n", "gd", "<Plug>(coc-definition)", opts)
        elseif result == vim.NIL then
          notify_keymap_error(nil, opts)
        else
          notify_keymap_error("Unknown error", opts)
        end
      end)

      vim.fn.CocActionAsync("hasProvider", "implementation", function(_, result)
        opts.desc = "COC: Show implementations"
        if result == true then
          vim.keymap.set("n", "gI", "<Plug>(coc-implementation)", opts)
        elseif result == vim.NIL then
          notify_keymap_error(nil, opts)
        end
      end)

      vim.fn.CocActionAsync("hasProvider", "typeDefinition", function(_, result)
        opts.desc = "COC: Show type definitions"
        if result == true then
          vim.keymap.set("n", "gy", "<Plug>(coc-type-definition)", opts)
        elseif result == vim.NIL then
          notify_keymap_error(nil, opts)
        end
      end)

      vim.fn.CocActionAsync("hasProvider", "codeAction", function(_, result)
        opts.desc = "COC: See available code actions"
        if result == true then
          vim.keymap.set("n", "gra", "<Plug>(coc-codeaction-cursor)", opts)
          vim.keymap.set("x", "gra", "<Plug>(coc-codeaction-selected)", opts)
        elseif result == vim.NIL then
          notify_keymap_error(nil, opts)
        end
      end)

      vim.fn.CocActionAsync("hasProvider", "documentSymbol", function(_, result)
        opts.desc = "COC: Document symbols"
        if result == true then
          vim.keymap.set("n", "<leader>ls", function()
            if utils.is_available("aerial.nvim") then require("aerial").toggle() end
          end, opts)
        elseif result == vim.NIL then
          notify_keymap_error(nil, opts)
        end
      end)

      vim.fn.CocActionAsync("hasProvider", "declaration", function(_, result)
        opts.desc = "COC: Go to declaration"
        if result == true then
          vim.keymap.set("n", "gD", "<Plug>(coc-declaration)", opts)
        elseif result == vim.NIL then
          notify_keymap_error(nil, opts)
        end
      end)

      vim.fn.CocActionAsync("hasProvider", "rename", function(_, result)
        opts.desc = "COC: Smart rename"
        if result == true then
          vim.keymap.set("n", "grn", "<Plug>(coc-rename)", opts)
        elseif result == vim.NIL then
          notify_keymap_error(nil, opts)
        end
      end)

      vim.fn.CocActionAsync("hasProvider", "hover", function(_, result)
        opts.desc = "COC: Hover"
        if result == true or vim.NIL then -- json and yaml files result is false, maybe a bug?
          vim.keymap.set("n", "K", show_docs, opts)
        elseif result == vim.NIL then
          notify_keymap_error(nil, opts)
        end
      end)

      vim.fn.CocActionAsync("hasProvider", "signature", function(_, result)
        opts.desc = "COC: Signature help"
        if result == true then
          vim.keymap.set("i", "<C-S>", function() vim.fn.CocActionAsync("showSignatureHelp") end, opts)
        elseif result == vim.NIL then
          notify_keymap_error(nil, opts)
        end
      end)

      vim.fn.CocActionAsync("hasProvider", "inlayHint", function(_, result)
        opts.desc = "COC: Toggle inlay hints"
        if result == true then
          vim.keymap.set("n", "<leader>uH", "<cmd>CocCommand document.toggleInlayHint<CR>", opts)
        elseif result == vim.NIL then
          notify_keymap_error(nil, opts)
        end
      end)

      local coc_completion_opts = vim.tbl_extend("force", opts, { expr = true, desc = "COC: Completion" })
      vim.keymap.set("i", "<C-x><C-o>", function()
        if vim.b[buf].coc_enabled == 1 then return vim.api.nvim_eval("coc#refresh()") end
        return "<C-x><C-o>"
      end, coc_completion_opts)

      opts.desc = "COC: Show document diagnostics"
      vim.keymap.set("n", "<leader>ld", function() fzf_lua.diagnostics_document() end, opts)

      opts.desc = "COC: Show line diagnostics"
      vim.keymap.set("n", "gl", vim.diagnostic.open_float, opts) -- ALE is required for this to work with coc

      opts.desc = "COC: Reset diagnostics"
      vim.keymap.set("n", "<leader>rS", vim.diagnostic.reset, opts)

      opts.desc = "COC: Restart coc service"
      vim.keymap.set("n", "<leader>li", "<cmd>CocRestart<CR>", opts)

      opts.desc = "COC: Show info"
      vim.keymap.set("n", "<leader>li", "<cmd>CocInfo<CR>", opts)

      -- opts.desc = "COC: Toggle codeLens"
      -- vim.keymap.set("n", "<leader>uL", "<cmd>CocCommand document.toggleInlayHint<CR>", opts)
    end
  else
    vim.notify("ensureDocument didn't work", vim.log.levels.WARN)
  end
end

local init = function()
  ---This env variable comes from my personal .bashrc file
  local system_node_version = vim.env.SYSTEM_DEFAULT_NODE_VERSION or "latest"
  ---Bypass volta's context detection to prevent running the debugger with unsupported node versions
  local node_path = utils.cmd({ "volta", "run", "--node", system_node_version, "which", "node" }):gsub("\n", "")
  if node_path then vim.g.node_system_executable = node_path end

  vim.g.coc_start_at_startup = 0
  vim.g.coc_user_config = vim.fn.stdpath("config") .. "/lua/serranomorante/plugins/coc"
  vim.g.coc_node_path = node_path
  vim.g.coc_quickfix_open_command = "botright copen"
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
end

M.config = function()
  init()

  vim.api.nvim_create_autocmd("User", {
    desc = "Setup coc per buffer on coc events",
    group = vim.api.nvim_create_augroup("setup_coc_on_init", { clear = true }),
    pattern = { "CocNvimInit" },
    callback = function(args) utils.setup_coc_per_buffer(args.buf, on_coc_enabled) end,
  })

  vim.api.nvim_create_autocmd({ "BufEnter", "TabEnter", "BufNew", "BufWritePost" }, {
    desc = "Setup coc per buffer on buffer enter",
    group = vim.api.nvim_create_augroup("setup_coc_per_buffer", { clear = true }),
    callback = function(args)
      if vim.g.coc_service_initialized == 1 then -- don't interfere with CocNvimInit
        if args.match:match("^diffview") then return end -- exclude unnecessary matches
        utils.setup_coc_per_buffer(args.buf, on_coc_enabled)
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
