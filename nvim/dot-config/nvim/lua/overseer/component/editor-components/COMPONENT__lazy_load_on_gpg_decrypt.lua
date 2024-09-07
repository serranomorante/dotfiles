---@type overseer.ComponentDefinition
return {
  name = "editor-components: lazy load plugin after gpg decryption",
  params = {
    parser = {
      desc = "Parser definition to extract values from output",
      type = "opaque",
      optional = false,
      order = 1,
    },
    parser_capture_group_name = {
      desc = "Name of the capture group property for the parser",
      type = "string",
      optional = false,
      order = 2,
    },
    plugin = {
      desc = "Name of the plugin to load",
      type = "string",
      optional = false,
      order = 3,
    },
    plugin_opt_name = {
      desc = "Name of the option where we should set the decrypted content",
      type = "string",
      optional = false,
      order = 4,
    },
  },
  constructor = function(params)
    local overseer = require("overseer")
    local parser = require("overseer.parser")
    local parser_defn = params.parser or {}

    return {
      on_init = function(self)
        ---When decryption is done sucessfully
        self.parser = parser.new(parser_defn)
      end,
      on_output = function(self, task, data)
        ---Open float when prompted for passphrase
        if vim.islist(data) and data ~= nil then
          for _, line in ipairs(data) do
            local is_passphrase_prompt = string.match(line, "Passphrase:")
            if is_passphrase_prompt ~= nil then
              overseer.run_action(task, "open float")
              vim.defer_fn(function()
                if vim.api.nvim_get_option_value("buftype", { buf = 0 }) == "terminal" then vim.cmd("startinsert") end
              end, 300)
            end
          end
        end
      end,
      on_output_lines = function(self, task, lines) self.parser:ingest(lines) end,
      on_complete = function(self, task, status, result)
        local decrypted_content = unpack(self.parser:get_result())
        if decrypted_content == nil then
          vim.notify("Couldn't decrypt gpg content", vim.log.levels.ERROR)
          return
        end

        ---Close the terminal to prevent showing decrypted content on the screen
        local winbuf = vim.api.nvim_win_get_buf(0)
        local buftype = vim.api.nvim_get_option_value("buftype", { buf = winbuf })
        if buftype == "terminal" then vim.api.nvim_win_close(0, true) end
        vim.cmd.packadd(params.plugin)
        local opts = { [params.plugin_opt_name] = decrypted_content[params.parser_capture_group_name] }
        require("serranomorante.plugins." .. params.plugin).config(nil, opts)
      end,
    }
  end,
}
