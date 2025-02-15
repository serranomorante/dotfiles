---This plugin is loaded by the following overseer task: overseer/template/editor-tasks/TASK__decrypt_gpg_load_plugin.lua:3
---Read more: https://github.com/serranomorante/.dotfiles/commit/fec9579bc10538b1ee88e81d7ffb81f522405dfe

local M = {}

local function opts_with_desc(desc)
  return {
    noremap = true,
    silent = true,
    nowait = true,
    desc = "GPT: " .. desc,
  }
end

local function keys()
  ---Chat commands
  vim.keymap.set({ "n", "i" }, "<C-g>c", "<cmd>GpChatNew<cr>", opts_with_desc("New Chat"))
  vim.keymap.set({ "n", "i" }, "<C-g>t", "<cmd>GpChatToggle<cr>", opts_with_desc("Toggle Chat"))

  vim.keymap.set("v", "<C-g>c", ":<C-u>'<,'>GpChatNew<cr>", opts_with_desc("Visual Chat New"))
  vim.keymap.set("v", "<C-g>p", ":<C-u>'<,'>GpChatPaste<cr>", opts_with_desc("Visual Chat Paste"))
  vim.keymap.set("v", "<C-g>t", ":<C-u>'<,'>GpChatToggle<cr>", opts_with_desc("Visual Toggle Chat"))

  vim.keymap.set({ "n", "i" }, "<C-g><C-x>", "<cmd>GpChatNew split<cr>", opts_with_desc("New Chat split"))
  vim.keymap.set({ "n", "i" }, "<C-g><C-v>", "<cmd>GpChatNew vsplit<cr>", opts_with_desc("New Chat vsplit"))
  vim.keymap.set({ "n", "i" }, "<C-g><C-t>", "<cmd>GpChatNew tabnew<cr>", opts_with_desc("New Chat tabnew"))

  vim.keymap.set("v", "<C-g><C-x>", ":<C-u>'<,'>GpChatNew split<cr>", opts_with_desc("Visual Chat New split"))
  vim.keymap.set("v", "<C-g><C-v>", ":<C-u>'<,'>GpChatNew vsplit<cr>", opts_with_desc("Visual Chat New vsplit"))
  vim.keymap.set("v", "<C-g><C-t>", ":<C-u>'<,'>GpChatNew tabnew<cr>", opts_with_desc("Visual Chat New tabnew"))

  ---Prompt commands
  vim.keymap.set({ "n", "i" }, "<C-g>r", "<cmd>GpRewrite<cr>", opts_with_desc("Inline Rewrite"))
  vim.keymap.set({ "n", "i" }, "<C-g>a", "<cmd>GpAppend<cr>", opts_with_desc("Append (after)"))
  vim.keymap.set({ "n", "i" }, "<C-g>b", "<cmd>GpPrepend<cr>", opts_with_desc("Prepend (before)"))

  vim.keymap.set("v", "<C-g>r", ":<C-u>'<,'>GpRewrite<cr>", opts_with_desc("Visual Rewrite"))
  vim.keymap.set("v", "<C-g>a", ":<C-u>'<,'>GpAppend<cr>", opts_with_desc("Visual Append (after)"))
  vim.keymap.set("v", "<C-g>b", ":<C-u>'<,'>GpPrepend<cr>", opts_with_desc("Visual Prepend (before)"))
  vim.keymap.set("v", "<C-g>i", ":<C-u>'<,'>GpImplement<cr>", opts_with_desc("Implement selection"))

  vim.keymap.set({ "n", "i" }, "<C-g>gp", "<cmd>GpPopup<cr>", opts_with_desc("Popup"))
  vim.keymap.set({ "n", "i" }, "<C-g>ge", "<cmd>GpEnew<cr>", opts_with_desc("GpEnew"))
  vim.keymap.set({ "n", "i" }, "<C-g>gn", "<cmd>GpNew<cr>", opts_with_desc("GpNew"))
  vim.keymap.set({ "n", "i" }, "<C-g>gv", "<cmd>GpVnew<cr>", opts_with_desc("GpVnew"))
  vim.keymap.set({ "n", "i" }, "<C-g>gt", "<cmd>GpTabnew<cr>", opts_with_desc("GpTabnew"))

  vim.keymap.set("v", "<C-g>gp", ":<C-u>'<,'>GpPopup<cr>", opts_with_desc("Visual Popup"))
  vim.keymap.set("v", "<C-g>ge", ":<C-u>'<,'>GpEnew<cr>", opts_with_desc("Visual GpEnew"))
  vim.keymap.set("v", "<C-g>gn", ":<C-u>'<,'>GpNew<cr>", opts_with_desc("Visual GpNew"))
  vim.keymap.set("v", "<C-g>gv", ":<C-u>'<,'>GpVnew<cr>", opts_with_desc("Visual GpVnew"))
  vim.keymap.set("v", "<C-g>gt", ":<C-u>'<,'>GpTabnew<cr>", opts_with_desc("Visual GpTabnew"))

  vim.keymap.set({ "n", "i" }, "<C-g>x", "<cmd>GpContext<cr>", opts_with_desc("Toggle Context"))
  vim.keymap.set("v", "<C-g>x", ":<C-u>'<,'>GpContext<cr>", opts_with_desc("Visual Toggle Context"))

  vim.keymap.set({ "n", "i", "v", "x" }, "<C-g>s", "<cmd>GpStop<cr>", opts_with_desc("Stop"))
  vim.keymap.set({ "n", "i", "v", "x" }, "<C-g>n", "<cmd>GpNextAgent<cr>", opts_with_desc("Next Agent"))

  ---Optional Whisper commands with prefix <C-g>w
  vim.keymap.set({ "n", "i" }, "<C-g>ww", "<cmd>GpWhisper<cr>", opts_with_desc("Whisper"))
  vim.keymap.set("v", "<C-g>ww", ":<C-u>'<,'>GpWhisper<cr>", opts_with_desc("Visual Whisper"))

  vim.keymap.set({ "n", "i" }, "<C-g>wr", "<cmd>GpWhisperRewrite<cr>", opts_with_desc("Whisper Inline Rewrite"))
  vim.keymap.set({ "n", "i" }, "<C-g>wa", "<cmd>GpWhisperAppend<cr>", opts_with_desc("Whisper Append (after)"))
  vim.keymap.set({ "n", "i" }, "<C-g>wb", "<cmd>GpWhisperPrepend<cr>", opts_with_desc("Whisper Prepend (before) "))

  vim.keymap.set("v", "<C-g>wr", ":<C-u>'<,'>GpWhisperRewrite<cr>", opts_with_desc("Visual Whisper Rewrite"))
  vim.keymap.set("v", "<C-g>wa", ":<C-u>'<,'>GpWhisperAppend<cr>", opts_with_desc("Visual Whisper Append (after)"))
  vim.keymap.set("v", "<C-g>wb", ":<C-u>'<,'>GpWhisperPrepend<cr>", opts_with_desc("Visual Whisper Prepend (before)"))

  vim.keymap.set({ "n", "i" }, "<C-g>wp", "<cmd>GpWhisperPopup<cr>", opts_with_desc("Whisper Popup"))
  vim.keymap.set({ "n", "i" }, "<C-g>we", "<cmd>GpWhisperEnew<cr>", opts_with_desc("Whisper Enew"))
  vim.keymap.set({ "n", "i" }, "<C-g>wn", "<cmd>GpWhisperNew<cr>", opts_with_desc("Whisper New"))
  vim.keymap.set({ "n", "i" }, "<C-g>wv", "<cmd>GpWhisperVnew<cr>", opts_with_desc("Whisper Vnew"))
  vim.keymap.set({ "n", "i" }, "<C-g>wt", "<cmd>GpWhisperTabnew<cr>", opts_with_desc("Whisper Tabnew"))

  vim.keymap.set("v", "<C-g>wp", ":<C-u>'<,'>GpWhisperPopup<cr>", opts_with_desc("Visual Whisper Popup"))
  vim.keymap.set("v", "<C-g>we", ":<C-u>'<,'>GpWhisperEnew<cr>", opts_with_desc("Visual Whisper Enew"))
  vim.keymap.set("v", "<C-g>wn", ":<C-u>'<,'>GpWhisperNew<cr>", opts_with_desc("Visual Whisper New"))
  vim.keymap.set("v", "<C-g>wv", ":<C-u>'<,'>GpWhisperVnew<cr>", opts_with_desc("Visual Whisper Vnew"))
  vim.keymap.set("v", "<C-g>wt", ":<C-u>'<,'>GpWhisperTabnew<cr>", opts_with_desc("Visual Whisper Tabnew"))
