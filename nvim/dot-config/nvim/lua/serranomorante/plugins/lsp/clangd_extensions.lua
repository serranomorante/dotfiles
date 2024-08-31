  {
    "p00f/clangd_extensions.nvim",
    dependencies = "neovim/nvim-lspconfig",
    event = "User CustomLSPc,CustomLSPcpp",
    config = function()
      require("lspconfig")["clangd"].setup({
        on_init = on_init,
        capabilities = vim.tbl_deep_extend("force", capabilities, { offsetEncoding = "utf-16" }),
        on_attach = on_attach,
      })
    end,
  }
