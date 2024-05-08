return {
  "github/copilot.vim",
  cmd = "Copilot",
  init = function()
    vim.g.copilot_node_command = vim.g.node_system_executable
    vim.g.copilot_no_tab_map = true -- I use `tab` for completion
    vim.g.copilot_filetypes = {
      ["oil"] = false,
    }
    vim.g.copilot_enabled = false -- disable by default
  end,
  config = function()
    vim.keymap.set("i", "<M-c>", 'copilot#Accept("\\<CR>")', {
      expr = true,
      replace_keycodes = false,
      desc = "Copilot: Accept suggestion",
    })
  end,
}
