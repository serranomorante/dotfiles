-- Purpose: Toggle the edit cursor between the current position and the last
--   position it was at. If the cursor was moved manually since the last toggle,
--   jump back to the last toggled position and remember the manual position as
--   the new "other" slot, so the next toggle returns to it.
-- Notes: State is stored in REAPER ExtState (session only). Two slots are kept:
--   "last" is where the cursor is expected to be after our own move, and "prev"
--   is the position to jump back to. Cursor positions are compared with a small
--   epsilon because floating-point times do not round-trip exactly.

local NAMESPACE = "alternate_position"
local EPSILON = 0.000001

local function get_position(key)
    local value = reaper.GetExtState(NAMESPACE, key)
    if value == nil or value == "" then
        return nil
    end
    return tonumber(value)
end

local function set_position(key, value)
    reaper.SetExtState(NAMESPACE, key, string.format("%.9f", value), false)
end

local function nearly_equal(a, b)
    if a == nil or b == nil then
        return false
    end
    return math.abs(a - b) < EPSILON
end

local now = reaper.GetCursorPosition()
local last = get_position("last")
local prev = get_position("prev")

if last == nil then
    -- First run: record the current position as the anchor; there is nothing to
    -- toggle back to yet.
    set_position("last", now)
    set_position("prev", now)
    return
end

if nearly_equal(now, last) then
    -- Cursor is still at the anchor. Toggle back to the previous position and
    -- swap the slots so the next toggle returns here.
    if prev ~= nil and not nearly_equal(prev, last) then
        reaper.SetEditCurPos(prev, true, false)
    end
    set_position("last", prev)
    set_position("prev", last)
else
    -- Cursor was moved manually. Jump back to the last anchor and remember the
    -- manual position as the new previous position.
    reaper.SetEditCurPos(last, true, false)
    set_position("prev", now)
end
