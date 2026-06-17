-- ============================================================================
-- claude_agents — orquestación de tasks de agentes hermanas bajo este Neovim
--
-- Permite a UNA task de overseer (p.ej. un Claude "orquestador") inspeccionar y
-- pilotar OTRAS tasks de agente (Claude/Codex) que corren en terminales bajo el
-- MISMO socket de Neovim: leer su output, enviarles input y consultar su estado.
--
-- Las funciones públicas devuelven STRING (texto plano o JSON) a propósito, para
-- ser llamadas vía RPC sin UI desde fuera del editor:
--   nvim --server "$NVIM" --remote-expr \
--     "luaeval(\"require('serranomorante.plugins.jobs.claude_agents').list_json()\")"
-- El wrapper de shell ~/dotfiles/utilities/bin/claude-agents envuelve esto.
--
-- Las claves de metadata (agent_provider / agent_session_id) las fija
-- agent_sessions.lua al crear/enlazar cada task; aquí se leen tal cual.
-- ============================================================================

local M = {}

-- Mantener en sync con agent_sessions.lua (AGENT_PROVIDER_METADATA / AGENT_SESSION_ID_METADATA).
local PROVIDER_KEY = "agent_provider"
local SESSION_ID_KEY = "agent_session_id"

local DEFAULT_READ_LINES = 80

---@return overseer.Task[]
local function list_tasks()
  local ok, overseer = pcall(require, "overseer")
  if not ok then return {} end
  local lok, tasks = pcall(overseer.list_tasks)
  if not lok or type(tasks) ~= "table" then return {} end
  return tasks
end

---@param t overseer.Task
---@return string?
local function task_provider(t)
  local md = t.metadata or {}
  return md[PROVIDER_KEY]
end

---@param t overseer.Task
---@return string?
local function task_session_id(t)
  local md = t.metadata or {}
  return md[SESSION_ID_KEY]
end

---@param t overseer.Task
---@return integer?
local function task_job_id(t)
  ---@diagnostic disable-next-line: invisible
  local strategy = t.strategy
  return t.job_id or (strategy and strategy.job_id) or nil
end

---@param t overseer.Task
---@return string[]?
local function task_buffer_lines(t)
  local ok, bufnr = pcall(function() return t:get_bufnr() end)
  if not ok or not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return nil end
  return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

