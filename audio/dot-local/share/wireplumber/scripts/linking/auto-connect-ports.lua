--[[
  Thanks!
  https://gitlab.freedesktop.org/pipewire/wireplumber/-/blob/91a8c344b185cc5e0a972124940acddde602de85/src/scripts/linking/find-user-target.lua.example

  This script connects a source to a target based on the node.name
]]

local lutils = require("linking-utils")
log = Log.open_topic("s-linking")
-- local lu = require("luaunit")

---The order is: source -> sink
---SOURCE: You get audio from a source/capture (unless that source was marked as sink using media.class = Audio/Sink). You can then pass that audio
---to other sinks.
---SINK: You have to send audio to a sink (so the sink can output it to your speakers). Watch out for the media.class that converts
---these sinks/playbacks into sources.
local LOGICAL_SINKS = {
  multimedia = "capture.sink_node.multimedia",
  work = "capture.sink_node.work",
  ["music-production"] = "capture.sink_node.music-production",
}

local APP_TARGETS = {
  ---BTAdapter -> Physical output sink (monitor-only, keep it out of recording mix)
  ---BTAdapter (media.class = "Stream/Output/Audio")
  ---alsa_output.usb-Burr-Brown_from_TI_USB_Audio_CODEC-00.analog-stereo-output (media.class = "Audio/Sink")
  ["BTAdapter"] = { node = "alsa_output.usb-Burr-Brown_from_TI_USB_Audio_CODEC-00.analog-stereo-output" },
  ["Brave"] = { logical_sink = "multimedia" },
  ["Firefox"] = { logical_sink = "multimedia" },
  ["ALSA plug-in [plexamp]"] = { logical_sink = "multimedia" },
  ---Denoiser source -> chromium input source?
  ---Chromium input (media.class = "Stream/Input/Audio")
  ---source_filter.rnnoise (media.class = "Audio/Source")
  ["Chromium input"] = { node = "source_filter.rnnoise" },
  ---Mic source -> Denoiser source
  ---capture.source_filter.rnnoise (media.class = "Stream/Input/Audio" )
  ---Mic (media.class = "Audio/Source")
  ["capture.source_filter.rnnoise"] = { node = "Mic" },
  ---Chromium sink -> Work sink
  ---Chromium (media.class = "Stream/Output/Audio")
  ---capture.sink_node.work (media.class = "Audio/Sink")
  ["Chromium"] = { logical_sink = "work" }, -- will fallback to default if not available
  ---Youtube music sink -> Multimedia sink
  ---YouTube Music Desktop App (media.class = "Stream/Output/Audio")
  ---capture.sink_node.multimedia (media.class = "Audio/Sink")
  ["YouTube Music Desktop App"] = { logical_sink = "multimedia" },
}

local function resolve_target_name(target)
  if not target then
    return nil
  end

  if target.logical_sink then
    return LOGICAL_SINKS[target.logical_sink]
  end

  return target.node
end

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

    ---bypass the hook if the target is already picked up
    if target then
      return
    end

    local target_config = APP_TARGETS[si_props["node.name"]]
    local target_name = resolve_target_name(target_config)
    if not target_name then
      return
    end

    local picked_target = om:lookup({ Constraint({ "node.name", "=", target_name }) })

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
