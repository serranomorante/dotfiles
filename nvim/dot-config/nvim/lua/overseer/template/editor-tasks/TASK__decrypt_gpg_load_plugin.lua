local utils = require("serranomorante.utils")

local task_name = "editor-tasks-decrypt-and-load-plugin"

---@type overseer.TemplateDefinition
return {
  name = task_name,
  desc = "Decrypt and load plugin",
  params = {
    parser_capture_group_name = {
      desc = "Name of the capture group property for the parser",
      type = "string",
      default = "openai_key",
      optional = false,
      order = 1,
    },
    plugin = {
      desc = "Name of the plugin to load",
      type = "enum",
      choices = { "gp" },
      optional = false,
      order = 2,
    },
    plugin_opt_name = {
      desc = "Name of the option where we should set the decrypted content",
      type = "string",
      default = "openai_api_key",
      optional = false,
      order = 3,
    },
  },
  builder = function(params)
    local args = { "--decrypt", utils.join_paths(vim.env.HOME, "openai_api_key.asc") }
    return {
      cmd = { "gpg" },
      args = args,
      components = {
        {
          "editor-components.COMPONENT__lazy_load_on_gpg_decrypt",
          parser = { { "extract", "(sk%-.*)", params.parser_capture_group_name } },
          plugin = params.plugin,
          parser_capture_group_name = params.parser_capture_group_name,
          plugin_opt_name = params.plugin_opt_name,
        },
        "defaults_without_notification",
      },
    }
  end,
  tags = { "editor-tasks" },
}
