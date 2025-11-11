require("serranomorante.plugins.treesitter.treesitter").config()
require("serranomorante.plugins.treesitter.treesitter-context").config()

---Hide all highlights from the following languages
---I want to keep the parsers installed, but I don't want to get its higlights.
for _, lang in ipairs({ "luadoc", "jsdoc" }) do
  local ok, highlights = pcall(vim.treesitter.query.get, lang, "highlights")
  if not ok or not highlights then return end
  for _, group in ipairs(highlights.captures) do
    local hl_group = "@%s.%s"
    vim.api.nvim_set_hl(0, hl_group:format(group, lang), {})
  end
end
