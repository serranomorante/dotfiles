#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: audio
# dotfiles-test-tags: audio reaper lua firejail
# dotfiles-test-case: reaper-track-lock-sync-syncs-on-load-and-lock-change

track_lock_sync="${DOTFILES_TEST_ROOT}/assets/scripts/reaper/track_lock_sync.lua"

case "${DOTFILES_TEST_CASE:-}" in
reaper-track-lock-sync-syncs-on-load-and-lock-change)
    command -v lua >/dev/null 2>&1 || {
        printf 'lua is not available\n' >&2
        exit 77
    }

    home="${DOTFILES_TEST_TMP}/home"
    state_home="${DOTFILES_TEST_TMP}/state"
    mkdir -p "$home" "${state_home}/dotfiles/reaper-track-lock-sync"
    harness="${DOTFILES_TEST_TMP}/track-lock-sync-harness.lua"

    cat >"$harness" <<'LUA'
local script_path = assert(os.getenv("TRACK_LOCK_SYNC_SCRIPT"), "TRACK_LOCK_SYNC_SCRIPT not set")

-- Parameters hosted by the "instance-1" track. Values start out of sync with
-- the track lock state so the first-load sync has to push ON/OFF.
local instance_params = {
    { name = "8 guitar-1/Disable", value = 0.0, min = 0.0, max = 1.0 },
    { name = "9 guitar-2/Disable", value = 1.0, min = 0.0, max = 1.0 },
    { name = "10 guitar-3/Disable", value = 1.0, min = 0.0, max = 1.0 },
}
local tracks = {
    { name = "guitar-1", locked = true },   -- disabled at load -> should push ON (1.0)
    { name = "guitar-2", locked = false },  -- enabled at load -> should push OFF (0.0)
    { name = "guitar-3", locked = true },   -- already in sync (1.0) -> no signal
    { name = "instance-1", locked = false, params = instance_params },
}
local now = 0
local defer_cb = nil
local set_param_calls = 0

reaper = {}
function reaper.CountTracks() return #tracks end
function reaper.GetTrack(_, i) return tracks[i + 1] end
function reaper.GetTrackName(t) return true, t.name end
function reaper.GetTrackStateChunk(t, _, _)
    local lines = { "<TRACK {00000000-0000-0000-0000-000000000000}", '  NAME "' .. t.name .. '"' }
    if t.locked then table.insert(lines, "  LOCK 1") end
    table.insert(lines, ">")
    return true, table.concat(lines, "\n")
end
function reaper.TrackFX_GetCount(t) return t.params and 1 or 0 end
function reaper.TrackFX_GetNumParams(t, _) return t.params and #t.params or 0 end
function reaper.TrackFX_GetParamName(t, _, p) return true, t.params[p + 1].name end
function reaper.TrackFX_GetParam(t, _, p)
    local prm = t.params[p + 1]
    return prm.value, prm.min, prm.max
end
function reaper.TrackFX_SetParam(t, _, p, v)
    set_param_calls = set_param_calls + 1
    t.params[p + 1].value = v
    return true
end
function reaper.time_precise() return now end
function reaper.defer(cb) defer_cb = cb end
function reaper.ShowConsoleMsg() end

local code = assert(io.open(script_path):read("*a"))
assert(load(code, "chunk"))()

local function pump()
    local cb = defer_cb
    if cb then defer_cb = nil; now = now + 0.3; cb() end
end

local function value(i) return instance_params[i].value end

-- First load: sync every track once, only sending when the value differs.
pump()
assert(value(1) == 1.0, string.format("locked track should sync to ON (1.0), got %s", value(1)))
assert(value(2) == 0.0, string.format("unlocked track should sync to OFF (0.0), got %s", value(2)))
assert(value(3) == 1.0, "in-sync track must stay untouched")
assert(set_param_calls == 2, string.format("expected 2 sets on load, got %d", set_param_calls))

-- Lock/unlock transitions use the inverted /Disable polarity.
tracks[1].locked = false -- enable guitar-1 -> OFF
pump()
assert(value(1) == 0.0, string.format("unlock should set OFF (0.0), got %s", value(1)))

tracks[2].locked = true -- disable guitar-2 -> ON
pump()
assert(value(2) == 1.0, string.format("lock should set ON (1.0), got %s", value(2)))

-- The instance-1 host track is never touched.
assert(value(1) == 0.0 and value(2) == 1.0, "instance params must reflect the final state")

print("PASS")
LUA

    HOME="$home" \
        XDG_STATE_HOME="$state_home" \
        TRACK_LOCK_SYNC_SCRIPT="$track_lock_sync" \
        lua "$harness"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
