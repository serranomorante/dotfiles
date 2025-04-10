---https://github.com/stevearc/resession.nvim/issues/44#issuecomment-2027345600
P = function(v) vim.cmd.echom({ args = { vim.fn.string(vim.inspect(v)) }, mods = { unsilent = true } }) end
