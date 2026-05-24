local constants = require("serranomorante.constants")

if not constants.BINARIES.tailwindcss_language_server then return {} end

---@type vim.lsp.Config
return {
  cmd = { constants.BINARIES.tailwindcss_language_server(), "--stdio" },
  filetypes = vim.list_extend(vim.deepcopy(constants.javascript_aliases), {
    "css",
    "html",
    "markdown",
    "php",
    "scss",
    "vue",
  }),
  root_markers = {
    "tailwind.config.js",
    "tailwind.config.cjs",
    "tailwind.config.mjs",
    "tailwind.config.ts",
    "postcss.config.js",
    "postcss.config.cjs",
    "postcss.config.mjs",
    "postcss.config.ts",
  },
  settings = {
    tailwindCSS = {
      classAttributes = { "class", "className", "class:list", "classList", "ngClass" },
      validate = true,
    },
  },
}
