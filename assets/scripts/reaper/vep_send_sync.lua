-- Purpose: Recreate MIDI sends from instrument tracks to the "instance-1" track when
--   a track template is loaded, since Reaper track templates drop sends to tracks that
--   live outside the template (here, the persistent "instance-1" VEPRO host track).
-- Notes: VEPRO channels follow a "<name>:<port>" naming convention and their automation
--   parameters are published as "<number> <name>:<port>/Disable". The MIDI port is
--   therefore recovered from the channel name after the colon, so a Reaper track named
--   "<name>" gets a MIDI send to "instance-1" with source "all channels" and destination
--   MIDI bus = port. Reaper stores the destination MIDI bus in I_MIDIFLAGS bits 22..29
--   (0 = all, 1 = bus 1/normal, 2+ = bus N), so the value is `port << 22`. I_SRCCHAN is
--   set to -1 to disable the audio side and keep the send MIDI-only. Sends are
--   idempotent: an existing send to "instance-1" is reused and only re-targeted when its
--   bus differs, so repeated polls never duplicate sends.

local poll_interval = 0.4
local idle_poll_interval = 1.0
local instance_track_name = "instance-1"

local midi_bus_shift = 22
local midi_bus_factor = 2 ^ midi_bus_shift
local midi_bus_mask = 255

local function resolve_home()
    local home = os.getenv("HOME")
    if home and home ~= "" then
        return home
    end
    -- Wine REAPER drops HOME from the Windows environment; fall back to USER.
    local user = os.getenv("USER")
    if user and user ~= "" then
        return "/home/" .. user
    end
    return ""
end

local home = resolve_home()
local state_home = os.getenv("XDG_STATE_HOME") or (home .. "/.local/state")
local log_dir = state_home .. "/dotfiles/reaper-vep-send-sync"
local log_file = log_dir .. "/vep-send-sync.log"

local next_poll = 0
local last_signature = nil
local logged_open_error = false

local function safe_number(default, fn, ...)
    local ok, result = pcall(fn, ...)
    if ok and type(result) == "number" then
        return result
    end
    return default
end

local function track_name(track)
    local _, name = reaper.GetTrackName(track, "")
    return name
end

local function find_track_named(name)
    local track_count = safe_number(0, reaper.CountTracks, 0)
    for index = 0, track_count - 1 do
        local track = reaper.GetTrack(0, index)
        if track and track_name(track) == name then
            return track
        end
    end
    return nil
end

local function append_log(line)
    local file = io.open(log_file, "a")
    if not file then
        if not logged_open_error then
            reaper.ShowConsoleMsg(("vep_send_sync: cannot write %s\n"):format(log_file))
            logged_open_error = true
        end
        return
    end
    file:write(line, "\n")
    file:close()
end

local function send_dest_bus(flags)
    -- I_MIDIFLAGS bits 22..29 hold the destination MIDI bus (0 = all, 1 = bus 1, ...).
    return math.floor(flags / midi_bus_factor) % (midi_bus_mask + 1)
end

local function param_port(param_name)
    -- VEPRO channels are "<name>:<port>"; the /Disable parameter is published as
    -- "<number> <name>:<port>/Disable".
    if not param_name then
        return nil, nil
    end
    local base, port = param_name:match("^%d+%s+(.+):(%d+)/Disable$")
    if not base or not port then
        return nil, nil
    end
    return base, tonumber(port)
end

local function channel_ports(instance_track)
    local ports = {}
    local fx_count = safe_number(0, reaper.TrackFX_GetCount, instance_track)
    for fx = 0, fx_count - 1 do
        local param_count = safe_number(0, reaper.TrackFX_GetNumParams, instance_track, fx)
        for param = 0, param_count - 1 do
            local ok, _, param_name = pcall(reaper.TrackFX_GetParamName, instance_track, fx, param)
            if ok then
                local base, port = param_port(param_name)
                if base then
                    ports[base] = port
                end
            end
        end
    end
    return ports
end

local function ensure_send(track, instance_track, port)
    local send_count = safe_number(0, reaper.GetTrackNumSends, track, 0)
    for index = 0, send_count - 1 do
        local dest = reaper.GetTrackSendInfo_Value(track, 0, index, "P_DESTTRACK")
        if dest == instance_track then
            local flags = safe_number(0, reaper.GetTrackSendInfo_Value, track, 0, index, "I_MIDIFLAGS")
            if send_dest_bus(flags) == port then
                return "unchanged"
            end
            reaper.SetTrackSendInfo_Value(track, 0, index, "I_SRCCHAN", -1)
            reaper.SetTrackSendInfo_Value(track, 0, index, "I_MIDIFLAGS", port * midi_bus_factor)
            return "set"
        end
    end
    local send_index = reaper.CreateTrackSend(track, instance_track)
    if not send_index or send_index < 0 then
        return "error"
    end
    reaper.SetTrackSendInfo_Value(track, 0, send_index, "I_SRCCHAN", -1)
    reaper.SetTrackSendInfo_Value(track, 0, send_index, "I_MIDIFLAGS", port * midi_bus_factor)
    return "created"
end

local function handle_track(track, instance_track, ports)
    local name = track_name(track)
    local port = ports[name]
    if not port then
        return
    end
    local outcome = ensure_send(track, instance_track, port)
    append_log(("[%s] track=%q port=%d outcome=%s"):format(
        os.date("%Y-%m-%d %H:%M:%S"), name, port, outcome))
end

local function track_signature()
    local parts = {}
    local track_count = safe_number(0, reaper.CountTracks, 0)
    for index = 0, track_count - 1 do
        local track = reaper.GetTrack(0, index)
        if track and track_name(track) ~= instance_track_name then
            parts[#parts + 1] = track_name(track)
        end
    end
    return table.concat(parts, "\0")
end

local function sync_all_tracks(instance_track)
    local ports = channel_ports(instance_track)
    local track_count = safe_number(0, reaper.CountTracks, 0)
    for index = 0, track_count - 1 do
        local track = reaper.GetTrack(0, index)
        if track and track_name(track) ~= instance_track_name then
            handle_track(track, instance_track, ports)
        end
    end
end

local function loop()
    local now = reaper.time_precise()
    if now >= next_poll then
        local instance_track = find_track_named(instance_track_name)
        if not instance_track then
            next_poll = now + idle_poll_interval
            last_signature = nil
            reaper.defer(loop)
            return
        end
        next_poll = now + poll_interval
        local signature = track_signature()
        if last_signature ~= signature then
            last_signature = signature
            sync_all_tracks(instance_track)
        end
    end
    reaper.defer(loop)
end

reaper.defer(loop)
