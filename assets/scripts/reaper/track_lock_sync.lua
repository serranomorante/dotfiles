-- Purpose: Mirror REAPER "lock track controls" state to matching parameters on the
--   "instance-1" track, so track enabled/disabled state stays in sync with VE Pro.
-- Notes: A track with "lock track controls" applied is treated as disabled. This resident
--   watcher syncs every track once on load, then only acts when a track is locked or
--   unlocked: it looks up the parameter on "instance-1" named "<number> <track name>/Disable"
--   (the leading number varies and is ignored). Since it is a /Disable flag, it is set to its
--   minimum (OFF) when the track is enabled or its maximum (ON) when disabled, and only when
--   the current value already differs. REAPER exposes track lock only through the state chunk
--   (a top-level "LOCK 1" line, absent when unlocked), so item locks nested in the chunk are
--   ignored. When more than one project tab is open (a project opened via "New project tab"),
--   the initial sync is skipped and only the resident lock watcher keeps running.

local poll_interval = 0.2
local instance_track_name = "instance-1"
local param_tolerance = 0.001

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
local log_dir = state_home .. "/dotfiles/reaper-track-lock-sync"
local log_file = log_dir .. "/track-lock-sync.log"

local next_poll = 0
local last_lock_state = nil
local last_tab_count = nil
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

local function track_controls_locked(track)
    local ok, retval, chunk = pcall(reaper.GetTrackStateChunk, track, "", false)
    if not ok or not retval or not chunk then
        return false
    end
    local first = true
    for line in chunk:gmatch("[^\r\n]+") do
        if first then
            first = false
        elseif line:match("^%s*<") then
            return false
        elseif line:match("^%s*LOCK%s+1%s*$") then
            return true
        end
    end
    return false
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

local function param_track_name(param_name)
    -- Parameters are published as "<number> <track name>/Disable"; the leading number
    -- varies between parameters and is ignored.
    return param_name and param_name:match("^%d+%s+(.+)/Disable$")
end

local function find_param(instance_track, name)
    local fx_count = safe_number(0, reaper.TrackFX_GetCount, instance_track)
    for fx = 0, fx_count - 1 do
        local param_count = safe_number(0, reaper.TrackFX_GetNumParams, instance_track, fx)
        for param = 0, param_count - 1 do
            local ok, _, param_name = pcall(reaper.TrackFX_GetParamName, instance_track, fx, param)
            if ok and param_track_name(param_name) == name then
                return fx, param
            end
        end
    end
    return nil
end

local function sync_param(instance_track, fx, param, enabled)
    local ok, current, minval, maxval = pcall(reaper.TrackFX_GetParam, instance_track, fx, param)
    if not ok or type(current) ~= "number" then
        return "error", nil
    end
    local target = enabled and minval or maxval
    if math.abs(current - target) <= param_tolerance then
        return "unchanged", current
    end
    reaper.TrackFX_SetParam(instance_track, fx, param, target)
    return "set", target
end

local function append_log(line)
    local file = io.open(log_file, "a")
    if not file then
        if not logged_open_error then
            reaper.ShowConsoleMsg(("track_lock_sync: cannot write %s\n"):format(log_file))
            logged_open_error = true
        end
        return
    end
    file:write(line, "\n")
    file:close()
end

local function handle_lock_change(track, locked)
    local name = track_name(track)
    local instance_track = find_track_named(instance_track_name)
    if not instance_track then
        append_log(("[%s] track=%q lock=%d outcome=no-instance"):format(
            os.date("%Y-%m-%d %H:%M:%S"), name, locked and 1 or 0))
        return
    end
    if track == instance_track then
        return
    end
    local fx, param = find_param(instance_track, name)
    if not fx then
        append_log(("[%s] track=%q lock=%d param=%q outcome=missing"):format(
            os.date("%Y-%m-%d %H:%M:%S"), name, locked and 1 or 0, name))
        return
    end
    local outcome, value = sync_param(instance_track, fx, param, not locked)
    local value_text = value and ("%.4f"):format(value) or "?"
    append_log(("[%s] track=%q lock=%d param=%q outcome=%s value=%s"):format(
        os.date("%Y-%m-%d %H:%M:%S"), name, locked and 1 or 0, name, outcome, value_text))
end

local function read_lock_signature()
    local track_count = safe_number(0, reaper.CountTracks, 0)
    local signature = { track_count = track_count }
    for index = 0, track_count - 1 do
        local track = reaper.GetTrack(0, index)
        signature[index] = (track and track_controls_locked(track)) and 1 or 0
    end
    return signature
end

local function open_project_tab_count()
    local count = 0
    for index = 0, 255 do
        local ok, project = pcall(reaper.EnumProjects, index)
        if not ok or not project then
            break
        end
        count = count + 1
    end
    return count
end

local function sync_all_tracks(signature)
    for index = 0, signature.track_count - 1 do
        local track = reaper.GetTrack(0, index)
        if track then
            handle_lock_change(track, signature[index] == 1)
        end
    end
end

local function log_skip_sync(tab_count)
    append_log(("[%s] skipped initial sync: %d project tabs open"):format(
        os.date("%Y-%m-%d %H:%M:%S"), tab_count))
end

local function loop()
    local now = reaper.time_precise()
    if now >= next_poll then
        next_poll = now + poll_interval
        local current = read_lock_signature()
        local tab_count = open_project_tab_count()

        if last_lock_state == nil or (last_tab_count ~= nil and tab_count ~= last_tab_count) then
            -- First observation or a project tab was opened/closed: re-baseline the
            -- watcher. Only push the initial sync while a single project is open, so a
            -- project opened in a new tab does not overwrite VE Pro state.
            last_lock_state = current
            last_tab_count = tab_count
            if tab_count <= 1 then
                sync_all_tracks(current)
            else
                log_skip_sync(tab_count)
            end
        else
            local shared = math.min(last_lock_state.track_count, current.track_count)
            for index = 0, shared - 1 do
                if last_lock_state[index] ~= current[index] then
                    local track = reaper.GetTrack(0, index)
                    if track then
                        handle_lock_change(track, current[index] == 1)
                    end
                end
            end
            last_lock_state = current
        end
    end
    reaper.defer(loop)
end

reaper.defer(loop)
