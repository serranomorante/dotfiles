return {
  "mfussenegger/nvim-dap-python",
  dependencies = "mfussenegger/nvim-dap",
  event = "User CustomDAPpython",
  config = function()
    local mason_registry = require("mason-registry")
    local python_dap = mason_registry.get_package("debugpy")

    if python_dap then
      local dap_executable = python_dap:get_install_path() .. "/venv/bin/python"
      ---https://github.com/mfussenegger/nvim-dap-python?tab=readme-ov-file#usage
      require("dap-python").setup(dap_executable)
    end
  end,
}
