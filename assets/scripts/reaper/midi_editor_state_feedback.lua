-- Purpose: Publish active MIDI editor state to the keyboard MIDI feedback renderers.
-- Notes: This is scoped to the focused MIDI editor. Add non-MIDI-editor state observers as separate scripts.

local channel = 9
local notes = {
    straight = 41,
    triplet = 42,
    grid_1 = 43,
    measure = 44,
    snap = 46,
}
local grid_cc = 90
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

local function send_cc(controller_number, value)
    send_controller(("feedback-cc %d %d %d"):format(channel, controller_number, value))
end

local function is_close(a, b)
    return math.abs(a - b) < 0.00001
end

local grid_denominators = {1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192, 16384, 32768}

local function grid_code(grid)
    if grid == nil or grid <= 0 then
        return 0
    end
    if grid >= 4 or is_close(grid, 4) then
        return 1
    end
    for index, denom in ipairs(grid_denominators) do
        local straight_qn = 4 / denom
        local triplet_qn = straight_qn * 2 / 3
        if is_close(grid, straight_qn) or is_close(grid, triplet_qn) then
            return index + 1
        end
    end
    return 0
end

local function grid_one_is_active(grid)
    if grid == nil or grid <= 0 then
        return false
    end
    return is_close(grid, 4) or is_close(grid, 4 * 2 / 3)
end

local function grid_is_triplet(grid)
    if grid == nil or grid <= 0 then
        return false
    end
    for _, denom in ipairs(grid_denominators) do
        local triplet_qn = (4 / denom) * 2 / 3
        if is_close(grid, triplet_qn) then
            return true
        end
    end
    return false
end

local function read_measure_length_qn(take)
    local item = reaper.GetMediaItemTake_Item(take)
    if not item then
        return nil
    end
    local item_time = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local _, _, measure_len, _, denominator = reaper.TimeMap2_timeToBeats(0, item_time)
    if measure_len == nil or denominator == nil or measure_len <= 0 or denominator <= 0 then
        return nil
    end
    return 4 * measure_len / denominator
end

local function grid_matches_measure(grid, measure_length_qn)
    if grid == nil or measure_length_qn == nil then
        return false
    end
    return is_close(grid, measure_length_qn) or is_close(grid, measure_length_qn * 2 / 3)
end

local function read_midi_editor_state()
    local editor = reaper.MIDIEditor_GetActive()
    if not editor then
        return nil
    end
    local take = reaper.MIDIEditor_GetTake(editor)
    if not take then
        return nil
    end

    local grid = reaper.MIDI_GetGrid(take)
    local measure_length_qn = read_measure_length_qn(take)
    local triplet = grid_is_triplet(grid)
    local code = grid_code(grid)
    local snap = reaper.MIDIEditor_GetSetting_int(editor, "snap_enabled") == 1

    return {
        grid_code = code,
        straight = code ~= 0 and not triplet,
        triplet = code ~= 0 and triplet,
        grid_1 = grid_one_is_active(grid),
        measure = grid_matches_measure(grid, measure_length_qn),
        snap = snap,
    }
end

local function publish_state(state)
    if last_state == nil or last_state.grid_code ~= state.grid_code then
        send_cc(grid_cc, state.grid_code)
    end
    for key, note in pairs(notes) do
        if last_state == nil or last_state[key] ~= state[key] then
            send_note(note, state[key])
        end
    end
    last_state = state
end

local function clear_state()
    if last_state == nil then
        return
    end
    send_cc(grid_cc, 0)
    for _, note in pairs(notes) do
        send_note(note, false)
    end
    last_state = nil
end

local function loop()
    local now = reaper.time_precise()
    if now >= next_poll then
        local state = read_midi_editor_state()
        if state then
            next_poll = now + active_poll_interval
            publish_state(state)
        else
            next_poll = now + idle_poll_interval
            clear_state()
        end
    end
    reaper.defer(loop)
end

reaper.defer(loop)
