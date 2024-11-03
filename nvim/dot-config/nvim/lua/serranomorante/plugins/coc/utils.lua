local promise = require("promise")
local async = require("async")

local M = {}

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
function M.coc_action_async(action, ...)
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

---@alias CocMethod "reference"|"definition"|"rename"|"hover"|"signature"|"inlayHint"|"codeAction"|"typeDefinition"|"implementation"|"documentSymbol"|"declaration"

---@class (exact) CocExtSupportsMethodOpt
---@field timeout? integer

---Check if LSP method is supported
---@param method CocMethod
---@param opts? CocExtSupportsMethodOpt
---@return Promise
function M.coc_ext_supports_method(method, opts)
  opts = vim.tbl_deep_extend("keep", opts or {}, {
    timeout = 500, -- it takes longer for some extensions
  })

  return async(function()
    await(require("ufo.utils").wait(opts.timeout))

    return M.coc_action_async("hasProvider", method):thenCall(function(result)
      if result == true then return promise.resolve(result) end
      return promise.reject(false)
    end, function() return promise.resolve(false) end)
  end)
end

---@class (exact) CocEnsureDocumentOpt
---@field timeout? integer

---Check coc document is attached
---@param opts? CocEnsureDocumentOpt
---@return Promise
function M.coc_ensure_document(opts)
  opts = vim.tbl_deep_extend("keep", opts or {}, {
    timeout = 1000, -- Between 1000 and 1500 is good for coc-marksman
  })

  return async(function()
    await(require("ufo.utils").wait(opts.timeout))

    return M.coc_action_async("ensureDocument"):thenCall(function(result)
      if result == true then return promise.resolve(result) end
      return promise.reject(false)
    end, function() return promise.reject(false) end)
  end)
end

return M
