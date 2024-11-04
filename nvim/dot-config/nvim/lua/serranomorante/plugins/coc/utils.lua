local promise = require("promise")
local async = require("async")
local tools = require("serranomorante.tools")

local M = {}

---Check if buffer's filetype is compatible with any coc-extension
---@param bufnr integer
---@return boolean
function M.has_extension_available(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local has_extension = false
  local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })
  local filetype_tools = ((tools.by_filetype[filetype] or {}).extensions or {})
  for _, extension in ipairs(vim.g.coc_global_extensions or {}) do
    if has_extension == false then has_extension = vim.list_contains(filetype_tools, extension) end
  end
  return has_extension
end

---Rules to detect if we should enable coc for a buffer
---@param bufnr integer
---@return boolean
function M.should_enable(bufnr)
  local enable = false
  if M.has_extension_available(bufnr) then enable = true end
  if vim.api.nvim_get_option_value("diff", { scope = "local" }) then
    enable = false -- prevent conflict with diffview
  end
  if vim.list_contains({ "nowrite", "nofile" }, vim.api.nvim_get_option_value("buftype", { buf = bufnr })) then
    enable = false -- not a valid buftype
  end
  if vim.b[bufnr].coc_enabled == 1 then enable = false end -- already enabled
  return enable
end

---Check if coc is attached to buffer
---@param buf number?
function M.is_coc_attached(buf)
  local bufnr = buf or vim.api.nvim_get_current_buf()
  return vim.b[bufnr].coc_enabled == 1
end

---Execute `CocActionAsync` as a promise
---This uses `promise-async` plugin
---@param action string
---@vararg any
---@return Promise
function M.action_async(action, ...)
  local args = { ... }
  return promise(function(resolve, reject)
    table.insert(args, function(err, res)
      if err ~= vim.NIL then
        if type(err) == "string" and (err:match("service not started") or err:match("Plugin not ready")) then
          resolve()
        else
          reject(err)
        end
      else
        if res == vim.NIL then res = nil end
        resolve(res)
      end
    end)
    vim.fn.CocActionAsync(action, unpack(args))
  end)
end

---@alias CocProviderFeature
---|'"rename"'
---|'"onTypeEdit"'
---|'"documentLink"'
---|'"documentColor"'
---|'"foldingRange"'
---|'"format"'
---|'"codeAction"'
---|'"workspaceSymbols"'
---|'"formatRange"'
---|'"hover"'
---|'"signature"'
---|'"documentSymbol"'
---|'"documentHighlight"'
---|'"definition"'
---|'"declaration"'
---|'"typeDefinition"'
---|'"reference"'
---|'"implementation"'
---|'"codeLens"'
---|'"selectionRange"'
---|'"formatOnType"'
---|'"callHierarchy"'
---|'"semanticTokens"'
---|'"semanticTokensRange"'
---|'"linkedEditing"'
---|'"inlayHint"'
---|'"inlineValue"'
---|'"typeHierarchy"'

---Check if provider feature is supported
---@param method CocProviderFeature
---@return Promise
function M.supports_provider_feature(method) return M.action_async("hasProvider", method) end

---Check if there's any extension ready. This might take some time.
---@return Promise
function M.extension_ready()
  return async(function()
    local base_support = await(M.supports_provider_feature("hover"))
      or await(M.supports_provider_feature("reference"))
      or await(M.supports_provider_feature("definition"))
      or await(M.supports_provider_feature("semanticTokens"))

    return M.action_async("ensureDocument"):thenCall(function(result)
      if result == true and base_support == true then return promise.resolve(result) end
      return promise.resolve(false)
    end, function(err) return promise.reject(err) end)
  end)
end

return M
