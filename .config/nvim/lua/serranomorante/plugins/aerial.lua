return {
  "stevearc/aerial.nvim",
  lazy = true,
  keys = {
    {
      "<leader>at",
      function()
        local backends = vim.list_contains(vim.b.aerial_backends or {}, "treesitter") and { "lsp" } or { "treesitter" }
        vim.b.aerial_backends = backends
        vim.notify("Aerial: now using " .. backends[1] .. " backend", vim.log.levels.WARN)
        require("aerial").refetch_symbols()
        vim.cmd.redrawstatus()
      end,
      desc = "Aerial: toggle between treesitter and lsp backend per buffer",
    },
  },
  opts = {
    show_guides = true,
    filter_kind = false,
    disable_max_lines = vim.g.max_file.lines,
    disable_max_size = vim.g.max_file.size,
    highlight_on_jump = 1000,
    backends = { "lsp", "coc" },
    layout = {
      default_direction = "float",
    },
    float = {
      border = "single",
      relative = "editor",
    },
    keymaps = {
      ["l"] = false,
      ["L"] = false,
      ["h"] = false,
      ["H"] = false,
    },
  },
}
