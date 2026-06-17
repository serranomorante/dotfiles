local M = {}

---Useful way of organizing some common filetypes
M.c_aliases = { "c" }
M.python_aliases = { "python" }
M.javascript_aliases = { "typescript", "javascript", "javascriptreact", "typescriptreact" }
M.lua_aliases = { "lua" }
M.markdown_aliases = { "markdown", "markdown.system_health" }
M.json_aliases = { "json", "jsonc" }
M.bash_aliases = { "sh", "bash" }
M.fish_aliases = { "fish" }
M.html_aliases = { "html", "htm" }
M.css_aliases = { "css", "scss" }
M.yaml_aliases = { "yaml", "yaml.ansible" }
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
  ["'O"] = "work:important 1",
  ["'P"] = "code:issues 1",
  ["'Q"] = "code:issues 2",
  ["'R"] = "work:important 2",
  ["'S"] = "me:journal 1",
  ["'T"] = "me:journal 2",
  ["'U"] = "me:journal 3",
  ["'V"] = "code:important 1",
  ["'W"] = "code:important 2",
  ["'X"] = "code:watch-later 1",
  ["'Y"] = "code:watch-later 2",
  ["'Z"] = nil,
}

M.GLOBAL_MARKS_BY_CWD = {
  [vim.env.HOME .. "/data/notes/foam"] = {
    ["'A"] = "todos:knowing", -- like the Nicolas Cage movie
    ["'B"] = "todos:personal",
    ["'C"] = "system:health",
    ["'D"] = "system:spikes",
    ["'E"] = "agent:runs",
    ["'F"] = "todos:finance",
    ["'G"] = "todos:events",
    ["'H"] = "todos:ai-autotrigger",
    ["'I"] = "system:features",
  },
}

local function normalize_path(path)
  if not path or path == "" then return "" end
  local expanded = vim.fn.expand(path)
  local real = (vim.uv or vim.loop).fs_realpath(expanded)
  local normalized = real or vim.fn.fnamemodify(expanded, ":p")
  normalized = normalized:gsub("/+$", "")
  return normalized == "" and "/" or normalized
end

---@param cwd? string
---@return table<string, string>
function M.global_marks_for_cwd(cwd)
  local normalized_cwd = normalize_path(cwd or vim.fn.getcwd())

  for mark_cwd, marks in pairs(M.GLOBAL_MARKS_BY_CWD) do
    if normalize_path(mark_cwd) == normalized_cwd then return marks end
  end

  return M.GLOBAL_MARKS
end

M.KEYRINGS = {
  anthropic = {
    folder = "dev-tools",
    passkey = "anthropic-api-key",
    wallet = "kdewallet",
  },
  claude_code = {
    folder = "dev-tools",
    passkey = "claude-code-token",
    wallet = "kdewallet",
  },
  openai = {
    folder = "dev-tools",
    passkey = "openai-api-key",
    wallet = "kdewallet",
  },
  gemini = {
    folder = "dev-tools",
    passkey = "gemini-api-key",
    wallet = "kdewallet",
  },
  davinci = {
    folder = "creative-tools",
    passkey = "davinci-resolve-blackmagic-pass",
    wallet = "kdewallet",
  },
}

return M
