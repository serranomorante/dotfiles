local M = {}
local configured = false

---Seems like "lsp" offers better performance: https://github.com/kevinhwang91/nvim-ufo/issues/6#issuecomment-1172346709
---@type table<string, UfoProviderEnum|string>
local provider_by_filetype = {
  vim = "indent",
  python = "indent",
  html = "indent",
  git = "",
  nofile = "",
}

---https://github.com/kevinhwang91/nvim-ufo/blob/553d8a9c611caa9f020556d4a26b760698e5b81b/doc/example.lua#L34C1-L50C8
---@param bufnr number
---@return Promise
local function enhance_selector(bufnr)
  local ufo = require("ufo")
  ---@param err string
  ---@param provider_name UfoProviderEnum
  local function handle_fallback_exception(err, provider_name)
    if type(err) == "string" and err:match("UfoFallbackException") then
      return ufo.getFolds(bufnr, provider_name)
    else
      local ok, promise = pcall(require, "promise")
      if ok then return promise.reject(err) end
      return nil
    end
  end

  return ufo
    .getFolds(bufnr, "lsp")
    :catch(function(err) return handle_fallback_exception(err, "treesitter") end)
    :catch(function(err) return handle_fallback_exception(err, "indent") end)
    :catch(function(_) return nil end)
end

local function keys(ufo)
  vim.keymap.set("n", "zR", ufo.openAllFolds, { desc = "Ufo: Open all folds" })
  vim.keymap.set("n", "zM", ufo.closeAllFolds, { desc = "Ufo: Close all folds" })
  vim.keymap.set("n", "zr", ufo.openFoldsExceptKinds, { desc = "Ufo: Open folds except kinds" })
  vim.keymap.set("n", "zm", ufo.closeFoldsWith, { desc = "Ufo: Close folds with level" })
  vim.keymap.set("n", "zp", ufo.peekFoldedLinesUnderCursor, { desc = "Ufo: Peek folded lines under cursor" })
end

local function opts()
  ---@type UfoConfig
  return {
    open_fold_hl_timeout = 400,
    close_fold_kinds_for_ft = { default = {} },
    enable_get_fold_virt_text = false,
    override_foldtext = false,
    preview = {
      win_config = {
        winblend = 0,
      },
      mappings = {
        scrollB = "<C-b>",
        scrollF = "<C-f>",
        scrollU = "<C-u>",
        scrollD = "<C-d>",
        jumpTop = "gg",
        jumpBot = "G",
      },
    },
    provider_selector = function(bufnr, filetype, buftype)
      if vim.b[bufnr].large_buf or filetype == "" or buftype == "nofile" then return provider_by_filetype["nofile"] end
      return provider_by_filetype[filetype] or enhance_selector
    end,
  }
end

function M.config()
  if configured then return end

  local package_loaded = pcall(vim.cmd.packadd, "ufo")
  if not package_loaded then return end

  local ok, ufo = pcall(require, "ufo")
  if not ok then return end

  keys(ufo)
  ufo.setup(opts())
  configured = true
end

return M
