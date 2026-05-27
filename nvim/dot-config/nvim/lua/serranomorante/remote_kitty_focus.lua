local M = {}

local focus_deadline = 0
local focus_running = false
local focus_window_ms = 1500

local function now_ms() return (vim.uv or vim.loop).hrtime() / 1000000 end

local function nvim_servername_from_kitty_listen_on()
  local listen_on = vim.env.KITTY_LISTEN_ON or ""
  local socket = listen_on:match("^unix:(/.+)$")
  if socket == nil then return nil end

  if socket:sub(-5) == ".sock" then return socket:sub(1, -6) .. ".nvim.sock" end
  return socket .. ".nvim.sock"
end

local function enabled()
  return vim.env.KITTY_WINDOW_ID ~= nil
    and vim.env.KITTY_WINDOW_ID ~= ""
    and vim.v.servername ~= ""
    and nvim_servername_from_kitty_listen_on() == vim.v.servername
end

local function kitty_window_is_focused(kitty_state)
  local target_id = tonumber(vim.env.KITTY_WINDOW_ID)
  if target_id == nil then return false end

  for _, os_window in ipairs(kitty_state or {}) do
    for _, tab in ipairs(os_window.tabs or {}) do
      for _, window in ipairs(tab.windows or {}) do
        if window.id == target_id then
          return os_window.is_focused == true and tab.is_active == true and window.is_active == true
        end
      end
    end
  end

  return false
end

local function focus_current_window()
  if not enabled() or focus_running or vim.fn.executable("kitten") ~= 1 then return end

  if not vim.system then
    vim.fn.jobstart({ "kitten", "@", "focus-window", "--match", "id:" .. vim.env.KITTY_WINDOW_ID }, { detach = true })
    return
  end

  focus_running = true
  vim.system({ "kitten", "@", "ls", "--match", "state:focused_os_window" }, { text = true }, function(result)
    vim.schedule(function()
      focus_running = false
      if result.code ~= 0 then return end

      local ok, kitty_state = pcall(vim.json.decode, result.stdout or "")
      if ok and kitty_window_is_focused(kitty_state) then return end

      vim.system(
        { "kitten", "@", "focus-window", "--match", "id:" .. vim.env.KITTY_WINDOW_ID },
        { text = true },
        function() end
      )
    end)
  end)
end

M.focus_current_window = focus_current_window

local function note_remote_rpc()
  if not enabled() then return end

  local info = vim.v.event.info or {}
  if info.mode ~= "rpc" or info.stream ~= "socket" then return end

  focus_deadline = now_ms() + focus_window_ms
end

local function maybe_focus_current_window()
  if focus_deadline == 0 then return end
  if now_ms() > focus_deadline then
    focus_deadline = 0
    return
  end

  focus_deadline = 0
  vim.schedule(focus_current_window)
end

function M.setup()
  focus_deadline = 0
  focus_running = false

  local group = vim.api.nvim_create_augroup("remote_kitty_focus", { clear = true })

  vim.api.nvim_create_autocmd("ChanOpen", {
    desc = "Notice remote RPC clients for Kitty focus handoff",
    group = group,
    callback = note_remote_rpc,
  })

  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
    desc = "Focus Kitty after remote edits display a buffer",
    group = group,
    callback = maybe_focus_current_window,
  })
end

return M
