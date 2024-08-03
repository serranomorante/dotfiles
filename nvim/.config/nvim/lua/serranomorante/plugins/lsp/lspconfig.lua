local utils = require("serranomorante.utils")
local constants = require("serranomorante.constants")
local tools = require("serranomorante.tools")

local on_init = nil
local on_attach = nil
local capabilities = nil

return {
  {
    "p00f/clangd_extensions.nvim",
    dependencies = "neovim/nvim-lspconfig",
    event = "User CustomLSPc,CustomLSPcpp",
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
    event = "User CustomLSPjson,CustomLSPjsonc,CustomLSPyaml",
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

      for _, server in ipairs({ "json", "yaml" }) do
        require("lspconfig")[server .. "ls"].setup({
          on_init = on_init,
          on_attach = on_attach,
          capabilities = capabilities,
          settings = {
            [server] = settings[server],
          },
        })
      end
    end,
  },
  {
    "neovim/nvim-lspconfig",
    cmd = { "LspInfo", "LspInstall", "LspStart" },
    event = "User CustomFile",
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
        jump = { float = { scope = "line" } },
      })

      vim.lsp.handlers["textDocument/hover"] = vim.lsp.with(vim.lsp.handlers.hover, { border = "single" })

      vim.lsp.handlers["textDocument/signatureHelp"] =
        vim.lsp.with(vim.lsp.handlers.signature_help, { border = "single" })

      local codelens_augroup = vim.api.nvim_create_augroup("lsp_codelens_augroup", { clear = true })

      vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, {
        desc = "Refresh codelens",
        group = codelens_augroup,
        callback = utils.refresh_codelens,
      })

      vim.api.nvim_create_autocmd("User", {
        desc = "Refresh codelens on undo redo events",
        pattern = { "CustomUndo", "CustomRedo" },
        group = codelens_augroup,
        callback = utils.refresh_codelens,
      })
    end,
    config = function()
      local lspconfig = require("lspconfig")
      vim.lsp.set_log_level(vim.env.LSP_LOG_LEVEL or "INFO")

      on_init = function(client)
        ---Disable semanticTokensProvider
        ---https://gist.github.com/swarn/fb37d9eefe1bc616c2a7e476c0bc0316
        client.server_capabilities.semanticTokensProvider = nil
        if client.server_capabilities.signatureHelpProvider then
          client.server_capabilities.signatureHelpProvider.triggerCharacters = {}
        end
      end

      on_attach = function(client, bufnr)
        ---Disable LSP on large buffers or when coc is already attached
        local should_detach = vim.b[bufnr].large_buf or vim.b[bufnr].coc_enabled == 1
        if should_detach and vim.lsp.buf_is_attached(bufnr, client.id) then
          vim.schedule(function() vim.lsp.buf_detach_client(bufnr, client.id) end)
          return
        end

        ---Don't continue if coc-extension is already attached to this buffer
        if vim.b[bufnr].coc_enabled == 1 then return end

        ---Enable new native completions
        vim.lsp.completion.enable(true, client.id, bufnr, { autotrigger = true })

        local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
        local opts = { noremap = true, silent = true, buffer = bufnr }

        if utils.is_available("fzf-lua") then
          local builtin = require("fzf-lua")
          if client.supports_method("textDocument/references") then
            opts.desc = "LSP: Show references"
            vim.keymap.set("n", "gr", function()
              local regex_filter = constants.regex_filters[filetype]
              builtin.lsp_references({ regex_filter = regex_filter })
            end, opts)
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

          if client.supports_method("textDocument/codeAction") then
            opts.desc = "LSP: See available code actions"
            vim.keymap.set({ "n", "x" }, "<leader>la", function() builtin.lsp_code_actions() end, opts)
          end

          opts.desc = "LSP: Show document diagnostics"
          vim.keymap.set("n", "<leader>ld", function() builtin.diagnostics_document() end, opts)

          opts.desc = "LSP: Show workspace diagnostics"
          vim.keymap.set("n", "<leader>lD", function() builtin.diagnostics_workspace() end, opts)

          opts.desc = "LSP: Document symbols"
          vim.keymap.set("n", "<leader>ls", function()
            if utils.is_available("aerial.nvim") then
              require("aerial").toggle()
            else
              builtin.lsp_document_symbols()
            end
          end, opts)

          opts.desc = "LSP: Workspace symbols"
          vim.keymap.set("n", "<leader>lS", function() builtin.lsp_workspace_symbols() end, opts)
        end

        if client.supports_method("textDocument/declaration") then
          opts.desc = "LSP: Go to declaration"
          vim.keymap.set("n", "gD", vim.lsp.buf.declaration, opts)
        end

        if client.supports_method("textDocument/rename") then
          opts.desc = "LSP: Smart rename"
          vim.keymap.set("n", "<leader>lr", vim.lsp.buf.rename, opts)
        end

        if client.supports_method("textDocument/signatureHelp") then
          opts.desc = "LSP: Signature help"
          vim.keymap.set("n", "<leader>lh", vim.lsp.buf.signature_help, opts)
        end

        opts.desc = "LSP: Show line diagnostics"
        vim.keymap.set("n", "gl", function() vim.diagnostic.open_float({ scope = "line" }) end, opts)

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

        opts.desc = "LSP: Trigger completions"
        vim.keymap.set("i", "<C-x><C-o>", vim.lsp.completion.trigger, opts)

        ---Toggle inlay hints with keymap
        if client.supports_method("textDocument/inlayHint") then
          opts.desc = "LSP: Toggle inlay hints"
          vim.keymap.set("n", "<leader>uH", function()
            local is_enabled = utils.toggle_inlay_hints()
            vim.notify(string.format("Inlay hints %s", utils.bool2str(is_enabled)), vim.log.levels.INFO)
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
      capabilities.textDocument.foldingRange = { dynamicRegistration = false, lineFoldingOnly = true }

      ---Custom handlers for lsp servers and plugins
      local custom = {
        ["tsserver"] = function()
          lspconfig["tsserver"].setup({
            on_init = on_init,
            on_attach = on_attach,
            capabilities = capabilities,
            init_options = {
              preferences = {
                includeCompletionsForModuleExports = false,
              },
              tsserver = {
                logVerbosity = vim.env.LSP_LOG_LEVEL == "TRACE" and "verbose" or "off",
                trace = vim.env.LSP_LOG_LEVEL == "TRACE" and "verbose" or "off",
              },
            },
            settings = {
              javascript = {
                implementationsCodeLens = { enabled = true },
                referencesCodeLens = {
                  showOnAllFunctions = true,
                  enabled = true,
                },
                inlayHints = {
                  includeInlayEnumMemberValueHints = true,
                  includeInlayFunctionLikeReturnTypeHints = true,
                  includeInlayFunctionParameterTypeHints = true,
                  includeInlayParameterNameHints = "all", -- 'none' | 'literals' | 'all';
                  includeInlayParameterNameHintsWhenArgumentMatchesName = true,
                  includeInlayPropertyDeclarationTypeHints = true,
                  includeInlayVariableTypeHints = true,
                },
              },
              typescript = {
                implementationsCodeLens = { enabled = true },
                referencesCodeLens = {
                  enabled = true,
                  showOnAllFunctions = true,
                },
                inlayHints = {
                  includeInlayEnumMemberValueHints = true,
                  includeInlayFunctionLikeReturnTypeHints = true,
                  includeInlayFunctionParameterTypeHints = true,
                  includeInlayParameterNameHints = "all", -- 'none' | 'literals' | 'all';
                  includeInlayParameterNameHintsWhenArgumentMatchesName = true,
                  includeInlayPropertyDeclarationTypeHints = true,
                  includeInlayVariableTypeHints = true,
                },
              },
            },
          })
        end,
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
                workspace = {
                  library = {
                    ---https://github.com/neovim/nvim-lspconfig/issues/2948#issuecomment-1871455900
                    vim.env.VIMRUNTIME .. "/lua",
                    "${3rd}/busted/library",
                    "${3rd}/luv/library",
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
            filetypes = constants.javascript_aliases,
            settings = {
              tailwindCSS = {
                experimental = { classRegex = { cva, cva_cx, javascript_plain_object } },
              },
            },
          })
        end,
        ["vtsls"] = function() -- Very large import times
          lspconfig["vtsls"].setup({
            on_init = on_init,
            on_attach = on_attach,
            capabilities = capabilities,
            single_file_support = false,
            settings = {
              ---https://github.com/yioneko/vtsls/blob/main/packages/service/configuration.schema.json
              typescript = {
                tsserver = { log = vim.env.LSP_LOG_LEVEL == "TRACE" and "verbose" or "off" },
                ---https://www.typescriptlang.org/docs/handbook/release-notes/typescript-4-0.html#smarter-auto-imports
                ---https://github.com/yioneko/vtsls/blob/41ad8c9d3f9dbd122ce3259564f34d020b7d71d9/packages/service/configuration.schema.json#L779C29-L779C58
                preferences = { includePackageJsonAutoImports = "off" },
                ---https://github.com/yioneko/vtsls/blob/41ad8c9d3f9dbd122ce3259564f34d020b7d71d9/packages/service/configuration.schema.json#L1025C17-L1025C43
                preferGoToSourceDefinition = true,
                inlayHints = {
                  parameterNames = {
                    enabled = "all",
                  },
                  parameterTypes = {
                    enabled = true,
                  },
                  propertyDeclarationTypes = {
                    enabled = true,
                  },
                  functionLikeReturnTypes = {
                    enabled = true,
                  },
                  enumMemberValues = {
                    enabled = true,
                  },
                },
                referencesCodeLens = {
                  enabled = true,
                  showOnAllFunctions = true,
                },
                implementationsCodeLens = {
                  enabled = true,
                  showOnInterfaceMethods = true,
                },
              },
              vtsls = {
                autoUseWorkspaceTsdk = true,
                experimental = {
                  completion = {
                    enableServerSideFuzzyMatch = true,
                  },
                },
              },
            },
          })
        end,
      }

      ---Prevent server setup if a plugin exists for it
      custom["tsserver"] = function() end
      if utils.is_available("clangd_extensions.nvim") then custom["clangd"] = function() end end
      if utils.is_available("SchemaStore.nvim") then
        custom["yamlls"] = function() end
        custom["jsonls"] = function() end
      end

      local servers = utils.get_from_tools(tools.by_filetype, "lsp", true)
      local extensions = utils.get_from_tools(tools.by_filetype, "extensions", true)

      ---Setup servers that don't require any extra plugins
      ---Lsp servers that require plugins are lazy loaded on `CustomLSP<filetype>` events
      local function setup_base_servers()
        for _, server in ipairs(servers) do
          ---Prevent lsp server setup if coc-extension already support the same filetypes
          local module_name = server:gsub(".*/", ""):gsub("%.lua$", "")
          local server_config = require("lspconfig.server_configurations." .. module_name)
          local server_filetypes = server_config.default_config.filetypes
          for _, extension in ipairs(extensions) do
            local extension_filetypes = utils.get_filetypes_from_tool(tools.by_filetype, extension)
            for _, server_filetype in ipairs(server_filetypes) do
              if vim.list_contains(extension_filetypes, server_filetype) then custom[server] = function() end end
            end
          end

          if not vim.tbl_contains(vim.tbl_keys(custom), server) then
            ---Setup lsp servers through nvim-lspconfig defaults
            lspconfig[server].setup({
              on_init = on_init,
              on_attach = on_attach,
              capabilities = capabilities,
            })
          else
            ---Setup lsp servers throught custom handler
            custom[server]()
          end
        end
      end

      setup_base_servers()
    end,
  },
}