---Best-effort estado de un agente leyendo el tail del terminal. Heurística:
---  - "busy"  si aparece el marcador de trabajo en curso ("esc to interrupt").
---  - "idle"  si hay un prompt de entrada (❯) y no está busy.
---  - "unknown" en otro caso.
---@param lines string[]?
---@return string
local function detect_state(lines)
  if type(lines) ~= "table" or #lines == 0 then return "unknown" end
  local from = math.max(1, #lines - 25)
  local tail = table.concat(vim.list_slice(lines, from, #lines), "\n")
  if tail:find("esc to interrupt", 1, true) then return "busy" end
  if tail:find("❯", 1, true) then return "idle" end
  return "unknown"
end

---Resuelve una task por: session-id exacto > id numérico de overseer >
---prefijo único de session-id > substring único de nombre (case-insensitive).
---@param ref string
---@return overseer.Task? task
---@return string? err
local function resolve_task(ref)
  if type(ref) ~= "string" or ref == "" then return nil, "missing task ref" end
  local tasks = list_tasks()

  for _, t in ipairs(tasks) do
    if task_session_id(t) == ref then return t end
  end

  if ref:match("^%d+$") then
    for _, t in ipairs(tasks) do
      if tostring(t.id) == ref then return t end
    end
  end

  local prefix = {}
  for _, t in ipairs(tasks) do
    local sid = task_session_id(t)
    if sid and sid:sub(1, #ref) == ref then table.insert(prefix, t) end
  end
  if #prefix == 1 then return prefix[1] end
  if #prefix > 1 then return nil, ("ambiguous ref '%s' matches %d session ids"):format(ref, #prefix) end

  local low = ref:lower()
  local named = {}
  for _, t in ipairs(tasks) do
    if type(t.name) == "string" and t.name:lower():find(low, 1, true) then table.insert(named, t) end
  end
  if #named == 1 then return named[1] end
  if #named > 1 then return nil, ("ambiguous ref '%s' matches %d task names"):format(ref, #named) end

  return nil, ("no task matches '%s'"):format(ref)
end

---@param t overseer.Task
---@return table
local function task_summary(t)
  local lines = task_buffer_lines(t)
  return {
    id = t.id,
    status = tostring(t.status),
    provider = task_provider(t),
    session_id = task_session_id(t),
    name = t.name,
    state = detect_state(lines),
  }
end

-- ---------------------------------------------------------------------------
-- API pública (devuelven string para uso vía --remote-expr/luaeval)
-- ---------------------------------------------------------------------------

---JSON con el roster de tasks de agente y su estado.
---@return string
function M.list_json()
  local tasks = {}
  for _, t in ipairs(list_tasks()) do
    table.insert(tasks, task_summary(t))
  end
  return vim.json.encode({ version = 1, count = #tasks, tasks = tasks })
end

---Tail del buffer de terminal de una task. Cabecera con id/estado + N últimas líneas.
---@param ref string
---@param n? integer|string
---@return string
function M.read(ref, n)
  local t, err = resolve_task(ref)
  if not t then return "ERROR: " .. tostring(err) end
  n = tonumber(n) or DEFAULT_READ_LINES
  local lines = task_buffer_lines(t)
  if not lines then return "ERROR: task has no valid terminal buffer" end
  while #lines > 0 and lines[#lines]:match("^%s*$") do
    table.remove(lines)
  end
  local total = #lines
  local start = math.max(1, total - n + 1)
  local header = ("# task id=%s session=%s provider=%s state=%s status=%s\n# lines %d-%d of %d"):format(
    tostring(t.id),
    tostring(task_session_id(t)),
    tostring(task_provider(t)),
    detect_state(lines),
    tostring(t.status),
    start,
    total,
    total
  )
  return header .. "\n" .. table.concat(vim.list_slice(lines, start, total), "\n")
end

---Inyecta texto en el input de una task de agente vía nvim_chan_send.
---IMPORTANTE: `with_newline` envía un '\r' = SALTO DE LÍNEA en la caja de
---entrada, NO un submit. El envío real lo decide quien orquesta, aparte.
---@param ref string
---@param b64_text string base64 del texto (evita problemas de quoting vía RPC)
---@param with_newline? boolean|string|integer
---@return string json
function M.send(ref, b64_text, with_newline)
  local t, err = resolve_task(ref)
  if not t then return vim.json.encode({ ok = false, error = err }) end
  local job = task_job_id(t)
  if not job then return vim.json.encode({ ok = false, error = "task has no job/channel id" }) end

  local text = ""
  if type(b64_text) == "string" and b64_text ~= "" then
    if type(vim.base64) ~= "table" then
      return vim.json.encode({ ok = false, error = "vim.base64 unavailable (needs Neovim >= 0.10)" })
    end
    local dok, decoded = pcall(vim.base64.decode, b64_text)
    if not dok then return vim.json.encode({ ok = false, error = "invalid base64 payload" }) end
    text = decoded
  end

  local ok_text = pcall(vim.api.nvim_chan_send, job, text)
  local newline = with_newline == true or with_newline == "true" or with_newline == "1" or with_newline == 1
  if newline then pcall(vim.api.nvim_chan_send, job, "\r") end

  return vim.json.encode({
    ok = ok_text,
    id = t.id,
    session_id = task_session_id(t),
    job = job,
    bytes = #text,
    newline = newline,
  })
end

---Estado de una task (si se pasa ref) o el roster completo.
---@param ref? string
---@return string json
function M.status(ref)
  if type(ref) == "string" and ref ~= "" then
    local t, err = resolve_task(ref)
    if not t then return vim.json.encode({ ok = false, error = err }) end
    local summary = task_summary(t)
    summary.ok = true
    return vim.json.encode(summary)
  end
  return M.list_json()
end

---Resuelve el binario `agent-session-store` igual que agent_sessions.lua:
---$AGENT_SESSION_STORE_BIN > ~/dotfiles/utilities/bin/agent-session-store > PATH.
---@return string?
local function store_bin()
  local env = vim.env.AGENT_SESSION_STORE_BIN
  if env and env ~= "" and vim.fn.executable(env) == 1 then return env end
  local repo = vim.fn.expand("~/dotfiles/utilities/bin/agent-session-store")
  if vim.fn.executable(repo) == 1 then return repo end
  if vim.fn.executable("agent-session-store") == 1 then return "agent-session-store" end
  return nil
end

-- Roots por provider (en sync con PROVIDERS de agent_sessions.lua).
local STORE_PROVIDERS = {
  { name = "claude", root = vim.fn.expand("~/.claude/projects") },
  { name = "codex", root = vim.fn.expand("~/.codex/sessions") },
}

---Ids de sesión conocidos por el store, scoped al cwd actual (a través de
---todos los providers). Síncrono (`ids` es rápido). Devuelve `nil` si el store
---no está disponible — el caller lo trata como "no he podido validar".
---@return string[]?
local function known_session_ids()
  local bin = store_bin()
  if not bin then return nil end
  local cwd = vim.fn.getcwd()
  local ids, seen, any_ok = {}, {}, false
  for _, p in ipairs(STORE_PROVIDERS) do
    local out = vim.fn.system({ bin, "--provider", p.name, "--root", p.root, "ids", cwd })
    if vim.v.shell_error == 0 and out ~= "" then
      local ok, decoded = pcall(vim.json.decode, out)
      if ok and type(decoded) == "table" and type(decoded.ids) == "table" then
        any_ok = true
        for _, id in ipairs(decoded.ids) do
          if type(id) == "string" and not seen[id] then
            seen[id] = true
            table.insert(ids, id)
          end
        end
      end
    end
  end
  if not any_ok then return nil end
  return ids
end

---Resuelve `ref` (UUID completo o prefijo único) al UUID completo conocido.
---@param ref string
---@param known string[]
---@return string? full_id
---@return string? err  -- "ambiguous" | "not_found"
local function resolve_session_ref(ref, known)
  for _, id in ipairs(known) do
    if id == ref then return id end
  end
  local matches = {}
  for _, id in ipairs(known) do
    if id:sub(1, #ref) == ref then table.insert(matches, id) end
  end
  if #matches == 1 then return matches[1] end
  if #matches > 1 then return nil, "ambiguous" end
  return nil, "not_found"
end

---Abre una o varias sesiones EXISTENTES como tasks de overseer, por id.
---Reusa el comando AgentResumeById (misma vía que `open_in_nvim agent_conversation
---<id>`): resuelve la sesión en el store de agentes (Claude o Codex) y, si ya está
---corriendo, ENFOCA la task existente en vez de duplicarla; si no, la crea con
---`<provider> --resume <id>`. `ids` = lista separada por comas o espacios.
---
---VALIDA cada id contra el store ANTES de programar el resume: acepta UUID
---completo o prefijo único (lo resuelve al UUID completo, que es lo que
---AgentResumeById exige para su lookup exacto). Los ids que no existen / son
---ambiguos NO se abren y se devuelven en `not_found` / `ambiguous` con `ok:false`,
---en vez de fallar en silencio (AgentResumeField notifica "Agent session not
---found" pero por debajo de un pcall que se tragaba el error).
---@param ids string
---@return string json
function M.open(ids)
  local requested, opened, not_found, ambiguous = {}, {}, {}, {}
  local known = known_session_ids()

  for id in tostring(ids):gmatch("[^,%s]+") do
    table.insert(requested, id)
    if known == nil then
      -- Store no disponible: no puedo validar; abro best-effort y lo marco.
      local target = id
      vim.schedule(function() pcall(vim.cmd, "AgentResumeById " .. target) end)
      table.insert(opened, id)
    else
      local full, err = resolve_session_ref(id, known)
      if full then
        table.insert(opened, full)
        -- AgentResumeById hace gestión de ventana sobre la ventana actual; lo
        -- programamos para no correrlo en el contexto RPC/fast.
        vim.schedule(function() pcall(vim.cmd, "AgentResumeById " .. full) end)
      elseif err == "ambiguous" then
        table.insert(ambiguous, id)
      else
        table.insert(not_found, id)
      end
    end
  end

  if #requested == 0 then return vim.json.encode({ ok = false, error = "no session ids given" }) end

  local ok = (#not_found == 0 and #ambiguous == 0)
  local result = { ok = ok, requested = requested, opened = opened }
  if #not_found > 0 then result.not_found = not_found end
  if #ambiguous > 0 then result.ambiguous = ambiguous end
  if known == nil then result.warning = "session store unavailable; ids not validated" end
  if not ok then
    result.error = ("could not resolve %d of %d id(s)"):format(#not_found + #ambiguous, #requested)
  end
  return vim.json.encode(result)
end

---Abre una sesión Claude NUEVA como task de overseer, reusando
---`agent_sessions.open_new("claude")` (la misma vía que el keymap `<leader>an`):
---preasigna session-id, crea la task `claude --session-id <uuid>`, abre su output
---y la enlaza. NO duplica esa lógica.
---
---Si se pasa `b64_prompt`, espera (best-effort) a que la nueva task esté lista
---(detect_state == "idle") e inyecta el prompt como bracketed-paste + un `\r`
---discreto para DESPACHARLO (la tarea X que debe hacer el nuevo agente hijo).
---@param b64_prompt? string base64 del prompt inicial (opcional)
---@return string json
function M.new(b64_prompt)
  local ok_as, agent_sessions = pcall(require, "serranomorante.plugins.jobs.agent_sessions")
  if not ok_as or type(agent_sessions.open_new) ~= "function" then
    return vim.json.encode({ ok = false, error = "agent_sessions.open_new no disponible" })
  end

  -- Snapshot de session-ids previos para identificar la task recién creada.
  local before = {}
  for _, t in ipairs(list_tasks()) do
    local sid = task_session_id(t)
    if sid then before[sid] = true end
  end

  local prompt
  if type(b64_prompt) == "string" and b64_prompt ~= "" and type(vim.base64) == "table" then
    local dok, decoded = pcall(vim.base64.decode, b64_prompt)
    if dok then prompt = decoded end
  end

  -- Spawn por la vía existente (no en contexto RPC/fast). open_new añade su prompt
  -- de contexto (la línea "continuando con esta conversación de claude con id: …")
  -- que enlaza al hijo con la conversación activa — se conserva a propósito. La
  -- tarea real la añade el glue de abajo (paste) y la despacha con el \r.
  vim.schedule(function() agent_sessions.open_new("claude") end)

  -- Si hay prompt, localizar la task nueva cuando aparezca + esté lista, e inyectar.
  if prompt then
    local tries = 0
    local function find_new()
      for _, t in ipairs(list_tasks()) do
        local sid = task_session_id(t)
        if sid and not before[sid] and task_provider(t) == "claude" then return t end
      end
    end
    local function step()
      tries = tries + 1
      local t = find_new()
      local job = t and task_job_id(t)
      local ready = t and detect_state(task_buffer_lines(t)) == "idle"
      if t and job and ready then
        pcall(vim.api.nvim_chan_send, job, "\27[200~" .. prompt .. "\27[201~")
        -- \r discreto, separado de la paste, para que el TUI lo tome como submit.
        vim.defer_fn(function() pcall(vim.api.nvim_chan_send, job, "\r") end, 400)
      elseif tries < 60 then
        vim.defer_fn(step, 500)
      end
    end
    vim.defer_fn(step, 1000)
  end

  return vim.json.encode({ ok = true, spawning = true, with_prompt = prompt ~= nil })
end

-- ---------------------------------------------------------------------------
-- Ex commands (capa humana — el orquestador usa el wrapper claude-agents)
-- ---------------------------------------------------------------------------

function M.setup_commands()
  vim.api.nvim_create_user_command("ClaudeAgents", function()
    local data = vim.json.decode(M.list_json())
    local lines = { ("Agent tasks (%d):"):format(data.count) }
    for _, t in ipairs(data.tasks) do
      table.insert(
        lines,
        ("  [%s] %-7s %-7s %-9s %s"):format(
          tostring(t.id),
          t.state or "?",
          t.provider or "-",
          (t.session_id or "-"):sub(1, 8),
          t.name or ""
        )
      )
    end
    vim.api.nvim_echo({ { table.concat(lines, "\n") } }, false, {})
  end, { desc = "Claude: list sibling agent tasks + state" })

  vim.api.nvim_create_user_command(
    "ClaudeAgentRead",
    function(a) vim.api.nvim_echo({ { M.read(a.fargs[1], a.fargs[2]) } }, false, {}) end,
    { nargs = "+", desc = "Claude: read tail of an agent task buffer (<ref> [lines])" }
  )

  vim.api.nvim_create_user_command("ClaudeAgentSend", function(a)
    local ref = a.fargs[1]
    local text = table.concat(vim.list_slice(a.fargs, 2, #a.fargs), " ")
    local b64 = vim.base64.encode(text)
    vim.api.nvim_echo({ { M.send(ref, b64, false) } }, false, {})
  end, { nargs = "+", desc = "Claude: type text into an agent task input, no submit (<ref> <text...>)" })

  vim.api.nvim_create_user_command(
    "ClaudeAgentOpen",
    function(a) vim.api.nvim_echo({ { M.open(table.concat(a.fargs, ",")) } }, false, {}) end,
    { nargs = "+", desc = "Claude: open existing agent session(s) as overseer task(s) by id" }
  )

  vim.api.nvim_create_user_command("ClaudeAgentNew", function(a)
    local prompt = table.concat(a.fargs, " ")
    local b64 = prompt ~= "" and vim.base64.encode(prompt) or ""
    vim.api.nvim_echo({ { M.new(b64) } }, false, {})
  end, { nargs = "*", desc = "Claude: spawn a NEW Claude session as an overseer task ([task to run])" })
end

return M
