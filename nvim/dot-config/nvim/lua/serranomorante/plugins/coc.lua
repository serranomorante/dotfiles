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
        if result == true or vim.NIL then -- json and yaml files result is false, maybe a bug?
          opts.desc = "COC: Hover"
          vim.keymap.set("n", "K", show_docs, opts)
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

      opts.desc = "COC: Show document diagnostics"
      vim.keymap.set("n", "<leader>ld", "<cmd>CocDiagnostics<CR>", opts)

      opts.desc = "COC: Show line diagnostics"
      vim.keymap.set("n", "gl", vim.diagnostic.open_float, opts) -- ALE is required for this to work with coc

      opts.desc = "COC: Reset diagnostics"
      vim.keymap.set("n", "<leader>rS", vim.diagnostic.reset, opts)

      opts.desc = "COC: Restart coc service"
      vim.keymap.set("n", "<leader>li", "<cmd>CocRestart<CR>", opts)

      opts.desc = "COC: Show info"
      vim.keymap.set("n", "<leader>li", "<cmd>CocInfo<CR>", opts)
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

  local user_config = {
    ["suggest.autoTrigger"] = "trigger",
    ["suggest.noselect"] = true,
    ["codeLens.enable"] = true,
    ["codeLens.position"] = "eol",
    ["diagnostic.enableHighlightLineNumber"] = false,
    ["diagnostic.enableSign"] = false,
    ["diagnostic.virtualText"] = true,
    ["diagnostic.displayByAle"] = true,
    ["diagnostic.virtualTextCurrentLineOnly"] = false,
    ["diagnostic.messageTarget"] = "float",
    ["coc.preferences.useQuickfixForLocations"] = true,
    ["hover.floatConfig"] = { border = true, focusable = true },
    ["diagnostic.floatConfig"] = { border = true, focusable = true },
    ["diagnostic.enableMessage"] = "jump",
    ["coc.preferences.promptInput"] = false,
    ["typescript.implementationsCodeLens.enabled"] = true,
    ["typescript.suggest.completeFunctionCalls"] = false,
    ["typescript.referencesCodeLens.enabled"] = true,
    ["javascript.implementationsCodeLens.enabled"] = true,
    ["javascript.suggest.completeFunctionCalls"] = false,
    ["javascript.referencesCodeLens.enabled"] = true,
    ---Download the compiled jar from this url and add it to the following dir
    ---https://plantuml.com/download
    ["markdown-preview-enhanced.plantumlJarPath"] = vim.env.HOME .. "/plantuml/plantuml.jar",
  }

  vim.g.coc_node_path = node_path
  vim.g.coc_user_config = user_config
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
end

M.config = function()
  init()

  local setup_coc_augroup = vim.api.nvim_create_augroup("setup_coc_on_init", { clear = true })

  local function wrap_with_plugin_start(handler)
    require("serranomorante.plugins.nvim-ufo").config()
    return handler
  end

  vim.api.nvim_create_autocmd("User", {
    desc = "Setup coc per buffer on coc events",
    group = setup_coc_augroup,
    pattern = { "CocNvimInit" },
    callback = function(args) utils.setup_coc_per_buffer(args.buf, wrap_with_plugin_start(on_coc_enabled)) end,
  })

  vim.api.nvim_create_autocmd({ "BufEnter", "TabEnter", "BufNew", "BufWritePost" }, {
    desc = "Setup coc per buffer on buffer enter",
    group = vim.api.nvim_create_augroup("setup_coc_per_buffer", { clear = true }),
    callback = function(args)
      if vim.g.coc_service_initialized == 1 then -- don't interfere with CocNvimInit
        if args.match:match("^diffview") then return end -- exclude unnecessary matches
        utils.setup_coc_per_buffer(args.buf, wrap_with_plugin_start(on_coc_enabled))
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
