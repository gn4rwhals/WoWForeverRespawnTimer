-- Loads add-on files the way WoW does: each file gets (addonName, ns).
local helper = {}

function helper.load(...)
	local ns = {}
	for _, name in ipairs({ ... }) do
		local chunk = assert(loadfile("WoWForeverRespawnTimer/" .. name .. ".lua"))
		chunk("WoWForeverRespawnTimer", ns)
	end
	return ns
end

return helper
