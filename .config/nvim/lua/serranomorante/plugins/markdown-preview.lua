return {
  "iamcco/markdown-preview.nvim",
  enabled = vim.fn.executable("npm") == 1,
  cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
  ---https://github.com/iamcco/markdown-preview.nvim/issues/616
  build = "cd app && npm install --no-save && git restore .",
  init = function()
    vim.g.mkdp_filetypes = { "markdown" }
    vim.g.mkdp_auto_close = 0
    vim.g.mkdp_command_for_global = 1
    vim.g.mkdp_combine_preview = 1

    local function load_then_exec(cmd)
      return function()
        vim.cmd.delcommand(cmd)
        ---@diagnostic disable-next-line: different-requires
        require("lazy").load({ plugins = { "markdown-preview.nvim" } })
        vim.api.nvim_exec_autocmds("BufEnter", {}) -- commands appear only after BufEnter
        vim.cmd(cmd)
      end
    end

    ---Fixes "No command :MarkdownPreview"
    ---https://github.com/iamcco/markdown-preview.nvim/issues/585#issuecomment-1724859362
    for _, cmd in pairs({ "MarkdownPreview", "MarkdownPreviewStop", "MarkdownPreviewToggle" }) do
      vim.api.nvim_create_user_command(cmd, load_then_exec(cmd), {})
    end
  end,
}
