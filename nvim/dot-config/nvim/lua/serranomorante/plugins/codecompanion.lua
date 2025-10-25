---https://github.com/olimorris/dotfiles/blob/main/.config/nvim/lua/plugins/coding.lua

local utils = require("serranomorante.utils")
local constants = require("serranomorante.constants")

local M = {}

M.PLUGIN = "codecompanion"

local function init()
  ---Expand 'cc' into 'CodeCompanion' in the command line
  vim.cmd([[cab cc CodeCompanion]])

  vim.api.nvim_create_autocmd("User", {
    desc = "Force redraw to display codecompanion model",
    pattern = "CodeCompanionChatModel",
    group = vim.api.nvim_create_augroup("codecompanion-model-name", { clear = true }),
    callback = function() vim.defer_fn(vim.cmd.redrawstatus, 500) end,
  })

  vim.api.nvim_create_autocmd("BufWinEnter", {
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
  local ok, private_prompts = pcall(require, "serranomorante.private-prompts")
  local prompts = {
    ["Write jsdocs"] = {
      strategy = "inline",
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
      strategy = "inline",
      description = "Generate a commit message",
      opts = {
        index = 10,
        is_default = true,
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
  }
  if ok then prompts = vim.tbl_deep_extend("force", prompts, private_prompts or {}) end

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
      acp = {
        claude_code = function()
          return require("codecompanion.adapters").extend("claude_code", {
            env = {
              ANTHROPIC_API_KEY = "cmd: gpg --decrypt ~/secrets/anthropic_api_key.gpg 2>/dev/null",
            },
          })
        end,
        gemini_cli = function()
          return require("codecompanion.adapters").extend("gemini_cli", {
            env = {
              GEMINI_API_KEY = "cmd: gpg --decrypt ~/secrets/gemini_api_key.gpg 2>/dev/null",
            },
          })
        end,
      },
      http = {
        gemini = function()
          return require("codecompanion.adapters").extend("gemini", {
            env = {
              api_key = "cmd: gpg --decrypt ~/secrets/gemini_api_key.gpg 2>/dev/null",
            },
          })
        end,
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
    },
    strategies = {
      chat = {
        adapter = "gemini",
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
              i = "<C-x><C-\\>",
            },
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
        adapter = "gemini",
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
    prompt_library = prompts,
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
