return {
  "echasnovski/mini.comment",
  dependencies = "JoosepAlviste/nvim-ts-context-commentstring",
  keys = {
    {
      "gc",
      mode = { "n", "v" },
      desc = "Comment toggle",
    },
    {
      "gcc",
      desc = "Comment toggle linewise",
    },
  },
  opts = {
    options = {
      ---https://github.com/echasnovski/mini.nvim/issues/342#issuecomment-1565644200
      ---https://github.com/JoosepAlviste/nvim-ts-context-commentstring/wiki/Integrations#minicomment
      custom_commentstring = function()
        return require("ts_context_commentstring.internal").calculate_commentstring() or vim.bo.commentstring
      end,
    },
  },
}
