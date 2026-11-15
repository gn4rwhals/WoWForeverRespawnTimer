-- Tracker: watches target, mouseover and nameplate units, turns what it sees
-- into deaths and sightings for the Estimator. No combat log: Forever blocks it.
local _, ns = ...
local R, Util = ns.Readable, ns.Util

local Tracker = {}
ns.Tracker = Tracker

local lastDead, lastDeadCount = {}, 0 -- guid -> last readable dead state

-- The player's position in world yards, or nil if the game hides it
-- (instances). Uses the player because the add-on cannot read mob positions.
local function playerPos()
	local ok, x, y, _, instance = pcall(UnitPosition, "player")
	if not ok then return nil end
	x, y, instance = R(x), R(y), R(instance)
	if type(x) ~= "number" or type(y) ~= "number" or instance == nil then return nil end
	return { c = instance, x = x, y = y }
end
Tracker.PlayerPos = playerPos

-- Reads one unit. Returns guid, npcID, dead, or nil for players, pets,
-- secret values and anything that is not a creature.
function Tracker.Read(unit)
	if not R(UnitExists(unit)) then return nil end
	if R(UnitIsPlayer(unit)) or R(UnitPlayerControlled(unit)) then return nil end
	local guid = R(UnitGUID(unit))
	local npcID = Util.ParseNpcID(guid)
	if not npcID then return nil end
	local dead = R(UnitIsDead(unit))
	if dead == nil then return nil end
	return guid, npcID, dead
end

local function observe(unit)
	local guid, npcID, dead = Tracker.Read(unit)
	if not guid then return end
	local est, now = ns.estimator, GetServerTime()
	local prev = lastDead[guid]
	if prev == nil then
		lastDeadCount = lastDeadCount + 1
		if lastDeadCount > 2000 then lastDead, lastDeadCount = {}, 1 end
	end
	lastDead[guid] = dead
	if dead then
		-- Only a death we watched happen has a known time.
		if prev == false then
			est:RecordDeath(guid, npcID, now, playerPos())
			ns.Debug("death", npcID, R(UnitName(unit)) or "?")
		end
	elseif R(UnitAffectingCombat(unit)) then
		est:MarkSeen(guid)
	else
		local sample = est:RecordAlive(guid, npcID, now, playerPos())
		if sample then
			ns.Debug("learned", npcID, R(UnitName(unit)) or "?", Util.FormatDuration(sample))
		end
	end
end

local frame = CreateFrame("Frame")
frame:SetScript("OnEvent", function(_, event, unit)
	if event == "PLAYER_TARGET_CHANGED" then
		observe("target")
	elseif event == "UPDATE_MOUSEOVER_UNIT" then
		observe("mouseover")
	elseif event == "UNIT_HEALTH" then
		if unit == "target" or unit == "mouseover" or unit:find("^nameplate") then observe(unit) end
	else -- NAME_PLATE_UNIT_ADDED / NAME_PLATE_UNIT_REMOVED
		observe(unit)
	end
end)

table.insert(ns.onLoad, function()
	ns.estimator = ns.Estimator.New(ns.db.npcs)
	for _, e in ipairs({ "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "UNIT_HEALTH",
		"NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED" }) do
		frame:RegisterEvent(e)
	end
end)

-- Slash commands ------------------------------------------------------------

local function targetNpc()
	local guid, npcID = Tracker.Read("target")
	if not guid then ns.Print("target a creature first") end
	return npcID, R(UnitName("target")) or "?"
end

ns.commands.set = function(rest)
	local seconds = tonumber(rest)
	if not seconds or seconds <= 0 then return ns.Print("usage: /rst set <seconds>") end
	local npcID, name = targetNpc()
	if not npcID then return end
	ns.estimator:SetOverride(npcID, seconds)
	ns.Print(name .. " respawn set to " .. Util.FormatDuration(seconds))
end

ns.commands.clear = function()
	local npcID, name = targetNpc()
	if not npcID then return end
	ns.estimator:Clear(npcID)
	ns.Print(name .. " respawn data cleared")
end

ns.commands.status = function()
	local npcID, name = targetNpc()
	if not npcID then return end
	local est = ns.estimator:Estimate(npcID, playerPos())
	local e = ns.db.npcs[npcID]
	local list = {}
	for i, s in ipairs(e and e.samples or {}) do list[i] = Util.FormatDuration(s) end
	ns.Print(string.format("%s (npc %d): estimate %s, %d spawn areas, all samples [%s]", name, npcID,
		est and (Util.FormatDuration(est.seconds) .. " " .. est.scope) or "none",
		e and e.areas and #e.areas or 0, table.concat(list, ", ")))
end

ns.commands.debug = function()
	ns.db.debug = not ns.db.debug
	ns.Print("debug " .. (ns.db.debug and "ON (logged to SavedVariables)" or "OFF"))
end
