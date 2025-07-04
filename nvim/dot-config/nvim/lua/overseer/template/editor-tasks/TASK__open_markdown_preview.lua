local utils = require("serranomorante.utils")
local task_name = "editor-tasks-open-markdown-preview"

---@type overseer.TemplateDefinition
return {
  name = task_name,
  desc = "Open markdown preview",
  builder = function()
    local file = vim.fn.expand("%:p")
    local command = { ("lowdown -Tterm %s | less -R"):format(file) }
    return {
      cmd = { "tmux" },
      args = utils.wrap_overseer_args_with_tmux(command, { session_name = task_name .. file }),
      env = {
        LESS = "-N",
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
