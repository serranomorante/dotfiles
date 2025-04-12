local binaries = require("serranomorante.binaries")
local constants = require("serranomorante.constants")

---@type vim.lsp.Config
return {
  cmd = { binaries.system_default_node(), binaries.vtsls(), "--stdio" },
  filetypes = constants.javascript_aliases,
  root_markers = {
    "tsconfig.json",
    "package.json",
    "jsconfig.json",
    ".git",
  },
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
}
