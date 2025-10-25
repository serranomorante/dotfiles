local constants = require("serranomorante.constants")

---@type vim.lsp.Config
return {
  cmd = { constants.BINARIES.lua_language_server() },
  filetypes = constants.lua_aliases,
  root_markers = {
    ".luarc.json",
    ".stylua.toml",
    ".git",
  },
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
}
