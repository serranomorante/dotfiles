local toboolean = { ["true"] = true, ["false"] = false }
---@type string|nil
local sws_last_used_redoundo_action = reaper.GetExtState("custom", "sws_last_used_redoundo_action")
---@type number|nil
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

local action_id = get_id_from_action_name(toboolean[sws_last_used_redoundo_action] and GO_TO.CURRENT_POS_ACTION or GO_TO.PREVIOUS_POS_ACTION)
reaper.SetExtState("custom", "sws_last_used_redoundo_action", tostring(not toboolean[sws_last_used_redoundo_action]), false)
local current_edit_cursor_pos = tonumber(tostring(reaper.GetCursorPosition()))
local current_should_go_to_previous_position = tostring(not toboolean[sws_last_used_redoundo_action])
reaper.Main_OnCommand(action_id, 0, 0)

-- if same edit cursor position, toggle again
if previous_edit_cursor_pos == current_edit_cursor_pos then
  action_id = action_id == GO_TO.CURRENT_POS_ACTION and GO_TO.PREVIOUS_POS_ACTION or GO_TO.CURRENT_POS_ACTION
  reaper.Main_OnCommand(action_id, 0, 0)
else
  reaper.SetExtState("custom", "sws_last_used_redoundo_action", current_should_go_to_previous_position, false)
  reaper.SetExtState("custom", "previous_edit_cursor_pos", current_edit_cursor_pos, false)
end
-- reaper.ShowConsoleMsg(string.format("edit cursor pos:\n%s\nshould go previous:\n%s", current_edit_cursor_pos, current_should_go_to_previous_position))
