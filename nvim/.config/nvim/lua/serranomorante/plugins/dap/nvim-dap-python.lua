return {
  "mfussenegger/nvim-dap-python",
  dependencies = "mfussenegger/nvim-dap",
  event = "User CustomDAPpython",
  config = function()
    local python_dap = vim.env.HOME .. "/apps/lang-tools/debugpy/.venv/bin/python"

    if vim.fn.executable(python_dap) == 1 then
      ---https://github.com/mfussenegger/nvim-dap-python?tab=readme-ov-file#usage
      require("dap-python").setup(python_dap)
    end
  end,
}
