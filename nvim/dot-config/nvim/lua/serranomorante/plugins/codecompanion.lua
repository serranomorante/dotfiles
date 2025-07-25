---https://github.com/olimorris/dotfiles/blob/main/.config/nvim/lua/plugins/coding.lua

local utils = require("serranomorante.utils")

local M = {}

M.PLUGIN = "codecompanion"

local function init()
  ---Expand 'cc' into 'CodeCompanion' in the command line
  vim.cmd([[cab cc CodeCompanion]])
end

local function keys()
  vim.keymap.set(
    { "n", "v" },
    "<C-a>",
    "<cmd>CodeCompanionActions<cr>",
    { noremap = true, silent = true, desc = "[AI]: Actions" }
  )
  vim.keymap.set(
    { "n", "v" },
    "<leader>a",
    "<cmd>CodeCompanionChat Toggle<cr>",
    { noremap = true, silent = true, desc = "[AI]: Chat toggle" }
  )
  vim.keymap.set(
    "v",
    "ga",
    "<cmd>CodeCompanionChat Add<cr>",
    { noremap = true, silent = true, desc = "[AI]: Chat add" }
  )
end

local function opts()
  return {
    display = {
      chat = {
        intro_message = "",
        auto_scroll = false,
      },
    },
    diff = {
      enabled = false,
    },
    adapters = {
      openai = function()
        return require("codecompanion.adapters").extend("openai", {
          opts = {
            stream = true,
          },
          env = {
            api_key = "cmd: gpg --decrypt ~/openai_api_key.asc 2>/dev/null",
          },
          schema = {
            model = {
              default = function() return "gpt-4.1" end,
            },
          },
        })
      end,
      anthropic = function()
        return require("codecompanion.adapters").extend("anthropic", {
          env = {
            api_key = "cmd: gpg --decrypt ~/secrets/anthropic_api_key.gpg 2>/dev/null",
          },
        })
      end,
    },
    strategies = {
      chat = {
        adapter = "openai",
        tools = {
          opts = {
            auto_submit_errors = false,
            auto_submit_success = true,
          },
        },
        keymaps = {
          send = {
            modes = {
              n = "<C-g><C-g>",
              i = "<C-g><C-g>",
            },
          },
          completion = {
            modes = {
              i = "<C-x><C-\\>"
            }
          }
        }
      },
      inline = {
        adapter = "anthropic",
      },
    },
    extensions = {
      mcphub = {
        callback = "mcphub.extensions.codecompanion",
        opts = {
          make_vars = true,
          make_slash_commands = true,
          show_result_in_chat = false,
        },
      },
    },
  }
end

function M.config()
  local path = utils.installation_path(M.PLUGIN)
  if path == "" then
    local msg = 'Plugin "%s" not installed'
    return vim.api.nvim_echo({ { msg:format(M.PLUGIN) } }, false, { err = true })
  end

  init()
  keys()
  require(M.PLUGIN).setup(opts())
end

return M
