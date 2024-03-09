local utils = require("serranomorante.utils")
local constants = require("serranomorante.constants")
local tools = require("serranomorante.tools")

local on_init = nil
local on_attach = nil
local capabilities = nil

return {
  {
    "pmizio/typescript-tools.nvim",
    dependencies = "neovim/nvim-lspconfig",
    event = "User CustomLSPLoadJavascript,CustomLSPLoadTypescript,CustomLSPLoadTypescriptreact,CustomLSPLoadJavascriptreact",
    opts = function()
      return {
        on_init = on_init,
        capabilities = capabilities,
        on_attach = on_attach,
        single_file_support = false,
        settings = {
          code_lens = "all",
          publish_diagnostic_on = "insert_leave",
          complete_function_calls = false,
          expose_as_code_action = { "fix_all", "add_missing_imports", "remove_unused" },
          separate_diagnostic_server = false,
          tsserver_file_preferences = {
            includeInlayParameterNameHints = "all",
            includeInlayParameterNameHintsWhenArgumentMatchesName = true,
            includeInlayFunctionParameterTypeHints = true,
            includeInlayVariableTypeHints = true,
            includeInlayVariableTypeHintsWhenTypeMatchesName = true,
            includeInlayPropertyDeclarationTypeHints = true,
            includeInlayFunctionLikeReturnTypeHints = true,
            includeInlayEnumMemberValueHints = true,
          },
        },
      }
    end,
  },
  {
    "p00f/clangd_extensions.nvim",
    dependencies = "neovim/nvim-lspconfig",
    event = "User CustomLSPLoadC",
    config = function()
      require("lspconfig")["clangd"].setup({
        on_init = on_init,
        capabilities = vim.tbl_deep_extend("force", capabilities, { offsetEncoding = "utf-16" }),
        on_attach = on_attach,
      })
    end,
  },
  {
    "b0o/SchemaStore.nvim",
    enabled = true,
    dependencies = "neovim/nvim-lspconfig",
    event = "User CustomLSPLoadJson,CustomLSPLoadYaml",
    config = function()
      local schemastore = require("schemastore")
      local settings = {
        json = { schemas = schemastore.json.schemas(), validate = { enable = true } },
        yaml = {
          schemaStore = {
            -- You must disable built-in schemaStore support if you want to use
            -- this plugin and its advanced options like `ignore`.
            enable = false,
            -- Avoid TypeError: Cannot read properties of undefined (reading 'length')
            url = "",
          },
          schemas = schemastore.yaml.schemas(),
        },
      }

      for _, server in ipairs({ "jsonls", "yamlls" }) do
        require("lspconfig")[server].setup({
          on_init = on_init,
          on_attach = on_attach,
          capabilities = capabilities,
          settings = settings[server],
        })
      end
    end,
  },
  {
    "neovim/nvim-lspconfig",
    cmd = { "LspInfo", "LspInstall", "LspStart" },
    event = "User CustomFile",
    dependencies = {
      "hrsh7th/cmp-nvim-lsp",
      "ibhagwan/fzf-lua",
    },
    init = function()
      ---See: https://github.com/VonHeikemen/lsp-zero.nvim/blob/dev-v3/doc/md/guides/under-the-hood.md
      ---See: https://github.com/mfussenegger/nvim-lint/issues/340#issuecomment-1676438571
      vim.diagnostic.config({
        signs = {
          text = {
            [vim.diagnostic.severity.INFO] = "",
            [vim.diagnostic.severity.HINT] = "",
            [vim.diagnostic.severity.WARN] = "",
            [vim.diagnostic.severity.ERROR] = "",
          },
        },
        virtual_text = { source = true },
        float = { border = "single", source = true },
      })

      vim.lsp.handlers["textDocument/hover"] = vim.lsp.with(vim.lsp.handlers.hover, { border = "single" })

      vim.lsp.handlers["textDocument/signatureHelp"] =
        vim.lsp.with(vim.lsp.handlers.signature_help, { border = "single" })

      ---Create autocmd to refresh codelens on BufEnter and InsertLeave
      local codelens_augroup = vim.api.nvim_create_augroup("lsp_codelens_augroup", { clear = true })
      vim.api.nvim_create_autocmd({ "InsertLeave", "BufEnter" }, {
        desc = "Refresh codelens",
        group = codelens_augroup,
        callback = function(args)
          if not utils.has_capability("textDocument/codeLens", { bufnr = args.buf }) then
            utils.del_buffer_autocmd("lsp_codelens_augroup", args.buf)
            return
          end
          if vim.g.codelens_enabled then vim.lsp.codelens.refresh({ bufnr = args.buf }) end
        end,
      })
    end,
    config = function()
      if utils.is_available("neodev.nvim") then require("neodev") end
      local lspconfig = require("lspconfig")
      local cmp_nvim_lsp = require("cmp_nvim_lsp")
      vim.lsp.set_log_level(vim.env.LSP_LOG_LEVEL or "INFO")

      on_init = function(client)
        ---Disable semanticTokensProvider
        ---https://gist.github.com/swarn/fb37d9eefe1bc616c2a7e476c0bc0316
        client.server_capabilities.semanticTokensProvider = nil
      end

      on_attach = function(client, bufnr)
        local opts = { noremap = true, silent = true, buffer = bufnr }

        if utils.is_available("fzf-lua") then
          local builtin = require("fzf-lua")
          if client.supports_method("textDocument/references") then
            opts.desc = "LSP: Show references"
            vim.keymap.set("n", "gr", function() builtin.lsp_references() end, opts)
          end

          if client.supports_method("textDocument/definition") then
            opts.desc = "LSP: Show definitions"
            vim.keymap.set("n", "gd", function() builtin.lsp_definitions({ jump_to_single_result = true }) end, opts)
          end

          if client.supports_method("textDocument/implementation") then
            opts.desc = "LSP: Show implementations"
            vim.keymap.set("n", "gI", function() builtin.lsp_implementations() end, opts)
          end

          if client.supports_method("textDocument/typeDefinition") then
            opts.desc = "LSP: Show type definitions"
            vim.keymap.set("n", "gy", function() builtin.lsp_typedefs() end, opts)
          end

          opts.desc = "LSP: Show document diagnostics"
          vim.keymap.set("n", "<leader>ld", function() builtin.diagnostics_document() end, opts)

          opts.desc = "LSP: Show workspace diagnostics"
          vim.keymap.set("n", "<leader>lD", function() builtin.diagnostics_workspace() end, opts)

          opts.desc = "LSP: Document symbols"
          vim.keymap.set("n", "<leader>ls", function() builtin.lsp_document_symbols() end, opts)

          opts.desc = "LSP: Workspace symbols"
          vim.keymap.set("n", "<leader>lS", function() builtin.lsp_workspace_symbols() end, opts)
        end

        if client.supports_method("textDocument/declaration") then
          opts.desc = "LSP: Go to declaration"
          vim.keymap.set("n", "gD", vim.lsp.buf.declaration, opts)
        end

        if client.supports_method("textDocument/codeAction") then
          opts.desc = "LSP: See available code actions"
          vim.keymap.set({ "n", "v" }, "<leader>la", vim.lsp.buf.code_action, opts)
        end

        if client.supports_method("textDocument/rename") then
          opts.desc = "LSP: Smart rename"
          vim.keymap.set("n", "<leader>lr", vim.lsp.buf.rename, opts)
        end

        if client.supports_method("textDocument/signatureHelp") then
          opts.desc = "LSP: Signature help"
          vim.keymap.set("n", "<leader>lh", vim.lsp.buf.signature_help, opts)
        end

        if client.supports_method("workspace/symbol") then
          opts.desc = "LSP: Search workspace symbols"
          vim.keymap.set("n", "<leader>lG", vim.lsp.buf.workspace_symbol, opts)
        end

        opts.desc = "LSP: Show line diagnostics"
        vim.keymap.set("n", "gl", vim.diagnostic.open_float, opts)

        opts.desc = "LSP: Go to previous diagnostic"
        vim.keymap.set("n", "[d", vim.diagnostic.goto_prev, opts)

        opts.desc = "LSP: Go to next diagnostic"
        vim.keymap.set("n", "]d", vim.diagnostic.goto_next, opts)

        opts.desc = "LSP: Restart current buffer clients"
        vim.keymap.set("n", "<leader>rs", function()
          local clients = vim.lsp.get_clients({ bufnr = bufnr })
          for _, c in pairs(clients) do
            ---Ignore copilot cause it causes issues
            if c.name ~= "copilot" then vim.cmd("LspRestart " .. c.id) end
          end
        end, opts)

        opts.desc = "LSP: Reset diagnostics"
        vim.keymap.set("n", "<leader>rS", vim.diagnostic.reset, opts)

        opts.desc = "LSP: Show info"
        vim.keymap.set("n", "<leader>li", "<cmd>LspInfo<CR>", opts)

        ---Toggle inlay hints with keymap
        if client.supports_method("textDocument/inlayHint") then
          opts.desc = "LSP: Toggle inlay hints"
          vim.keymap.set("n", "<leader>uH", function()
            utils.toggle_buffer_inlay_hints(bufnr)
            vim.notify(
              string.format("Inlay hints %s", utils.bool2str(vim.b[bufnr].inlay_hints_enabled)),
              vim.log.levels.INFO
            )
          end, opts)
        end

        ---Refresh codelens if supported
        if client.supports_method("textDocument/codeLens") then
          if vim.g.codelens_enabled then vim.lsp.codelens.refresh({ bufnr = bufnr }) end

          opts.desc = "LSP: Toggle codelens"
          vim.keymap.set("n", "<leader>uL", function()
            utils.toggle_codelens()
            vim.notify(string.format("CodeLens %s", utils.bool2str(vim.g.codelens_enabled)), vim.log.levels.INFO)
            if vim.g.codelens_enabled then vim.lsp.codelens.refresh({ bufnr = bufnr }) end
          end, opts)

          opts.desc = "LSP: CodeLens refresh (buffer)"
          vim.keymap.set("n", "<leader>ll", function() vim.lsp.codelens.refresh({ bufnr = bufnr }) end, opts)

          opts.desc = "LSP CodeLens run"
          vim.keymap.set("n", "<leader>lL", function() vim.lsp.codelens.run() end, opts)
        end
      end

      capabilities = vim.lsp.protocol.make_client_capabilities()
      capabilities = vim.tbl_deep_extend("force", capabilities, cmp_nvim_lsp.default_capabilities())
      capabilities.textDocument.foldingRange = { dynamicRegistration = false, lineFoldingOnly = true }

      local servers = utils.get_from_tools(tools.by_filetype, "lsp", true)

      ---Custom handlers for lsp servers and plugins
      local custom = {
        ["ruff_lsp"] = function()
          lspconfig["ruff_lsp"].setup({
            on_init = on_init,
            on_attach = function(client, bufnr)
              -- Disable hover in favor of Pyright
              client.server_capabilities.hoverProvider = false
              on_attach(client, bufnr)
            end,
            capabilities = capabilities,
          })
        end,
        ["lua_ls"] = function()
          lspconfig["lua_ls"].setup({
            on_init = on_init,
            capabilities = capabilities,
            on_attach = on_attach,
            settings = {
              Lua = {
                runtime = {
                  version = "LuaJIT",
                },
                diagnostics = {
                  globals = { "vim" },
                },
                completion = {
                  callSnippet = "Replace",
                },
                workspace = {
                  library = {
                    ---https://github.com/neovim/nvim-lspconfig/issues/2948#issuecomment-1871455900
                    vim.env.VIMRUNTIME .. "/lua",
                    "${3rd}/busted/library",
                  },
                },
                codeLens = {
                  enable = true,
                },
                hint = {
                  enable = true,
                },
              },
            },
          })
        end,
        ["tailwindcss"] = function()
          ---https://github.com/paolotiu/tailwind-intellisense-regex-list?tab=readme-ov-file#plain-javascript-object
          local javascript_plain_object = { ":\\s*?[\"'`]([^\"'`]*).*?," }
          ---https://cva.style/docs/getting-started/installation#intellisense
          local cva = { "cva\\(([^)]*)\\)", "[\"'`]([^\"'`]*).*?[\"'`]" }
          local cva_cx = { "cx\\(([^)]*)\\)", "(?:'|\"|`)([^']*)(?:'|\"|`)" }

          lspconfig["tailwindcss"].setup({
            on_init = on_init,
            on_attach = on_attach,
            capabilities = capabilities,
            filetypes = constants.javascript_filetypes,
            settings = {
              tailwindCSS = {
                experimental = { classRegex = { cva, cva_cx, javascript_plain_object } },
              },
            },
          })
        end,
      }

      ---Prevent lsp server setup only when plugin is available
      if utils.is_available("typescript-tools.nvim") then custom["tsserver"] = function() end end
      if utils.is_available("clangd_extensions.nvim") then custom["clangd"] = function() end end
      if utils.is_available("SchemaStore.nvim") then
        custom["yamlls"] = function() end
        custom["jsonls"] = function() end
      end

      ---Setup servers that don't require any extra plugins
      ---Lsp servers that require plugins are lazy loaded
      local function setup_base_servers()
        for _, server in ipairs(servers) do
          if not vim.tbl_contains(vim.tbl_keys(custom), server) then
            lspconfig[server].setup({
              on_init = on_init,
              on_attach = on_attach,
              capabilities = capabilities,
            })
          else
            custom[server]()
          end
        end
      end

      setup_base_servers()
    end,
  },
}
