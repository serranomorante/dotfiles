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
        { "open_output", direction = "tab", on_start = "always", focus = true },
        { "on_complete_dispose", timeout = 1, statuses = { require("overseer.constants").STATUS.SUCCESS } },
        "unique",
        "defaults_without_notification",
      },
    }
  end,
  condition = {
    filetype = "markdown",
  },
}
