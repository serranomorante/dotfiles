local utils = require("serranomorante.utils")

local task_name = "editor-tasks-export-markdown"

---@type overseer.TemplateDefinition
return {
  name = task_name,
  desc = "Export markdown",
  builder = function()
    local input = vim.fn.expand("%:p")
    local output = vim.fn.fnamemodify(input, ":r") .. ".pdf"
    local fullhrule = ("%s/fullhrule.tex"):format(vim.fn.getcwd())
    local bib_file = ("%s/myrefs.public.bib"):format(vim.fn.getcwd())

    local args = {
      "--from=markdown+rebase_relative_paths",
      "-V",
      "pagestyle=empty",
      "--pdf-engine=xelatex",
      "--mathjax",
      "--filter=mermaid-filter",
      "--citeproc",
    }
    if vim.fn.filereadable(fullhrule) == 1 then table.insert(args, ("--include-in-header=%s"):format(fullhrule)) end
    if vim.fn.filereadable(bib_file) == 1 then table.insert(args, ("--bibliography=%s"):format(bib_file)) end

    local command = vim.list_extend({ "pandoc" }, vim.list_extend(args, { input, "-o", output }))

    return {
      cmd = { "tmux" },
      args = utils.wrap_overseer_args_with_tmux(command, task_name .. input),
      components = {
        "unique",
        "default",
      },
    }
  end,
  condition = {
    callback = function(search)
      return vim.fn.executable("pandoc") == 1 and vim.list_contains({ "markdown" }, search.filetype)
    end,
  },
}
