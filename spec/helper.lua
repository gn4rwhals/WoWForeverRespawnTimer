-- Loads add-on files the way WoW does: each file gets (addonName, ns).
local helper = {}

function helper.load(...)
	local ns = {}
	for _, name in ipairs({ ... }) do
		local chunk = assert(loadfile("RespawnTimer/" .. name .. ".lua"))
		chunk("RespawnTimer", ns)
	end
	return ns
end

return helper
