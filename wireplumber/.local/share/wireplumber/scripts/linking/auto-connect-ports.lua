-- WirePlumber
--
-- Copyright © 2022 Collabora Ltd.
--
-- SPDX-License-Identifier: MIT
--
-- example of a user injectible hook to link a node to a custom target

--[[
Thanks!
https://gitlab.freedesktop.org/pipewire/wireplumber/-/blob/91a8c344b185cc5e0a972124940acddde602de85/src/scripts/linking/find-user-target.lua.example
]]
--

local putils = require("linking-utils")
local cutils = require("common-utils")
log = Log.open_topic("s-linking")

-- function findLinkable(si)
-- 	local si_props = si.properties
-- 	local target_direction = cutils.getTargetDirection(si_props)
-- 	local def_node_id = cutils.getDefaultNode
--
--   return cutils.get_object_manager ("session-item"):lookup {
--     type = "SiLinkable",
--     Constraint { "item.factory.name", "c", "si-audio-adapter", "si-node" },
--     Constraint { "node.id", "=", tostring (def_node_id) }
--   }
-- end

local APP_TO_OUTPUT = {
	["Brave"] = "media-sink",
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
		-- local luaunit = require("luaunit")
		local source, om, si, si_props, si_flags, target = putils:unwrap_select_target_event(event)

		-- print("## si_props: " .. luaunit.prettystr(si_props))
		-- print("## si_flags: " .. luaunit.prettystr(si_flags))
		-- print("## target: " .. luaunit.prettystr(target))
		print('## node name: ' .. si_props["node.name"])

		-- bypass the hook if the target is already picked up
		if target then
			return
		end

		log:info(si, "in find-user-target")

		local media_sink_si = om:lookup({ Constraint({ "node.name", "=", APP_TO_OUTPUT[si_props["node.name"]] }) })

		-- print("## metadata: " .. luaunit.prettystr(media_sink_si["properties"]))

		-- implement logic here to find a suitable target

		-- store the found target on the event,
		-- the next hooks will take care of linking
		event:set_data("target", media_sink_si)
	end,
}):register()
