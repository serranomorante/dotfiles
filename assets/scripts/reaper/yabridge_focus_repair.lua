local poll_interval = 0.25
local watchdog_interval = 2.0
local forced_repair_interval = 0.5
local repair_duration = 1.5
local exec_timeout_ms = 250
local last_poll = 0
local last_watchdog = 0
local last_fx_open_count = 0
local last_fx_ui_count = 0
local repair_until = 0
local last_repair = 0

local function safe_number(default, fn, ...)
    local ok, result = pcall(fn, ...)
    if ok and type(result) == "number" then
        return result
    end

    return default
end

local function safe_boolean(fn, ...)
    local ok, result = pcall(fn, ...)
    return ok and result == true
end

local function has_window(hwnd)
    local text = tostring(hwnd)
    return hwnd ~= nil and text ~= "userdata: 0x0000000000000000" and text ~= "userdata: 0x0" and text ~= "userdata: (nil)"
end

local function track_fx_open_count(track)
    local count = 0
    local fx_count = safe_number(0, reaper.TrackFX_GetCount, track)

    for fx_index = 0, fx_count - 1 do
        if safe_boolean(reaper.TrackFX_GetOpen, track, fx_index) then
            count = count + 1
        end
    end

    return count
end

local function track_fx_ui_count(track)
    local count = 0

    if safe_number(-1, reaper.TrackFX_GetChainVisible, track) >= 0 then
        count = count + 1
    end

    local fx_count = safe_number(0, reaper.TrackFX_GetCount, track)
    for fx_index = 0, fx_count - 1 do
        local ok, hwnd = pcall(reaper.TrackFX_GetFloatingWindow, track, fx_index)
        if ok and has_window(hwnd) then
            count = count + 1
        end
    end

    return count
end

local function take_fx_open_count(take)
    if not take then
        return 0
    end

    local count = 0
    local fx_count = safe_number(0, reaper.TakeFX_GetCount, take)

    for fx_index = 0, fx_count - 1 do
        if safe_boolean(reaper.TakeFX_GetOpen, take, fx_index) then
            count = count + 1
        end
    end

    return count
end

local function take_fx_ui_count(take)
    if not take then
        return 0
    end

    local count = 0

    if safe_number(-1, reaper.TakeFX_GetChainVisible, take) >= 0 then
        count = count + 1
    end

    local fx_count = safe_number(0, reaper.TakeFX_GetCount, take)
    for fx_index = 0, fx_count - 1 do
        local ok, hwnd = pcall(reaper.TakeFX_GetFloatingWindow, take, fx_index)
        if ok and has_window(hwnd) then
            count = count + 1
        end
    end

    return count
end

local function open_fx_count()
    local count = track_fx_open_count(reaper.GetMasterTrack(0))

    local track_count = safe_number(0, reaper.CountTracks, 0)
    for track_index = 0, track_count - 1 do
        count = count + track_fx_open_count(reaper.GetTrack(0, track_index))
    end

    local item_count = safe_number(0, reaper.CountSelectedMediaItems, 0)
    for item_index = 0, item_count - 1 do
        local item = reaper.GetSelectedMediaItem(0, item_index)
        local take_count = safe_number(0, reaper.CountTakes, item)
        for take_index = 0, take_count - 1 do
            count = count + take_fx_open_count(reaper.GetMediaItemTake(item, take_index))
        end
    end

    return count
end

local function visible_fx_ui_count()
    local count = track_fx_ui_count(reaper.GetMasterTrack(0))

    local track_count = safe_number(0, reaper.CountTracks, 0)
    for track_index = 0, track_count - 1 do
        count = count + track_fx_ui_count(reaper.GetTrack(0, track_index))
    end

    local item_count = safe_number(0, reaper.CountSelectedMediaItems, 0)
    for item_index = 0, item_count - 1 do
        local item = reaper.GetSelectedMediaItem(0, item_index)
        local take_count = safe_number(0, reaper.CountTakes, item)
        for take_index = 0, take_count - 1 do
            count = count + take_fx_ui_count(reaper.GetMediaItemTake(item, take_index))
        end
    end

    return count
end

local function repair_reaper_focus_if_broken(force)
    local force_value = force and "1" or "0"
    local command = table.concat({
        "/usr/bin/bash -lc 'force=",
        force_value,
        "; ",
        "active_window=$(xdotool getactivewindow 2>/dev/null) || exit 0; ",
        'case "$active_window" in ""|*[!0-9]*) exit 0 ;; esac; ',
        'active_class=$(xdotool getwindowclassname "$active_window" 2>/dev/null) || exit 0; ',
        'case "$active_class" in REAPER|reaper) ;; *) exit 0 ;; esac; ',
        "focused_window=$(xdotool getwindowfocus 2>/dev/null) || focused_window=; ",
        '[ "$force" = 1 ] || [ -z "$focused_window" ] || exit 0; ',
        '[ "$focused_window" != "$active_window" ] || exit 0; ',
        "current_active=$(xdotool getactivewindow 2>/dev/null) || exit 0; ",
        '[ "$current_active" = "$active_window" ] || exit 0; ',
        'xdotool windowfocus "$active_window" >/dev/null 2>&1 || true',
        "'",
    })

    reaper.ExecProcess(command, exec_timeout_ms)
end

local function loop_body()
    local now = reaper.time_precise()

    if now - last_poll >= poll_interval then
        last_poll = now

        local fx_open_count = open_fx_count()
        local fx_ui_count = visible_fx_ui_count()
        if fx_open_count < last_fx_open_count or fx_ui_count < last_fx_ui_count then
            repair_until = now + repair_duration
            last_repair = 0
        end

        last_fx_open_count = fx_open_count
        last_fx_ui_count = fx_ui_count
    end

    if repair_until > now and now - last_repair >= forced_repair_interval then
        last_repair = now
        repair_reaper_focus_if_broken(true)
    elseif now - last_watchdog >= watchdog_interval then
        last_watchdog = now
        repair_reaper_focus_if_broken(false)
    end
end

local function loop()
    pcall(loop_body)

    reaper.defer(loop)
end

reaper.defer(loop)