end

local AGENTS_ENUM = {
  ChatGPT4o = "ChatGPT4o",
  ChatGPT4o_mini = "ChatGPT4o-mini",
  CodeGPT4o = "CodeGPT4o",
  CodeGPT4o_mini = "CodeGPT4o-mini",
}

---@return GpConfig
local function base_opts()
  return {
    chat_conceal_model_params = false,
    default_command_agent = AGENTS_ENUM.CodeGPT4o,
    default_chat_agent = AGENTS_ENUM.ChatGPT4o,
    hooks = {
      ---@param gp Gp
      ---@param params table
      CodeReview = function(gp, params)
        local template = "I have the following code from {{filename}}:\n\n"
          .. "```{{filetype}}\n{{selection}}\n```\n\n"
          .. "Please analyze for code smells and suggest improvements."
        local agent = gp.get_chat_agent()
        gp.Prompt(params, gp.Target.enew("markdown"), agent, template)
      end,
      ---@param gp Gp
      ---@param params table
      Explain = function(gp, params)
        local template = "I have the following code from {{filename}}:\n\n"
          .. "```{{filetype}}\n{{selection}}\n```\n\n"
          .. "Please respond by explaining the code above."
        local agent = gp.get_chat_agent()
        gp.Prompt(params, gp.Target.enew("markdown"), agent, template)
      end,
    },
  }
end

---@param _ any reserved
---@param opts GpConfig
function M.config(_, opts)
  keys()
  require("gp").setup(vim.tbl_deep_extend("force", base_opts(), opts))
end

return M
