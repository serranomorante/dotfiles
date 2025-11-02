local task_name = "editor-tasks-open-markdown-preview"

---@type overseer.TemplateDefinition
return {
  name = task_name,
  desc = "Open markdown preview",
  builder = function()
    return {
      name = task_name,
      cmd = "kitty", -- for the image support
      args = {
        "@",
        "launch",
        "--type=overlay",
        "--cwd=current",
        "--var=is_markdown_preview",
        "--hold",
        "mdcat",
        "--no-pager",
        vim.fn.expand("%:p"),
      },
      components = {
        { "system-components/COMPONENT__close_window_on_exit_0" },
        { "open_output", direction = "float", on_start = "always", focus = true },
        { "on_complete_dispose", timeout = 1, statuses = { require("overseer.parser").STATUS.SUCCESS } },
        "unique",
        "defaults_without_notification",
      },
    }
  end,
  condition = {
    callback = function(search)
      return vim.fn.executable("mdcat") == 1 and vim.list_contains({ "markdown" }, search.filetype)
    end,
  },
}
