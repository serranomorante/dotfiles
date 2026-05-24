local constants = require("serranomorante.constants")

if not constants.BINARIES.vtsls then return {} end

local inlay_hints = {
  parameterNames = { enabled = "all" },
  parameterTypes = { enabled = true },
  variableTypes = { enabled = true },
  propertyDeclarationTypes = { enabled = true },
  functionLikeReturnTypes = { enabled = true },
  enumMemberValues = { enabled = true },
}

---@type vim.lsp.Config
return {
  cmd = { constants.BINARIES.vtsls(), "--stdio" },
  filetypes = constants.javascript_aliases,
  init_options = {
    hostInfo = "neovim",
  },
  root_markers = {
    "tsconfig.json",
    "jsconfig.json",
    "package.json",
    ".git",
  },
  settings = {
    vtsls = {
      autoUseWorkspaceTsdk = true,
    },
    typescript = {
      implementationsCodeLens = { enabled = true },
      referencesCodeLens = { enabled = true },
      preferences = {
        importModuleSpecifier = "non-relative",
      },
      suggest = {
        completeFunctionCalls = false,
      },
      inlayHints = inlay_hints,
    },
    javascript = {
      implementationsCodeLens = { enabled = true },
      referencesCodeLens = { enabled = true },
      preferences = {
        importModuleSpecifier = "non-relative",
      },
      suggest = {
        completeFunctionCalls = false,
      },
      inlayHints = inlay_hints,
    },
  },
}
