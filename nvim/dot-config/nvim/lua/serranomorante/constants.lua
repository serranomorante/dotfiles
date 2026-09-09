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

---Normal-mode chords that forward the tmux prefix (Ctrl-S, see tmux.conf) to a
---tmux running inside a Neovim terminal buffer, where Normal mode would swallow
---the keys. `keys` are the tmux keys typed right after the prefix. To add a new
---passthrough, append an entry here; the terminal keymap autocmd registers it.
---@class TmuxPrefixPassthrough
---@field lhs string # Neovim Normal-mode mapping to define
---@field keys string # tmux keys sent after the Ctrl-S prefix
---@field desc string
---@field terminal_mode? boolean # enter Terminal mode after sending (default true)
M.TMUX_PREFIX_PASSTHROUGHS = {
  {
    lhs = "<C-s>g",
    keys = "g", -- tmux root binding: copy-mode marks picker
    desc = "Send C-s g (tmux prefix) to the nested tmux",
  },
}

M.KEYRINGS = {
  anthropic = {
    folder = "dev-tools",
    passkey = "anthropic-api-key",
    wallet = "kdewallet",
  },
  deepseek = {
    folder = "dev-tools",
    passkey = "deepseek-api-key",
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
