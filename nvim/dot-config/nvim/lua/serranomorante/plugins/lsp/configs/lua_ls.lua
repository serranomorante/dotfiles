local binaries = require("serranomorante.binaries")

return {
  ---@param bufnr integer
  ---@return vim.lsp.ClientConfig
  config = function(bufnr)
    ---@type vim.lsp.ClientConfig
    return {
      name = "lua-lsp",
      cmd = { binaries.lua_language_server() },
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
          runtime = {
            version = "LuaJIT",
          },
          telemetry = { enable = false },
          workspace = {
            checkThirdParty = false,
          },
        },
      },
      root_dir = vim.fs.root(bufnr, {
        ".luarc.json",
        ".stylua.toml",
        ".git",
      }),
    }
  end,
}
