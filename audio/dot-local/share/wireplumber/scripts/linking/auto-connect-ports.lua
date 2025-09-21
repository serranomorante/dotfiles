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
  ["Brave"] = "media-sink",
  ["Firefox"] = "media-sink",
  ["ALSA plug-in [plexamp]"] = "media-sink",
  ["BTAdapter"] = "media-sink",
  ["Chromium input"] = "rnnoise_source",
  ---Apply noise reduction to Google chrome media sound
  ["Google Chrome"] = "Filtered Headphones", -- will fallback to default if not available
  ["Chromium"] = "Filtered Headphones", -- will fallback to default if not available
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

    ---@type string
    local SOURCE = si_props["node.name"]

    ---bypass the hook if the target is already picked up
    if target then
      return
    end

    local TARGET = MAPPINGS[SOURCE]

    if TARGET == nil then
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
