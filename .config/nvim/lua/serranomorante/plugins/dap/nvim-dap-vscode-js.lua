return {
  "mxsdev/nvim-dap-vscode-js",
  dependencies = "mfussenegger/nvim-dap",
  enabled = false,
  event = "User CustomDAPLoadJavascript,CustomDAPLoadTypescript,CustomDAPLoadTypescriptreact,CustomDAPLoadJavascriptreact",
  config = function()
    ---https://github.com/mxsdev/nvim-dap-vscode-js?tab=readme-ov-file#debugger
    local vscode_js_debug_dir = vim.fn.stdpath("data") .. "/debuggers/vscode-js-debug"
    if not vim.fn.isdirectory(vscode_js_debug_dir) then
      vim.notify("No dir for `vscode-js-debug`", vim.log.levels.ERROR)
      return
    end

    ---https://github.com/mxsdev/nvim-dap-vscode-js?tab=readme-ov-file#setup
    require("dap-vscode-js").setup({
      node_path = vim.g.node_system_executable,
      debugger_path = vscode_js_debug_dir,
      adapters = { "pwa-node", "pwa-chrome", "pwa-msedge", "node-terminal", "pwa-extensionHost" },
      log_file_level = vim.log.levels[vim.env.DAP_LOG_LEVEL or "INFO"],
      log_console_level = false, -- too much noise
    })
  end,
}
