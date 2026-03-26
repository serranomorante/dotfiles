local devinfo = require("device-info-cache")

local INTEGRATED_DEVICE_NAME = "alsa_card.pci-0000_06_00.6"
local INTEGRATED_SPEAKERS_VOLUME = 0.9

SimpleEventHook({
  name = "device/set-integrated-speakers-default-volume",
  after = "device/apply-route-props",
  before = "device/apply-routes",
  interests = {
    EventInterest({
      Constraint({ "event.type", "=", "select-routes" }),
    }),
  },
  execute = function(event)
    local device = event:get_subject()

    if device.properties["device.name"] ~= INTEGRATED_DEVICE_NAME then
      return
    end

    local selected_routes = event:get_data("selected-routes") or Properties()
    if selected_routes:get_count() == 0 then
      return
    end

    local dev_info = devinfo:get_device_info(device)
    assert(dev_info)

    local new_selected_routes = {}

    for device_id, route_json in pairs(selected_routes) do
      local route = Json.Raw(route_json):parse()
      local route_info = devinfo.find_route_info(dev_info, route, false)
      local props = route.props or {}

      if route_info and route_info.direction == "Output" then
        props.channelVolumes = Json.Array({ INTEGRATED_SPEAKERS_VOLUME })
      elseif props.channelVolumes then
        props.channelVolumes = Json.Array(props.channelVolumes)
      end

      if props.channelMap then
        props.channelMap = Json.Array(props.channelMap)
      end

      if props.iec958Codecs then
        props.iec958Codecs = Json.Array(props.iec958Codecs)
      end

      new_selected_routes[device_id] = Json.Object({
        index = route.index,
        props = Json.Object(props),
      }):to_string()
    end

    event:set_data("selected-routes", new_selected_routes)
  end,
}):register()
