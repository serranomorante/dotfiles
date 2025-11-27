--[[
  Thanks!
  https://gitlab.freedesktop.org/pipewire/wireplumber/-/blob/91a8c344b185cc5e0a972124940acddde602de85/src/scripts/linking/find-user-target.lua.example

  This script connects a source to a target based on the node.name
]]

local lutils = require("linking-utils")
log = Log.open_topic("s-linking")
local lu = require("luaunit")

---Try changing the order (target -> source instead of source -> target)
---if it doesn't work as expected
local MAPPINGS = {
  ["Brave"] = "sink_node.multimedia",
  ["Firefox"] = "sink_node.multimedia",
  ["ALSA plug-in [plexamp]"] = "sink_node.multimedia",
  ["BTAdapter"] = "sink_node.multimedia",
  ["Chromium input"] = "source_filter.rnnoise",
  ---Apply noise reduction to Google chrome media sound
  ["Google Chrome"] = "Filtered Headphones", -- will fallback to default if not available
  ["Chromium"] = "source_filter.ebur128_normalize", -- will fallback to default if not available
  ["Microsoft-edge"] = "Filtered Headphones", -- will fallback to default if not available
}

SimpleEventHook({
  name = "linking/auto-connect-ports",
  before = "linking/find-defined-target",
  interests = {
    EventInterest({
      Constraint({ "event.type", "=", "select-target" }),
    }),
  },
  execute = function(event)
    ---@diagnostic disable-next-line: unused-local
    local source, om, si, si_props, si_flags, target = lutils:unwrap_select_target_event(event)

    ---bypass the hook if the target is already picked up
    if target then
      return
    end

    ---@type string
    local TARGET = MAPPINGS[si_props["node.name"]]
    if not TARGET then
      return
    end

    local picked_target = om:lookup({ Constraint({ "node.name", "=", TARGET }) })

    if not picked_target then
      return
    end

    if not lutils.canLink(si_props, picked_target) then
      log:info(picked_target, "[custom] is not linkable")
      return
    end

    ---store the found target on the event,
    ---the next hooks will take care of linking
    event:set_data("target", picked_target)
  end,
}):register()
