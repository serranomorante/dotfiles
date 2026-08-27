#!/usr/bin/env bash
set -euo pipefail

# dotfiles-test-unit: audio
# dotfiles-test-tags: audio reaper lua
# dotfiles-test-case: reaper-alternate-position-toggles-back-and-forth
# dotfiles-test-case: reaper-alternate-position-manual-move-returns-to-last

alternate_position="${DOTFILES_TEST_ROOT}/assets/scripts/reaper/alternate_position.lua"

case "${DOTFILES_TEST_CASE:-}" in
reaper-alternate-position-toggles-back-and-forth)
    command -v lua >/dev/null 2>&1 || {
        printf 'lua is not available\n' >&2
        exit 77
    }

    harness="${DOTFILES_TEST_TMP}/alternate-position-harness.lua"

    cat >"$harness" <<'LUA'
local script_path = assert(os.getenv("ALTERNATE_POSITION_SCRIPT"), "ALTERNATE_POSITION_SCRIPT not set")
local code = assert(io.open(script_path):read("*a"))

local extstate = {}
local cursor_pos = 10.0
local set_edit_calls = {}

reaper = {}
function reaper.GetExtState(ns, key) return extstate[ns .. "\0" .. key] or "" end
function reaper.SetExtState(ns, key, value, persist) extstate[ns .. "\0" .. key] = value end
function reaper.GetCursorPosition() return cursor_pos end
function reaper.SetEditCurPos(pos, moveview, seekplay)
    set_edit_calls[#set_edit_calls + 1] = pos
    cursor_pos = pos
end

local function run() assert(load(code, "chunk"))() end

-- First run initializes the anchor without moving the cursor.
run()
assert(cursor_pos == 10.0, "first run must not move the cursor")
assert(#set_edit_calls == 0, "first run must not move the cursor")

-- A second run before any manual move is a no-op: the two slots are identical.
run()
assert(cursor_pos == 10.0, "no-op toggle must not move the cursor")
assert(#set_edit_calls == 0, "no-op toggle must not move the cursor")

-- Manual move to 25, then toggle -> back to 10.
cursor_pos = 25.0
run()
assert(cursor_pos == 10.0, string.format("toggle after manual move should return to last, got %s", cursor_pos))
assert(set_edit_calls[1] == 10.0, "toggle should jump to the last position 10")

-- Toggle again -> back to 25.
run()
assert(cursor_pos == 25.0, string.format("toggle should return to previous position, got %s", cursor_pos))
assert(set_edit_calls[2] == 25.0)

-- Toggle once more -> back to 10.
run()
assert(cursor_pos == 10.0, "toggle should return to 10 again")
assert(set_edit_calls[3] == 10.0)

print("PASS")
LUA

    ALTERNATE_POSITION_SCRIPT="$alternate_position" lua "$harness"
    ;;
reaper-alternate-position-manual-move-returns-to-last)
    command -v lua >/dev/null 2>&1 || {
        printf 'lua is not available\n' >&2
        exit 77
    }

    harness="${DOTFILES_TEST_TMP}/alternate-position-harness.lua"

    cat >"$harness" <<'LUA'
local script_path = assert(os.getenv("ALTERNATE_POSITION_SCRIPT"), "ALTERNATE_POSITION_SCRIPT not set")
local code = assert(io.open(script_path):read("*a"))

local extstate = {}
local cursor_pos = 10.0
local set_edit_calls = {}

reaper = {}
function reaper.GetExtState(ns, key) return extstate[ns .. "\0" .. key] or "" end
function reaper.SetExtState(ns, key, value, persist) extstate[ns .. "\0" .. key] = value end
function reaper.GetCursorPosition() return cursor_pos end
function reaper.SetEditCurPos(pos, moveview, seekplay)
    set_edit_calls[#set_edit_calls + 1] = pos
    cursor_pos = pos
end

local function run() assert(load(code, "chunk"))() end

run() -- init at A = 10

-- Move to B = 25, toggle -> A = 10; toggle -> B = 25.
cursor_pos = 25.0
run()
assert(cursor_pos == 10.0)
run()
assert(cursor_pos == 25.0)

-- Move to C = 40 while at B, toggle -> B = 25 (last position before the click).
cursor_pos = 40.0
run()
assert(cursor_pos == 25.0, string.format("manual move should return to the last position before the click, got %s", cursor_pos))

-- Toggle again -> C = 40.
run()
assert(cursor_pos == 40.0, string.format("second toggle should return to the manual position, got %s", cursor_pos))

print("PASS")
LUA

    ALTERNATE_POSITION_SCRIPT="$alternate_position" lua "$harness"
    ;;
*)
    printf 'unknown DOTFILES_TEST_CASE: %s\n' "${DOTFILES_TEST_CASE:-}" >&2
    exit 2
    ;;
esac
