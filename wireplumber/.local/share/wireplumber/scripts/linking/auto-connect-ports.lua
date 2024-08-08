--[[
  Thanks!
  https://gitlab.freedesktop.org/pipewire/wireplumber/-/blob/91a8c344b185cc5e0a972124940acddde602de85/src/scripts/linking/find-user-target.lua.example
]]

local putils = require("linking-utils")
log = Log.open_topic("s-linking")

local APP_TO_OUTPUT = {
  ["Brave"] = "media-sink",
  ["Firefox"] = "media-sink",
  ["ALSA plug-in [plexamp]"] = "media-sink",
  ["BTAdapter"] = "media-sink",
  ---Apply noise reduction to Google chrome media sound
  ["Google Chrome"] = "Filtered Headphones", -- will fallback to default if not available
}

SimpleEventHook({
  name = "linking/find-user-target",
  before = "linking/find-defined-target",
  interests = {
    EventInterest({
      Constraint({ "event.type", "=", "select-target" }),
    }),
  },
  execute = function(event)
    local source, om, si, si_props, si_flags, target = putils:unwrap_select_target_event(event)

    ---@type string
    local node_to_route_from = si_props["node.name"]

    ---bypass the hook if the target is already picked up
    if target then
      return
    end

    local node_to_route_to = APP_TO_OUTPUT[node_to_route_from]

    if node_to_route_to == nil then
      return
    end

    local media_sink_si = om:lookup({ Constraint({ "node.name", "=", node_to_route_to }) })

    ---store the found target on the event,
    ---the next hooks will take care of linking
    event:set_data("target", media_sink_si)
  end,
}):register()
