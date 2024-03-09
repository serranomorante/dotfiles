local M = {}

---Useful way of organizing some common filetypes
M.c_filetypes = { "c" }
M.python_filetypes = { "python" }
M.javascript_filetypes = { "typescript", "javascript", "javascriptreact", "typescriptreact" }
M.lua_filetypes = { "lua" }
M.markdown_filetypes = { "markdown" }
M.json_filetypes = { "json", "jsonc" }

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

return M
