local utils = require("serranomorante.utils")

return {
  name = "Decrypt OpenAI key and load gp.nvim plugin",
  builder = function()
    return {
      cmd = { "gpg" },
      args = { "--decrypt", utils.join_paths(vim.env.HOME, "openai_api_key.asc") },
      components = {
        {
          "editor.lazy_load_on_gpg_decrypt",
          parser = {
            { "extract", "(sk%-.*)", "openai_key" },
          },
          parser_capture_group_name = "openai_key",
          plugin = "gp.nvim",
          plugin_opt_name = "openai_api_key",
        },
        "default",
      },
    }
  end,
  tags = { "editor" },
}
