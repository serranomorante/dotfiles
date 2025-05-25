local toboolean = { ["true"] = true, ["false"] = false }
---@type string
local should_go_to_previous_position = reaper.GetExtState("custom", "should_go_to_previous_position") or "true"

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
reaper.Main_OnCommand(action_id, 0, 0)
