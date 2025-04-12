local binaries = require("serranomorante.binaries")
local constants = require("serranomorante.constants")

local javascript_plain_object = { ":\\s*?[\"'`]([^\"'`]*).*?," }
---https://cva.style/docs/getting-started/installation#intellisense
local cva = { "cva\\(([^)]*)\\)", "[\"'`]([^\"'`]*).*?[\"'`]" }
local cva_cx = { "cx\\(([^)]*)\\)", "(?:'|\"|`)([^']*)(?:'|\"|`)" }

---@type vim.lsp.Config
return {
  cmd = { binaries.tailwindcss_language_server(), "--stdio" },
  filetypes = constants.javascript_aliases,
  root_markers = {
    "tailwind.config.js",
    "tailwind.config.cjs",
    "tailwind.config.mjs",
    "tailwind.config.ts",
    "postcss.config.js",
    "postcss.config.cjs",
    "postcss.config.mjs",
    "postcss.config.ts",
    "package.json",
    "node_modules",
    ".git",
  },
  ---https://github.com/paolotiu/tailwind-intellisense-regex-list?tab=readme-ov-file#plain-javascript-object
  settings = {
    tailwindCSS = {
      experimental = { classRegex = { cva, cva_cx, javascript_plain_object } },
    },
  },
}
