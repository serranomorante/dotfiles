local utils = require("serranomorante.utils")
local docs_debounce_ms = 250
local docs_timer = assert(vim.uv.new_timer(), "Cannot create timer")
local trigger_debounce_ms = 250
local trigger_timer = assert(vim.uv.new_timer(), "Cannot create timer")
---Some LSPs for some reason say they have completionItem_resolve capability
---but then throw errors when this is executed (I look at you gopls)
local documentation_is_enabled = true

local kinds = {
  Text = "󰉿",
  Method = "󰆧",
  Function = "󰊕",
  Constructor = "",
  Field = "󰜢",
  Variable = "󰀫",
  Class = "󰠱",
  Interface = "",
  Module = "",
  Property = "󰜢",
  Unit = "󰑭",
  Value = "󰎠",
  Enum = "",
  Keyword = "󰌋",
  Snippet = "",
  Color = "󰏘",
  File = "󰈙",
  Reference = "󰈇",
  Folder = "󰉋",
  EnumMember = "",
  Constant = "󰏿",
  Struct = "󰙅",
  Event = "",
  Operator = "󰆕",
  TypeParameter = "",
}

local initialized = false
local function initialize_once()
  if initialized then return end
  for i, v in ipairs(vim.lsp.protocol.CompletionItemKind) do
    vim.lsp.protocol.CompletionItemKind[i] = kinds[v]
  end
  initialized = true
end

---@return boolean
local function pumvisible() return tonumber(vim.fn.pumvisible()) ~= 0 end

---@param docs string
---@param client vim.lsp.Client
---@return string
local function format_docs(docs, client) return docs .. "\n\n_source: " .. client.name .. "_" end

local M = {}

---@param client vim.lsp.Client
---@param bufnr integer
function M.enable(client, bufnr)
  local keymapper = require("serranomorante.plugins.lsp.keymapper")
  local opts_with_desc = keymapper.opts_for(bufnr)

  initialize_once()
  vim.lsp.completion.enable(true, client.id, bufnr, { autotrigger = true })

  ---Completion is triggered only on inserting new characters,
  ---if we delete char to adjust the match, popup disappears
  ---this solves it
  for _, keys in ipairs({ "<BS>", "<C-h>", "<C-w>" }) do
    vim.keymap.set("i", keys, function()
      if pumvisible() then
        trigger_timer:stop()
        utils.feedkeys(keys)
        trigger_timer:start(trigger_debounce_ms, 0, vim.schedule_wrap(vim.lsp.completion.trigger))
        return
      end
      utils.feedkeys(keys)
    end, opts_with_desc("Feed '" .. keys .. "' and trigger LSP completion if needed"))
  end

  ---Trigger LSP completion.
  ---If there's none, fallback to vanilla omnifunc.
  ---if there's none, use buffer completion
  vim.keymap.set("i", "<C-Space>", function()
    if next(vim.lsp.get_clients({ bufnr = bufnr, id = client.id })) then
      if vim.lsp.completion.trigger then vim.lsp.completion.trigger() end
    else
      if vim.bo.omnifunc == "" then
        utils.feedkeys("<C-x><C-n>")
      else
        utils.feedkeys("<C-x><C-o>")
      end
    end
  end, opts_with_desc("Smart completion trigger"))
end

---@param client vim.lsp.Client
---@param augroup integer
---@param bufnr integer
function M.enable_completion_documentation(client, augroup, bufnr)
  vim.api.nvim_create_autocmd("CompleteChanged", {
    group = augroup,
    buffer = bufnr,
    callback = function()
      if not documentation_is_enabled then return end

      docs_timer:stop()

      local client_id = vim.tbl_get(vim.v.completed_item, "user_data", "nvim", "lsp", "client_id")
      if client_id ~= client.id then return end

      local completion_item = vim.tbl_get(vim.v.completed_item, "user_data", "nvim", "lsp", "completion_item")
      if not completion_item then return end

      local complete_info = vim.fn.complete_info({ "selected" })
      if vim.tbl_isempty(complete_info) then return end

      docs_timer:start(
        docs_debounce_ms,
        0,
        vim.schedule_wrap(function()
          client:request(
            vim.lsp.protocol.Methods.completionItem_resolve,
            completion_item,
            ---@param err lsp.ResponseError
            ---@param result any
            function(err, result)
              if err ~= nil then
                vim.notify(
                  "Error from client " .. client.id .. " when getting documentation\n" .. vim.inspect(err),
                  vim.log.levels.WARN
                )
                ---at this stage just disable it
                documentation_is_enabled = false
                return
              end

              local docs = vim.tbl_get(result, "documentation", "value")
              if not docs then return end

              local wininfo = vim.api.nvim__complete_set(complete_info.selected, { info = format_docs(docs, client) })
              if vim.tbl_isempty(wininfo) or not vim.api.nvim_win_is_valid(wininfo.winid) then return end

              vim.api.nvim_win_set_config(wininfo.winid, { border = "rounded" })

              if not vim.api.nvim_buf_is_valid(wininfo.bufnr) then return end

              vim.bo[wininfo.bufnr].syntax = "markdown"
              vim.treesitter.start(wininfo.bufnr, "markdown")
            end,
            bufnr
          )
        end)
      )
    end,
  })
end

return M
