local M = {}

---Useful way of organizing some common filetypes
M.c_filetypes = { "c" }
M.python_filetypes = { "python" }
M.javascript_filetypes = { "typescript", "javascript", "javascriptreact", "typescriptreact" }
M.lua_filetypes = { "lua" }
M.markdown_filetypes = { "markdown" }
M.json_filetypes = { "json", "jsonc" }
M.bash_filetypes = { "sh", "bash" }

---Map `vim.fn.mode()` to mode text and highlight color
---https://github.com/AstroNvim/AstroNvim/blob/f8b94716912ad867998e0659497884d577cd9ec1/lua/astronvim/utils/status/env.lua#L33
M.modes = {
  ["n"] = { "NORMAL", "normal" },
  ["no"] = { "OP", "normal" },
  ["nov"] = { "OP", "normal" },
  ["noV"] = { "OP", "normal" },
  ["no"] = { "OP", "normal" },
  ["niI"] = { "NORMAL", "normal" },
  ["niR"] = { "NORMAL", "normal" },
  ["niV"] = { "NORMAL", "normal" },
  ["i"] = { "INSERT", "insert" },
  ["ic"] = { "INSERT", "insert" },
  ["ix"] = { "INSERT", "insert" },
  ["t"] = { "TERM", "terminal" },
  ["nt"] = { "TERM", "terminal" },
  ["v"] = { "VISUAL", "visual" },
  ["vs"] = { "VISUAL", "visual" },
  ["V"] = { "LINES", "visual" },
  ["Vs"] = { "LINES", "visual" },
  [""] = { "BLOCK", "visual" },
  ["s"] = { "BLOCK", "visual" },
  ["R"] = { "REPLACE", "replace" },
  ["Rc"] = { "REPLACE", "replace" },
  ["Rx"] = { "REPLACE", "replace" },
  ["Rv"] = { "V-REPLACE", "replace" },
  ["s"] = { "SELECT", "visual" },
  ["S"] = { "SELECT", "visual" },
  [""] = { "BLOCK", "visual" },
  ["c"] = { "COMMAND", "command" },
  ["cv"] = { "COMMAND", "command" },
  ["ce"] = { "COMMAND", "command" },
  ["r"] = { "PROMPT", "inactive" },
  ["rm"] = { "MORE", "inactive" },
  ["r?"] = { "CONFIRM", "inactive" },
  ["!"] = { "SHELL", "inactive" },
  ["null"] = { "null", "inactive" },
}

M.overseer_status = {
  ["FAILURE"] = { "F", "red" },
  ["CANCELED"] = { "C", "gray" },
  ["SUCCESS"] = { "S", "green" },
  ["RUNNING"] = { "R", "cyan" },
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

M.regex_filters = {}
---@param filter function|string|table
---@param filetypes string[]
local function add_regex_filter(filter, filetypes)
  M.regex_filters =
    vim.tbl_deep_extend("force", M.regex_filters, vim.tbl_map(function(ft) M.regex_filters[ft] = filter end, filetypes))
end

add_regex_filter(function(item)
  if item.text:match("^import%s.*from.*") then return false end
  return true
end, M.javascript_filetypes)

add_regex_filter(function(item)
  if item.text:match("^from%s.*import.*") then return false end
  if item.text:match("^import%s.*") then return false end
  return true
end, M.python_filetypes)

return M
