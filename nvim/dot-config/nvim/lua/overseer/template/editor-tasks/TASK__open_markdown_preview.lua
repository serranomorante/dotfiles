local task_name = "editor-tasks-open-markdown-preview"

---@type overseer.TemplateDefinition
return {
  name = task_name,
  desc = "Open markdown preview",
  builder = function()
    return {
      name = task_name,
      cmd = "kitty",
      args = {
        "@",
        "launch",
        "--location=vsplit",
        "--bias=50",
        "--hold",
        "bash",
        "-c",
        string.format("mdcat --no-pager %s", vim.fn.expand("%:p")),
      },
      components = {
        { "open_output", direction = "float", on_start = "always", focus = true },
        "unique",
        "defaults_without_notification",
      },
    }
  end,
  condition = {
    callback = function(search)
      return vim.fn.executable("lowdown") == 1 and vim.list_contains({ "markdown" }, search.filetype)
    end,
  },
}
