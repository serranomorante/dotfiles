local utils = require("serranomorante.utils")
local binaries = require("serranomorante.binaries")

return {
  ---@param bufnr integer
  ---@return vim.lsp.ClientConfig
  config = function(bufnr)
    ---This env variable comes from my personal .bashrc file
    local system_node_version = vim.env.SYSTEM_DEFAULT_NODE_VERSION or "latest"
    ---Bypass volta's context detection to prevent running the debugger with unsupported node versions
    local node_path = utils.cmd({ "volta", "run", "--node", system_node_version, "which", "node" }):gsub("\n", "")

    return {
      name = "vtsls",
      cmd = { node_path, binaries.vtsls(), "--stdio" },
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
      root_dir = vim.fs.root(bufnr, {
        "tsconfig.json",
        "package.json",
        "jsconfig.json",
        ".git",
      }),
    }
  end,
}
