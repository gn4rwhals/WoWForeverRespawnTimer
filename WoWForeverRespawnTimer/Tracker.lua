-- Tracker: watches target, mouseover and nameplate units, turns what it sees
-- into deaths and sightings for the Estimator. No combat log: Forever blocks it.
local _, ns = ...
local R, Util = ns.Readable, ns.Util

local Tracker = {}
ns.Tracker = Tracker

local lastDead, lastDeadCount = {}, 0 -- guid -> last readable dead state
local petChecked = {} -- npcID -> true once checked for an owner this session

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
	if not petChecked[npcID] and C_TooltipInfo and C_TooltipInfo.GetUnit then
		local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
		if ok and ns.CheckPet(unit, npcID, data) then petChecked[npcID] = true end
	end
	if est:IsPet(npcID) then return end
	local prev = lastDead[guid]
	if prev == nil then
		lastDeadCount = lastDeadCount + 1
		if lastDeadCount > 2000 then lastDead, lastDeadCount = {}, 1 end
	end
	lastDead[guid] = dead
	if dead then
		-- Only a death we watched happen has a known time.
		if prev == false then
			local pos = playerPos()
			est:RecordDeath(guid, npcID, now, pos)
			ns.Debug("death", npcID, R(UnitName(unit)) or "?",
				pos and string.format("@%d:%d,%d", pos.c, pos.x, pos.y) or "@unknown")
		end
	elseif R(UnitAffectingCombat(unit)) then
		if est:MarkSeen(guid) then ns.Debug("add", npcID, R(UnitName(unit)) or "?") end
	else
		local sample, areaIndex, areaCount = est:RecordAlive(guid, npcID, now, playerPos())
		if not sample and areaIndex == "away" then
			ns.Debug("skipped", npcID, R(UnitName(unit)) or "?", Util.FormatDuration(areaCount), "(away)")
		elseif sample then
			ns.Debug("learned", npcID, R(UnitName(unit)) or "?", Util.FormatDuration(sample),
				string.format("area#%d (%d samples)", areaIndex, areaCount))
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
	local failed, last = false, nil
	C_Timer.NewTicker(5, function()
		local now = GetServerTime()
		local dt = last and now - last or 5
		last = now
		local ok, err = pcall(function() ns.estimator:Tick(playerPos(), dt) end)
		if not ok and not failed then
			failed = true
			ns.Log("TICK ERROR " .. tostring(err))
		end
	end)
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
	if ns.estimator:IsPet(npcID) then return ns.Print(name .. " is a pet, ignored (/rst clear to undo)") end
	ns.estimator:SetOverride(npcID, seconds)
	ns.Print(name .. " respawn set to " .. Util.FormatDuration(seconds))
end

ns.commands.clear = function()
	local npcID, name = targetNpc()
	if not npcID then return end
	ns.estimator:Clear(npcID)
	petChecked[npcID] = nil
	ns.Print(name .. " respawn data cleared")
end

ns.commands.status = function()
	local npcID, name = targetNpc()
	if not npcID then return end
	local est = ns.estimator:Estimate(npcID, playerPos())
	local e = ns.db.npcs[npcID]
	if e and e.pet then return ns.Print(string.format("%s (npc %d): pet, ignored", name, npcID)) end
	local list = {}
	for i, s in ipairs(e and e.samples or {}) do list[i] = Util.FormatDuration(s) end
	ns.Print(string.format("%s (npc %d): estimate %s, %d spawn areas, all samples [%s]", name, npcID,
		est and (Util.FormatDuration(est.seconds) .. " " .. est.scope) or "none",
		e and e.areas and #e.areas or 0, table.concat(list, ", ")))
end

-- Test notes: always logged, even with debug off. See docs/testing.
ns.commands.note = function(rest)
	if rest == "" then return ns.Print("usage: /rst note <text>") end
	ns.Log("NOTE " .. rest)
end

ns.commands.log = function()
	local log = ns.db.log or {}
	ns.Print("log: " .. #log .. " lines (debug " .. (ns.db.debug and "ON" or "OFF") .. ")")
	for i = math.max(1, #log - 4), #log do ns.Print(log[i]) end
end

ns.commands.debug = function()
	ns.db.debug = not ns.db.debug
	ns.Print("debug " .. (ns.db.debug and "ON (logged to SavedVariables)" or "OFF"))
end
