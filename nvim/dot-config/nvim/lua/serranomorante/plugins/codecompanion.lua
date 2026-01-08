---https://github.com/olimorris/dotfiles/blob/main/.config/nvim/lua/plugins/coding.lua

local utils = require("serranomorante.utils")
local constants = require("serranomorante.constants")

local M = {}

M.PLUGIN = "codecompanion"

---@param provider "openai"|"gemini"|"anthropic"
local function api_key_gen(provider)
  return string.format(
    "cmd: kwallet-query --folder %s --read-password %s %s",
    constants.KEYRINGS[provider].folder,
    constants.KEYRINGS[provider].passkey,
    constants.KEYRINGS[provider].wallet
  )
end

local function init()
  ---Expand 'cc' into 'CodeCompanion' in the command line
  vim.cmd([[cab cc CodeCompanion]])

  vim.api.nvim_create_autocmd("BufEnter", {
    desc = "Force removing winhighlight when buffer is not codecompanion filetype",
    group = vim.api.nvim_create_augroup("codecompanion-bg-highlight", { clear = true }),
    callback = function(args)
      if vim.api.nvim_get_option_value("filetype", { buf = args.buf }) == "codecompanion" then return end
      local winid = vim.fn.bufwinid(args.buf)
      if vim.api.nvim_get_option_value("winhl", { win = winid == -1 and 0 or winid }):match("CustomAI") then
        vim.api.nvim_set_option_value("winhl", "", { win = winid })
      end
    end,
  })
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
  local ok, private_opts = pcall(require, "serranomorante.private-opts")
  local _opts = {
    ignore_warnings = true,
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
      acp = {
        claude_code = function()
          return require("codecompanion.adapters").extend("claude_code", {
            env = {
              ANTHROPIC_API_KEY = api_key_gen("anthropic"),
            },
          })
        end,
        gemini_cli = function()
          return require("codecompanion.adapters").extend("gemini_cli", {
            defaults = {
              ---@type "oauth-personal"|"gemini-api-key"
              auth_method = "oauth-personal", --oauth-personal is the only method that works now
              timeout = 20000, -- 20 seconds
            },
            env = {
              GEMINI_API_KEY = api_key_gen("gemini"),
            },
          })
        end,
      },
      http = {
        gemini = function()
          return require("codecompanion.adapters").extend("gemini", {
            env = {
              api_key = api_key_gen("gemini"),
            },
          })
        end,
        openai = function()
          return require("codecompanion.adapters").extend("openai", {
            opts = {
              stream = true,
            },
            env = {
              api_key = api_key_gen("openai"),
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
              api_key = api_key_gen("anthropic"),
            },
          })
        end,
      },
    },
    interactions = {
      chat = {
        adapter = "gemini",
        tools = {
          opts = {
            auto_submit_errors = false,
            auto_submit_success = true,
          },
        },
        keymaps = {
          options = {
            modes = { n = "<C-g>?" },
          },
          completion = {
            modes = {
              i = "<C-x><C-\\>",
            },
          },
          send = {
            modes = {
              n = "<C-g><C-g>",
              i = "<C-g><C-g>",
            },
          },
          regenerate = {
            modes = { n = "<C-g>gr" },
          },
          close = {
            modes = {
              n = "<C-c>",
              i = "<C-c>",
            },
          },
          stop = {
            modes = { n = "q" },
          },
          clear = {
            modes = { n = "gx" },
          },
          codeblock = {
            modes = { n = "gc" },
          },
          yank_code = {
            modes = { n = "gy" },
          },
          buffer_sync_all = {
            modes = { n = "gp" },
          },
          buffer_sync_diff = {
            modes = { n = "gw" },
          },
          next_chat = {
            modes = { n = "}" },
          },
          previous_chat = {
            modes = { n = "{" },
          },
          next_header = {
            modes = { n = "]]" },
          },
          previous_header = {
            modes = { n = "[[" },
          },
          change_adapter = {
            modes = { n = "ga" },
          },
          fold_code = {
            modes = { n = "gf" },
          },
          debug = {
            modes = { n = "gd" },
          },
          system_prompt = {
            modes = { n = "gs" },
          },
          rules = {
            modes = { n = "gM" },
          },
          yolo_mode = {
            modes = { n = "gty" },
          },
          goto_file_under_cursor = {
            modes = { n = "gR" },
          },
          copilot_stats = {
            modes = { n = "gS" },
          },
          super_diff = {
            modes = { n = "gD" },
          },
        },
        slash_commands = {
          image = {
            opts = {
              dirs = { vim.env.HOME .. "/Pictures" },
            },
          },
        },
      },
      inline = {
        adapter = "anthropic",
      },
      cmd = {
        adapter = "gemini_cli",
      },
    },
    extensions = {
      vectorcode = {
        ---@type VectorCode.CodeCompanion.ExtensionOpts
        opts = {
          prompt_library = {},
          tool_group = {
            enabled = true,
            extras = {},
            collapse = false,
          },
          tool_opts = {
            ---@type VectorCode.CodeCompanion.QueryToolOpts
            query = {
              chunk_mode = true,
            },
          },
        },
      },
      history = {
        enabled = true,
        ---@type CodeCompanion.History.Opts
        opts = {
          auto_generate_title = false,
          chat_filter = function(chat_data) return constants.CWD == chat_data.cwd end,
        },
      },
      mcphub = {
        callback = "mcphub.extensions.codecompanion",
        opts = {
          make_vars = true,
          make_slash_commands = true,
          show_result_in_chat = false,
        },
      },
    },
    prompt_library = {
      ["Write jsdocs"] = {
        interaction = "inline",
        description = "Write jsdoc documentation",
        opts = {
          short_name = "docs",
        },
        prompts = {
          {
            role = "user",
            content = "Write a jsdoc for this method and add a brief description (2 lines max). Leave a 1 line space between description and jsdoc",
          },
        },
      },
      ["Generate a Commit Message"] = {
        interaction = "inline",
        description = "Generate a commit message",
        opts = {
          index = 10,
          is_preset = true,
          is_slash_cmd = true,
          short_name = "commit",
          auto_submit = true,
        },
        prompts = {
          {
            role = "user",
            content = function()
              return string.format(
                [[You are an expert at following the Conventional Commit specification. Given the git diff listed below, please generate a commit message for me:

                ```diff
                %s
                ```
                ]],
                vim.fn.system("git diff --no-ext-diff --staged")
              )
            end,
            opts = {
              contains_code = true,
            },
          },
        },
      },
    },
    opts = {
      log_level = "INFO", -- or "TRACE"
    },
  }
  return vim.tbl_deep_extend("force", _opts, ok and private_opts or {})
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
