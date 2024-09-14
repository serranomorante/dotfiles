local binaries = require("serranomorante.binaries")
local nvim_library = {}

return {
  ---@param bufnr integer
  ---@return vim.lsp.ClientConfig
  config = function(bufnr)
    ---@type vim.lsp.ClientConfig
    return {
      name = "lua_language_server",
      cmd = { binaries.lua_language_server() },
      capabilities = {
        textDocument = {
          foldingRange = { dynamicRegistration = false, lineFoldingOnly = true },
        },
      },
      before_init = function()
        table.insert(nvim_library, vim.env.VIMRUNTIME)
        table.insert(nvim_library, "${3rd}/busted/library")
        table.insert(nvim_library, "${3rd}/luv/library")
        table.insert(nvim_library, vim.fn.stdpath("data") .. "/site/pack/plugins/start/overseer/lua")
        table.insert(nvim_library, vim.fn.stdpath("data") .. "/site/pack/plugins/start/dap/lua")
        table.insert(nvim_library, vim.fn.stdpath("data") .. "/site/pack/plugins/start/quicker/lua")
      end,
      on_init = function(client)
        ---Disable semanticTokensProvider
        ---https://gist.github.com/swarn/fb37d9eefe1bc616c2a7e476c0bc0316
        client.server_capabilities.semanticTokensProvider = nil
        if client.server_capabilities.signatureHelpProvider then
          client.server_capabilities.signatureHelpProvider.triggerCharacters = {}
        end
      end,
      settings = {
        Lua = {
          addonManager = { enable = false },
          format = { enable = true },
          codeLens = { enable = true },
          hint = { enable = true },
          runtime = { version = "LuaJIT" },
          telemetry = { enable = false },
          workspace = {
            checkThirdParty = false,
            library = nvim_library,
          },
        },
      },
      root_dir = vim.fs.root(bufnr, ".luarc.json") or vim.fs.root(0, { "lua", ".git" }),
    }
  end,
}
