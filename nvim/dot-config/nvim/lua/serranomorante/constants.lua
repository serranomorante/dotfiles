local M = {}

---Useful way of organizing some common filetypes
M.c_aliases = { "c" }
M.python_aliases = { "python" }
M.javascript_aliases = { "typescript", "javascript", "javascriptreact", "typescriptreact", "vue", "html" }
M.lua_aliases = { "lua" }
M.markdown_aliases = { "markdown" }
M.json_aliases = { "json", "jsonc" }
M.bash_aliases = { "sh", "bash" }
M.fish_aliases = { "fish" }
M.html_aliases = { "html", "htm" }
M.php_aliases = { "php" }
M.go_aliases = { "go" }

M.overseer_status = {
  ["FAILURE"] = { "F", "Red" },
  ["CANCELED"] = { "C", "Grey1" },
  ["SUCCESS"] = { "S", "Green" },
  ["RUNNING"] = { "R", "Cyan" },
}

---https://github.com/folke/ts-comments.nvim
M.commentstring_setup = {
  lang = {
    astro = "<!-- %s -->",
    c = "// %s",
    cpp = "// %s",
    css = "/* %s */",
    gleam = "// %s",
    glimmer = "{{! %s }}",
    graphql = "# %s",
    handlebars = "{{! %s }}",
    hcl = "# %s",
    html = "<!-- %s -->",
    ini = "; %s",
    php = "// %s",
    rego = "# %s",
    rescript = "// %s",
    sql = "-- %s",
    svelte = "<!-- %s -->",
    terraform = "# %s",
    tsx = {
      _ = "// %s",
      call_expression = "// %s",
      comment = "// %s",
      jsx_attribute = "// %s",
      jsx_element = "{/* %s */}",
      jsx_fragment = "{/* %s */}",
      spread_element = "// %s",
      statement_block = "// %s",
    },
    twig = "{# %s #}",
    typescript = "// %s",
    vim = '" %s',
    vue = "<!-- %s -->",
  },
}

M.commentstring_setup.lang.javascript = vim.deepcopy(M.commentstring_setup.lang.tsx)

M.POSITION_CURSOR_BETWEEN_QUOTES = "<HOME><C-Right><Right><Right>"

M.CWD = vim.fn.getcwd()

local ok, binaries = pcall(require, "serranomorante.binaries")
M.BINARIES = ok and binaries or {}

---@type overseer.JobstartStrategyOpts
M.fullscreen_jobstart_opts = {
  "jobstart",
  wrap_opts = {
    width = vim.o.columns,
    height = vim.o.lines - 3,
  },
}

M.NUMBERED_MARKS = { "'0", "'1", "'2", "'3", "'4", "'5", "'6", "'7", "'8", "'9" }
M.GLOBAL_MARKS = {
  ["'A"] = nil,
  ["'B"] = "me:finance",
  ["'C"] = "me:health",
  ["'D"] = "me:youtube",
  ["'E"] = "me:ideas 1",
  ["'F"] = "me:ideas 2",
  ["'G"] = "me:todos 1",
  ["'H"] = "me:todos 2",
  ["'I"] = nil,
  ["'J"] = "code:step-1",
  ["'K"] = "code:step-2",
  ["'L"] = nil,
  ["'M"] = "me:learning 1",
  ["'N"] = "me:learning 2",
  ["'O"] = nil,
  ["'P"] = "code:issues 1",
  ["'Q"] = "code:issues 2",
  ["'R"] = nil,
  ["'S"] = "me:journal 1",
  ["'T"] = "me:journal 2",
  ["'U"] = "me:journal 3",
  ["'V"] = "code:important 1",
  ["'W"] = "code:important 2",
  ["'X"] = "code:watch-later 1",
  ["'Y"] = "code:watch-later 2",
  ["'Z"] = nil,
}

return M
