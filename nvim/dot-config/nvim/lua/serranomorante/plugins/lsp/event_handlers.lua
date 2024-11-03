local keymapper = require("serranomorante.plugins.lsp.keymapper")
local augroups = require("serranomorante.plugins.lsp.augroups")
local ms = vim.lsp.protocol.Methods

---@alias HandlerData {augroup: integer, bufnr: integer, client: vim.lsp.Client}

---@class CapabilityHandler
---@field attach fun(data: HandlerData)
---@field detach fun(client_id: integer, bufnr: integer)

local M = {}

---Open quickfix list but don't focus
---@param options vim.lsp.LocationOpts.OnList
local function on_list(options)
  ---@diagnostic disable-next-line: param-type-mismatch
  vim.fn.setqflist({}, " ", options)
  require("quicker").open({ focus = false, open_cmd_mods = { split = "botright" } })
end

---@param client vim.lsp.Client
---@param bufnr integer
M.attach = function(client, bufnr)
  local fzf_lua = require("fzf-lua")
  local augroup = augroups.get_augroup(client)
  local opts_with_desc = keymapper.opts_for(bufnr)
  ---@type vim.lsp.LocationOpts
  local lsp_default_opts = { on_list = on_list }

  local function client_buf_supports_method(method) return client.supports_method(method, { bufnr = bufnr }) end

  local handler_data = {
    augroup = augroup,
    bufnr = bufnr,
    client = client,
  }

  if client_buf_supports_method(ms.textDocument_references) then
    vim.keymap.set(
      "n",
      "grr",
      function() vim.lsp.buf.references(nil, lsp_default_opts) end,
      opts_with_desc("Show references")
    )
  end

  if client_buf_supports_method(ms.textDocument_definition) then
    vim.keymap.set(
      "n",
      "gd",
      function() vim.lsp.buf.definition(lsp_default_opts) end,
      opts_with_desc("Show definitions")
    )
  end

  if client_buf_supports_method(ms.textDocument_implementation) then
    vim.keymap.set(
      "n",
      "gI",
      function() vim.lsp.buf.implementation(lsp_default_opts) end,
      opts_with_desc("Show implementations")
    )
  end

  if client_buf_supports_method(ms.textDocument_typeDefinition) then
    vim.keymap.set(
      "n",
      "gy",
      function() vim.lsp.buf.type_definition(lsp_default_opts) end,
      opts_with_desc("Show type definitions")
    )
  end

  if client_buf_supports_method(ms.textDocument_diagnostic) then
    vim.keymap.set(
      "n",
      "<leader>ld",
      function() fzf_lua.diagnostics_document() end,
      opts_with_desc("Show document diagnostics")
    )
  end

  if client_buf_supports_method(ms.workspace_diagnostic) then
    vim.keymap.set(
      "n",
      "<leader>lD",
      function() fzf_lua.diagnostics_workspace() end,
      opts_with_desc("Show workspace diagnostics")
    )
  end

  if client_buf_supports_method(ms.textDocument_documentSymbol) then
    vim.keymap.set("n", "<leader>ls", function() require("aerial").toggle() end, opts_with_desc("Document symbols"))
  end

  if client_buf_supports_method(ms.workspace_symbol) then
    vim.keymap.set(
      "n",
      "<leader>lS",
      function() vim.lsp.buf.workspace_symbol(nil, lsp_default_opts) end,
      opts_with_desc("Workspace symbols")
    )
  end

  if client_buf_supports_method(ms.textDocument_declaration) then
    vim.keymap.set(
      "n",
      "gD",
      function() vim.lsp.buf.declaration(lsp_default_opts) end,
      opts_with_desc("Go to declaration")
    )
  end

  vim.keymap.set(
    "n",
    "gl",
    function() vim.diagnostic.open_float({ scope = "line" }) end,
    opts_with_desc("Show line diagnostics")
  )

  vim.keymap.set("n", "<leader>rS", vim.diagnostic.reset, opts_with_desc("Reset diagnostics"))

  if client_buf_supports_method(ms.textDocument_completion) then
    local completion = require("serranomorante.plugins.lsp.completion")
    completion.enable(client, bufnr)

    if client_buf_supports_method(ms.completionItem_resolve) then
      completion.enable_completion_documentation(client, augroup, bufnr)
    end
  end

  if client_buf_supports_method(ms.textDocument_codeLens) then
    require("serranomorante.plugins.lsp.capability_handlers.codelens").attach(handler_data)
  end

  if client_buf_supports_method(ms.textDocument_inlayHint) then
    require("serranomorante.plugins.lsp.capability_handlers.inlayhints").attach(handler_data)
  end
end

---@param client vim.lsp.Client
---@param bufnr integer
M.detach = function(client, bufnr)
  local client_id = client.id
  augroups.del_autocmds_for_buf(client, bufnr)
  local function client_buf_supports_method(method) return client.supports_method(method, { bufnr = bufnr }) end

  if client_buf_supports_method(ms.textDocument_codeLens) then
    require("serranomorante.plugins.lsp.capability_handlers.codelens").detach(client_id, bufnr)
  end

  if client_buf_supports_method(ms.textDocument_inlayHint) then
    require("serranomorante.plugins.lsp.capability_handlers.inlayhints").detach(client_id, bufnr)
  end

  local clients = vim.lsp.get_clients({ bufnr = bufnr })
  ---don't remove if more than 1 client attached
  ---1 is allowed, since detach runs just before detaching from buffer
  if #clients <= 1 then keymapper.clear(bufnr) end
end

return M
