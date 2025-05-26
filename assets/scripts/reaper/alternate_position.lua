local toboolean = { ["true"] = true, ["false"] = false }
---@type string
local should_go_to_previous_position = reaper.GetExtState("custom", "should_go_to_previous_position") or "true"
local previous_edit_cursor_pos = tonumber(tostring(reaper.GetExtState("custom", "previous_edit_cursor_pos")))

local GO_TO = {
  PREVIOUS_POS_ACTION = "SWS: Undo edit cursor move",
  CURRENT_POS_ACTION = "SWS: Redo edit cursor move"
}

---@param search string
local function get_id_from_action_name(search)
  local name, cnt, ret = "", 0, 1
  while ret > 0 do
    ret, name = reaper.CF_EnumerateActions(0, cnt, "")
    if name == search then return ret end
    cnt = cnt + 1
  end
end

local action_id = get_id_from_action_name(toboolean[should_go_to_previous_position] and GO_TO.CURRENT_POS_ACTION or GO_TO.PREVIOUS_POS_ACTION)
reaper.SetExtState("custom", "should_go_to_previous_position", tostring(not toboolean[should_go_to_previous_position]), false)
local current_edit_cursor_pos = tonumber(tostring(reaper.GetCursorPosition()))
local current_should_go_to_previous_position = tostring(not toboolean[should_go_to_previous_position])
reaper.Main_OnCommand(action_id, 0, 0)

-- if same edit cursor position, toggle again
if previous_edit_cursor_pos == current_edit_cursor_pos then
  action_id = action_id == GO_TO.CURRENT_POS_ACTION and GO_TO.PREVIOUS_POS_ACTION or GO_TO.CURRENT_POS_ACTION
  reaper.Main_OnCommand(action_id, 0, 0)
else
  reaper.SetExtState("custom", "should_go_to_previous_position", current_should_go_to_previous_position, false)
  reaper.SetExtState("custom", "previous_edit_cursor_pos", current_edit_cursor_pos, false)
end
