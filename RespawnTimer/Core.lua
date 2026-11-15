-- Core: add-on namespace, saved variables and the /rst slash command.
-- Every file in the TOC receives the same two values: the add-on folder name
-- and a private table (ns) shared between our files without using globals.
local addonName, ns = ...

-- Forever (like Retail 12.x) can hand add-ons "secret values" from unit APIs.
-- Comparing, concatenating or indexing a secret throws an error, so every
-- unit read goes through Readable: a secret value comes back as nil.
function ns.IsSecret(v)
	return v ~= nil and issecretvalue ~= nil and issecretvalue(v) and true or false
end

function ns.Readable(v)
	if ns.IsSecret(v) then return nil end
	return v
end

function ns.Print(...)
	print("|cff33ff99RespawnTimer|r:", ...)
end

-- Debug log: with /rst debug on, lines print to chat and are kept in
-- RespawnTimerDB.log, which the game writes to
-- WTF\Account\<account>\SavedVariables\RespawnTimer.lua on /reload or logout.
-- ns.Log always records; ns.Debug only when debug is on.
function ns.Log(...)
	if not ns.db then return end
	ns.Print(...)
	ns.db.log = ns.db.log or {}
	local parts = {}
	for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
	table.insert(ns.db.log, date("%H:%M:%S ") .. table.concat(parts, " "))
	if #ns.db.log > 3000 then table.remove(ns.db.log, 1) end
end

function ns.Debug(...)
	if ns.db and ns.db.debug then ns.Log(...) end
end

-- Functions other files want run once saved variables are ready.
ns.onLoad = {}

-- Slash command handlers, added by other files: ns.commands.name = function(rest)
ns.commands = {}

SLASH_RESPAWNTIMER1 = "/rst"
SlashCmdList.RESPAWNTIMER = function(msg)
	local cmd, rest = (msg or ""):match("^(%S*)%s*(.-)$")
	local handler = ns.commands[cmd:lower()]
	if handler then
		handler(rest)
	else
		local names = {}
		for name in pairs(ns.commands) do names[#names + 1] = name end
		table.sort(names)
		ns.Print("commands: /rst " .. table.concat(names, " | /rst "))
	end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, name)
	if name ~= addonName then return end
	-- SavedVariables are only loaded once our ADDON_LOADED fires.
	RespawnTimerDB = RespawnTimerDB or { version = 1, npcs = {} }
	ns.db = RespawnTimerDB
	ns.db.probeLog = nil -- left over from the step 1 probe
	for _, fn in ipairs(ns.onLoad) do fn() end
	self:UnregisterEvent("ADDON_LOADED")
end)
