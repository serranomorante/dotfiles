return {
  "NMAC427/guess-indent.nvim",
  event = "BufReadPost",
  config = function(_, opts)
    require("guess-indent").setup(opts)
    vim.cmd.lua({ args = { "require('guess-indent').set_from_buffer('auto_cmd')" }, mods = { silent = true } })
  end,
}
