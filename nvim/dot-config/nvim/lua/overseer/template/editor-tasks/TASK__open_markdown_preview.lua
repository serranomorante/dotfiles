local coc_utils = require("serranomorante.plugins.coc.utils")

---@type overseer.TemplateDefinition
return {
  name = "editor-tasks-open-markdown-preview",
  desc = "Open markdown preview",
  builder = function()
    return {
      cmd = { "nvr" },
      args = { "--servername", vim.v.servername, "-c", "CocCommand markdown-preview-enhanced.openPreviewBackground" },
      components = {
        "unique",
        "defaults_without_notification",
      },
    }
  end,
  condition = {
    callback = function(search)
      if not coc_utils.is_coc_attached() then return false end
      return vim.list_contains({ "markdown" }, search.filetype)
    end,
  },
}
