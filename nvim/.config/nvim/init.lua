-- Use nvim 0.9+ new loader with byte-compilation cache
-- https://neovim.io/doc/user/lua.html#vim.loader
if vim.loader and vim.fn.has("nvim-0.9.1") == 1 then vim.loader.enable() end

require("serranomorante")
