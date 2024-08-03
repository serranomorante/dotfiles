---Compiler plugin that make tsc work with monorepo

local tsconfig = vim.fs.find("tsconfig.json", {
  stop = vim.fn.getcwd() .. "/..",
  type = "file",
  upward = true,
  path = vim.fs.dirname(vim.api.nvim_buf_get_name(0)),
})

vim.opt_local.makeprg = "tsc -p " .. tsconfig[1]
vim.opt_local.errorformat = "%f %#(%l\\,%c): %trror TS%n: %m, %trror TS%n: %m, %%-G%.%#"
