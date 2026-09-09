#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: audio
# dotfiles-test-tags: audio reaper lua
# dotfiles-test-case: vep-send-sync-creates-and-fixes-sends
# dotfiles-test-case: vep-send-sync-idles-without-instance

vep_send_sync="${DOTFILES_TEST_ROOT}/assets/scripts/reaper/vep_send_sync.lua"

case "${DOTFILES_TEST_CASE:-}" in
vep-send-sync-creates-and-fixes-sends)
    command -v lua >/dev/null 2>&1 || {
        printf 'lua is not available\n' >&2
        exit 77
    }

    home="${DOTFILES_TEST_TMP}/home"
    state_home="${DOTFILES_TEST_TMP}/state"
    mkdir -p "$home" "${state_home}/dotfiles/reaper-vep-send-sync"
    harness="${DOTFILES_TEST_TMP}/vep-send-sync-harness.lua"

    cat >"$harness" <<'LUA'
local script_path = assert(os.getenv("VEP_SEND_SYNC_SCRIPT"), "VEP_SEND_SYNC_SCRIPT not set")

-- VEPRO channels follow "<name>:<port>"; the /Disable parameter is published as
-- "<number> <name>:<port>/Disable". Only the instance track hosts these params.
local instance_params = {
    { name = "8 drums-1:2/Disable" },
    { name = "14 bass-1:3/Disable" },
}
local instance = { name = "instance-1", params = instance_params }
local tracks = {
    { name = "drums-1" },  -- port 2
    { name = "bass-1" },   -- port 3
    { name = "other-1" },  -- no VEPRO channel
    instance,
}
local now = 0
local defer_cb = nil
local created_sends = 0

reaper = {}
function reaper.CountTracks() return #tracks end
function reaper.GetTrack(_, i) return tracks[i + 1] end
function reaper.GetTrackName(t) return true, t.name end
function reaper.TrackFX_GetCount(t) return t.params and 1 or 0 end
function reaper.TrackFX_GetNumParams(t, _) return t.params and #t.params or 0 end
function reaper.TrackFX_GetParamName(t, _, p) return true, t.params[p + 1].name end
function reaper.GetTrackNumSends(t, _) return t.sends and #t.sends or 0 end
function reaper.GetTrackSendInfo_Value(t, _, idx, parm)
    local send = t.sends and t.sends[idx + 1]
    if not send then return 0 end
    if parm == "P_DESTTRACK" then return send.dest end
    if parm == "I_MIDIFLAGS" then return send.flags end
    if parm == "I_SRCCHAN" then return send.srcchan or 0 end
    return 0
end
function reaper.SetTrackSendInfo_Value(t, _, idx, parm, v)
    local send = t.sends[idx + 1]
    if parm == "I_SRCCHAN" then send.srcchan = v end
    if parm == "I_MIDIFLAGS" then send.flags = v end
    return true
end
function reaper.CreateTrackSend(src, dest)
    created_sends = created_sends + 1
    src.sends = src.sends or {}
    src.sends[#src.sends + 1] = { dest = dest, flags = 0 }
    return #src.sends - 1
end
function reaper.time_precise() return now end
function reaper.defer(cb) defer_cb = cb end
function reaper.ShowConsoleMsg() end

local code = assert(io.open(script_path):read("*a"))
assert(load(code, "chunk"))()

local function pump()
    local cb = defer_cb
    if cb then defer_cb = nil; now = now + 0.5; cb() end
end

local drums = tracks[1]
local bass = tracks[2]
local function send_count(t) return t.sends and #t.sends or 0 end

-- First load: mapped tracks get a MIDI send to instance-1 with bus = port.
pump()
assert(send_count(drums) == 1, "drums-1 should have one send on load")
assert(drums.sends[1].dest == instance, "send must target instance-1")
assert(drums.sends[1].flags == 2 * (2 ^ 22),
    string.format("drums-1 send bus must be 2, got flags %d", drums.sends[1].flags))
assert(drums.sends[1].srcchan == -1, "send must be MIDI-only (I_SRCCHAN = -1)")
assert(send_count(bass) == 1, "bass-1 should have one send on load")
assert(bass.sends[1].dest == instance, "send must target instance-1")
assert(bass.sends[1].flags == 3 * (2 ^ 22),
    string.format("bass-1 send bus must be 3, got flags %d", bass.sends[1].flags))
assert(send_count(tracks[3]) == 0, "track without a VEPRO channel must not get a send")
assert(send_count(instance) == 0, "instance track must not get a send")
assert(created_sends == 2, string.format("expected 2 sends created, got %d", created_sends))

-- Unchanged signature: no new sends.
pump()
assert(send_count(drums) == 1 and send_count(bass) == 1, "no duplicate sends on unchanged signature")
assert(created_sends == 2, "no new sends on unchanged signature")

-- Existing send with the wrong bus gets re-targeted, not duplicated.
drums.sends[1].flags = 0
table.insert(tracks, { name = "extra-1" })
pump()
assert(send_count(drums) == 1, "wrong-bus fix must reuse the existing send")
assert(drums.sends[1].flags == 2 * (2 ^ 22),
    string.format("wrong-bus send should be re-targeted to 2, got flags %d", drums.sends[1].flags))
assert(created_sends == 2, "wrong-bus fix must not create a new send")
assert(send_count(tracks[5]) == 0, "unmapped extra track must not get a send")

print("PASS")
LUA

    HOME="$home" \
        XDG_STATE_HOME="$state_home" \
        VEP_SEND_SYNC_SCRIPT="$vep_send_sync" \
        lua "$harness"
    ;;
vep-send-sync-idles-without-instance)
    command -v lua >/dev/null 2>&1 || {
        printf 'lua is not available\n' >&2
        exit 77
    }

    home="${DOTFILES_TEST_TMP}/home"
    state_home="${DOTFILES_TEST_TMP}/state"
    mkdir -p "$home" "${state_home}/dotfiles/reaper-vep-send-sync"
    harness="${DOTFILES_TEST_TMP}/vep-send-sync-harness.lua"

    cat >"$harness" <<'LUA'
local script_path = assert(os.getenv("VEP_SEND_SYNC_SCRIPT"), "VEP_SEND_SYNC_SCRIPT not set")

local tracks = {
    { name = "drums-1" },  -- would be mapped, but no instance-1 track present
}
local now = 0
local defer_cb = nil
local created_sends = 0

reaper = {}
function reaper.CountTracks() return #tracks end
function reaper.GetTrack(_, i) return tracks[i + 1] end
function reaper.GetTrackName(t) return true, t.name end
function reaper.GetTrackNumSends(t, _) return t.sends and #t.sends or 0 end
function reaper.CreateTrackSend(src, dest)
    created_sends = created_sends + 1
    src.sends = src.sends or {}
    src.sends[#src.sends + 1] = { dest = dest, flags = 0 }
    return #src.sends - 1
end
function reaper.time_precise() return now end
function reaper.defer(cb) defer_cb = cb end
function reaper.ShowConsoleMsg() end

local code = assert(io.open(script_path):read("*a"))
assert(load(code, "chunk"))()

local function pump()
    local cb = defer_cb
    if cb then defer_cb = nil; now = now + 0.5; cb() end
end

local drums = tracks[1]

pump()
assert(drums.sends == nil or #drums.sends == 0, "no send without an instance-1 track")
assert(created_sends == 0, string.format("expected 0 sends without instance-1, got %d", created_sends))

print("PASS")
LUA

    HOME="$home" \
        XDG_STATE_HOME="$state_home" \
        VEP_SEND_SYNC_SCRIPT="$vep_send_sync" \
        lua "$harness"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
