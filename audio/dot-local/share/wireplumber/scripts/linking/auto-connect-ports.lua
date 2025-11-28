--[[
  Thanks!
  https://gitlab.freedesktop.org/pipewire/wireplumber/-/blob/91a8c344b185cc5e0a972124940acddde602de85/src/scripts/linking/find-user-target.lua.example

  This script connects a source to a target based on the node.name
]]

local lutils = require("linking-utils")
log = Log.open_topic("s-linking")
local lu = require("luaunit")

---The order is: source -> sink
---SOURCE: You get audio from a source/capture (unless that source was marked as sink using media.class = Audio/Sink). You can then pass that audio
---to other sinks.
---SINK: You have to send audio to a sink (so the sink can output it to your speakers). Watch out for the media.class that converts
---these sinks/playbacks into sources.
local MAPPINGS = {
  ---BTAdapter -> Multimedia sink
  ---BTAdapter (media.class = "Stream/Output/Audio")
  ---capture.sink_node.multimedia (media.class = "Audio/Sink")
  ["BTAdapter"] = "capture.sink_node.multimedia",
  ["Brave"] = "capture.sink_node.multimedia",
  ["Firefox"] = "capture.sink_node.multimedia",
  ["ALSA plug-in [plexamp]"] = "capture.sink_node.multimedia",
  ---Denoiser source -> chromium input source?
  ---Chromium input (media.class = "Stream/Input/Audio")
  ---source_filter.rnnoise (media.class = "Audio/Source")
  ["Chromium input"] = "source_filter.rnnoise",
  ---Mic source -> Denoiser source
  ---capture.source_filter.rnnoise (media.class = "Stream/Input/Audio" )
  ---Mic (media.class = "Audio/Source")
  ["capture.source_filter.rnnoise"] = "Mic",
  ---Chromium sink -> Normalizer sink
  ---Chromium (media.class = "Stream/Output/Audio")
  ---capture.source_filter.ebur128_normalize (media.class = "Audio/Sink")
  ["Chromium"] = "capture.source_filter.ebur128_normalize", -- will fallback to default if not available
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
