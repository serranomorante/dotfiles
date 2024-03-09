local utils = require("serranomorante.utils")
local mock = require("luassert.mock")
local stub = require("luassert.stub")

describe("utils", function()
  describe("tools", function()
    ---@type table<string, ToolEnsureInstall>
    local by_filetype = {
      javascript = {
        ["lsp"] = { "lsp-1", "lsp-2" },
        ["formatters"] = { "formatter-1" },
      },
      python = {
        ["lsp"] = { "lsp-3", { "lsp-4", version = "v000" } },
        ["formatters"] = { "formatter-2" },
      },
      json = {
        ["formatters"] = { "formatter-1" },
      },
    }

    local map_to_lspconfig = {
      ["lsp-1"] = "lsp_1",
      ["lsp-4"] = "lsp_4",
    }

    it("can get a list of lsp tools", function()
      local lsp_tools = utils.get_from_tools(by_filetype, "lsp")
      local expected_tools = { "lsp-1", "lsp-2", "lsp-3", "lsp-4" }
      assert.are.same(#lsp_tools, #expected_tools)
      assert.True(vim.list_contains(lsp_tools, "lsp-1"))
      assert.True(vim.list_contains(lsp_tools, "lsp-2"))
      assert.True(vim.list_contains(lsp_tools, "lsp-3"))
      assert.True(vim.list_contains(lsp_tools, "lsp-4"))
    end)

    it("can get a list of lsp tools with nvim-lspconfig name mapping", function()
      local lsp_tools = utils.get_from_tools(by_filetype, "lsp", true, map_to_lspconfig)
      assert.are.same(4, #lsp_tools)
      assert.True(vim.list_contains(lsp_tools, "lsp_1"))
      assert.True(vim.list_contains(lsp_tools, "lsp_4"))
      assert.False(vim.list_contains(lsp_tools, "lsp-1"))
      assert.False(vim.list_contains(lsp_tools, "lsp-4"))
    end)

    it("can merge a list of tools (by filetype) without duplicates", function()
      local result = utils.merge_tools("mason", by_filetype.javascript, by_filetype.python, by_filetype.json)
      assert.are.same(6, #result) -- 7 in total but 6 without duplicates!
      assert.are.unique(result)
    end)
  end)
end)

describe("lazy load", function()
  it("plugin by filetype", function()
    local api = mock(vim.api, true)
    api.nvim_exec_autocmds.returns(nil)
    api.nvim_get_option_value.returns("javascript")

    utils.load_plugin_by_filetype("LSP", {
      delay = false,
    })

    assert
      .stub(api.nvim_exec_autocmds)
      .was_called_with("User", { pattern = "CustomLSPLoadJavascript", modeline = false })

    utils.load_plugin_by_filetype("DAP", {
      delay = false,
    })

    assert
      .stub(api.nvim_exec_autocmds)
      .was_called_with("User", { pattern = "CustomDAPLoadJavascript", modeline = false })

    mock.revert(api)
  end)
end)
