-- Purpose: Publish project and transport state to the keyboard MIDI feedback renderers.
-- Notes: This is scoped to project-level transport/options state.

local channel = 10
local notes = {
    metronome = 41,
    metronome_badge = 95,
}
local active_velocity = 90
local inactive_velocity = 0
local poll_interval = 0.08
local command_timeout_ms = 100
local metronome_action_id = 40364

local home = os.getenv("HOME") or ""
local cache_home = os.getenv("XDG_CACHE_HOME") or (home .. "/.cache")
local controller = cache_home .. "/dotfiles/keyboard-midi-controller/keyboard-midi-controller"
local next_poll = 0
local last_state = nil

local function shell_quote(value)
    return string.format("%q", value)
end

local function send_controller(args)
    if controller == "/dotfiles/keyboard-midi-controller/keyboard-midi-controller" then
        return
    end
    reaper.ExecProcess(shell_quote(controller) .. " " .. args, command_timeout_ms)
end

local function send_note(note, active)
    local velocity = active and active_velocity or inactive_velocity
    send_controller(("feedback-note %d %d %d"):format(channel, note, velocity))
end

local function safe_number(default, fn, ...)
    local ok, result = pcall(fn, ...)
    if ok and type(result) == "number" then
        return result
    end
    return default
end

local function project_transport_state()
    local metronome = safe_number(0, reaper.GetToggleCommandStateEx, 0, metronome_action_id) > 0
    return {
        metronome = metronome,
        metronome_badge = metronome,
    }
end

local function refresh_reaper_ui(state)
    if last_state == nil or last_state.metronome ~= state.metronome then
        reaper.RefreshToolbar2(0, metronome_action_id)
    end
end

local function publish_state(state)
    refresh_reaper_ui(state)
    for key, note in pairs(notes) do
        if last_state == nil or last_state[key] ~= state[key] then
            send_note(note, state[key])
        end
    end
    last_state = state
end

local function loop()
    local now = reaper.time_precise()
    if now >= next_poll then
        local state = project_transport_state()
        next_poll = now + poll_interval
        publish_state(state)
    end
    reaper.defer(loop)
end

reaper.defer(loop)
