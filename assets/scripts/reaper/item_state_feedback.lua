-- Purpose: Publish selected item state to the keyboard MIDI feedback renderers.
-- Notes: This is scoped to arrange-view item state. Keep MIDI-editor-only state in midi_editor_state_feedback.lua.

local channel = 12
local notes = {
    mute = 40,
    lock = 43,
}
local active_velocity = 90
local inactive_velocity = 0
local active_poll_interval = 0.08
local idle_poll_interval = 0.50
local command_timeout_ms = 100

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

local function selected_items_state()
    local count = safe_number(0, reaper.CountSelectedMediaItems, 0)
    local muted = false
    local locked = false

    for item_index = 0, count - 1 do
        local item = reaper.GetSelectedMediaItem(0, item_index)
        if item then
            muted = muted or safe_number(0, reaper.GetMediaItemInfo_Value, item, "B_MUTE") > 0.5
            locked = locked or safe_number(0, reaper.GetMediaItemInfo_Value, item, "C_LOCK") > 0.5
        end
    end

    return {
        count = count,
        mute = count > 0 and muted,
        lock = count > 0 and locked,
    }
end

local function publish_state(state)
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
        local state = selected_items_state()
        next_poll = now + (state.count > 0 and active_poll_interval or idle_poll_interval)
        publish_state(state)
    end
    reaper.defer(loop)
end

reaper.defer(loop)
