local M = {}

---Resolve the current agent session context for snippet variables.
---@return { AGENT_NAME?: string, CWD?: string, CHAT_ID?: string }
function M.current_agent_vars()
  local ok, agent_sessions = pcall(require, "serranomorante.plugins.jobs.agent_sessions")
  if not ok or type(agent_sessions.current_agent_context) ~= "function" then return {} end

  local context = agent_sessions.current_agent_context()
  if type(context) ~= "table" then return {} end

  local vars = {}
  if type(context.provider) == "string" and context.provider ~= "" then vars.AGENT_NAME = context.provider end
  if type(context.cwd) == "string" and context.cwd ~= "" then vars.CWD = context.cwd end
  if type(context.session_id) == "string" and context.session_id ~= "" then vars.CHAT_ID = context.session_id end
  return vars
end

---Paste a snippet directly by name, substituting {var:KEY} placeholders with
---the current agent session context plus any explicit var:KEY=VALUE overrides.
---@param name string
---@param extra_vars? string[] Explicit "var:KEY=VALUE" args to append.
---@return boolean
function M.paste(name, extra_vars)
  if type(name) ~= "string" or name == "" then
    vim.notify("snippets: missing snippet name", vim.log.levels.ERROR)
    return false
  end

  local args = { "snippets", name }
  for key, value in pairs(M.current_agent_vars()) do
    table.insert(args, ("var:%s=%s"):format(key, value))
  end
  if type(extra_vars) == "table" then
    for _, spec in ipairs(extra_vars) do
      table.insert(args, spec)
    end
  end

  vim.system(args, { detach = true }, function(result)
    if result.code ~= 0 then
      local message = vim.trim(result.stderr or result.stdout or "")
      vim.schedule(function() vim.notify("snippets: " .. name .. " failed: " .. message, vim.log.levels.ERROR) end)
    end
  end)
  return true
end

return M
