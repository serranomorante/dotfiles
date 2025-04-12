_G.user = _G.user or {}
---https://github.com/stevearc/resession.nvim/issues/44#issuecomment-2027345600
function P(v) vim.cmd.echom({ args = { vim.fn.string(vim.inspect(v)) }, mods = { unsilent = true } }) end
