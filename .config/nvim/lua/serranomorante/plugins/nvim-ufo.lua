---Anything not here will use lsp->indent
---Seems like "lsp" offers better performance: https://github.com/kevinhwang91/nvim-ufo/issues/6#issuecomment-1172346709
---@type table<string, "treesitter" | "indent" | "">
local provider_by_filetype = {
  vim = "indent",
  python = "indent",
  git = "",
  nofile = "",
}

---https://github.com/kevinhwang91/nvim-ufo/blob/553d8a9c611caa9f020556d4a26b760698e5b81b/doc/example.lua#L34C1-L50C8
---@param bufnr number
---@diagnostic disable-next-line: undefined-doc-name
---@return Promise
local function customize_selector(bufnr)
  local function handleFallbackException(err, providerName)
    if type(err) == "string" and err:match("UfoFallbackException") then
      return require("ufo").getFolds(bufnr, providerName)
    else
      return require("promise").reject(err)
    end
  end

  return require("ufo").getFolds(bufnr, "lsp"):catch(function(err) return handleFallbackException(err, "indent") end)
end

return {
  "kevinhwang91/nvim-ufo",
  event = "User CustomFile",
  cmd = "UfoInspect",
  dependencies = "kevinhwang91/promise-async",
  keys = {
    {
      "zR",
      function() require("ufo").openAllFolds() end,
      desc = "Ufo: Open all folds",
    },
    {
      "zM",
      function() require("ufo").closeAllFolds() end,
      desc = "Ufo: Close all folds",
    },
    {
      "zr",
      function() require("ufo").openFoldsExceptKinds() end,
      desc = "Ufo: Open folds except kinds",
    },
    {
      "zm",
      function() require("ufo").closeFoldsWith() end,
      desc = "Ufo: Close folds with level",
    },
    {
      "zp",
      function() require("ufo").peekFoldedLinesUnderCursor() end,
      desc = "Ufo: Peek folded lines under cursor",
    },
  },
  opts = {
    preview = {
      win_config = {
        winblend = 0,
        winhighlight = "Normal:Folded",
      },
      mappings = {
        scrollB = "<C-b>",
        scrollF = "<C-f>",
        scrollU = "<C-u>",
        scrollD = "<C-d>",
      },
    },
    provider_selector = function(bufnr, filetype, buftype)
      if vim.b[bufnr].large_buf or filetype == "" or buftype == "nofile" then return provider_by_filetype["nofile"] end
      return provider_by_filetype[filetype] or customize_selector
    end,
  },
  config = function(_, opts) require("ufo").setup(opts) end,
}
