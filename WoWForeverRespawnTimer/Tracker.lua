-- Tracker: watches target, mouseover and nameplate units, turns what it sees
-- into deaths and sightings for the Estimator. No combat log: Forever blocks it.
local _, ns = ...
local R, Util = ns.Readable, ns.Util

local Tracker = {}
ns.Tracker = Tracker

local lastDead, lastDeadCount = {}, 0 -- guid -> last readable dead state
local petChecked = {} -- npcID -> true once checked for an owner this session, or next retry time

local zoneCache = {} -- mapID -> zone map ID, this session

-- GetBestMapForUnit can return a cave or building sub-map: walk up to the
-- Zone map. Falls back to the original id when none is found.
local function zoneOf(id)
	if zoneCache[id] then return zoneCache[id] end
	local zone, cur = id, id
	local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone
	for _ = 1, 5 do
		if not (zoneType and C_Map.GetMapInfo) then break end
		local ok, info = pcall(C_Map.GetMapInfo, cur)
		info = ok and R(info) or nil
		if type(info) ~= "table" then break end
		local mapType, parent = R(info.mapType), R(info.parentMapID)
		if mapType == zoneType then
			zone = cur
			break
		end
		if type(parent) ~= "number" or parent == 0 then break end
		cur = parent
	end
	zoneCache[id] = zone
	return zone
end

-- The player's position in world yards, or nil if the game hides it
-- (instances). Uses the player because the add-on cannot read mob positions.
local function playerPos()
	local ok, x, y, _, instance = pcall(UnitPosition, "player")
	if not ok then return nil end
	x, y, instance = R(x), R(y), R(instance)
	if type(x) ~= "number" or type(y) ~= "number" or instance == nil then return nil end
	-- Zone = map ID (e.g. 1434 Stranglethorn); nil when unavailable.
	local zone
	if C_Map and C_Map.GetBestMapForUnit then
		local okZone, id = pcall(C_Map.GetBestMapForUnit, "player")
		id = okZone and R(id) or nil
		if type(id) == "number" then zone = zoneOf(id) end
	end
	return { c = instance, x = x, y = y, zone = zone }
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
	if ns.Paused() then return end
	local guid, npcID, dead = Tracker.Read(unit)
	if not guid then return end
	local est, now = ns.estimator, GetServerTime()
	-- Unreadable tooltips are retried at most every 10s, not on every health event.
	local checked = petChecked[npcID]
	if checked ~= true and now >= (checked or 0) and C_TooltipInfo and C_TooltipInfo.GetUnit then
		local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
		petChecked[npcID] = (ok and ns.CheckPet(unit, npcID, data)) or now + 10
	end
	if est:IsPet(npcID) then return end
	ns.CheckClass(unit, npcID)
	local prev = lastDead[guid]
	if prev == nil then
		lastDeadCount = lastDeadCount + 1
		if lastDeadCount > 2000 then lastDead, lastDeadCount = {}, 1 end
	end
	lastDead[guid] = dead
	if dead then
		-- Only a death we watched happen has a known time.
		if prev == false then
			-- Re-check the tooltip once per death: quest lines may have appeared
			-- since the first check (a quest taken later).
			local known = est:Entry(npcID)
			if not (known and known.quest) and C_TooltipInfo and C_TooltipInfo.GetUnit then
				local ok, data = pcall(C_TooltipInfo.GetUnit, unit)
				if ok then ns.CheckPet(unit, npcID, data) end
				if est:IsPet(npcID) then return end
			end
			local pos = playerPos()
			est:RecordDeath(guid, npcID, now, pos)
			ns.Debug("death", npcID, R(UnitName(unit)) or "?",
				pos and string.format("@%d:%d,%d", pos.c, pos.x, pos.y) or "@unknown")
		end
	elseif R(UnitAffectingCombat(unit)) then
		if est:IsSeen(guid) then return end -- skip playerPos() on every health event
		local bound = est:RecordBound(guid, npcID, now, playerPos())
		if bound then
			ns.Debug("bound", npcID, R(UnitName(unit)) or "?", "<=", Util.FormatDuration(bound))
		else
			ns.Debug("add", npcID, R(UnitName(unit)) or "?")
		end
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
	ns.estimator = ns.Estimator.New(ns.db.npcs, ns.db.zones)
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
	local e = ns.estimator:Entry(npcID)
	if e and e.pet then return ns.Print(string.format("%s (npc %d): pet, ignored", name, npcID)) end
	local list = {}
	for i, s in ipairs(e and e.samples or {}) do list[i] = Util.FormatDuration(s) end
	local bounds = {}
	for i, b in ipairs(e and e.bounds or {}) do bounds[i] = Util.FormatDuration(b) end
	local pos = playerPos()
	local pool = pos and pos.zone and ns.db.zones[pos.zone]
	ns.Print(string.format("%s (npc %d): estimate %s, %d spawn areas, all samples [%s], bounds [%s]", name, npcID,
		est and (Util.FormatDuration(est.seconds) .. " " .. est.scope) or "none",
		e and e.areas and #e.areas or 0, table.concat(list, ", "), table.concat(bounds, ", ")))
	ns.Print(string.format("class %s, quest %s, zone %s pool %d samples", e and e.class or "?",
		e and e.quest and "yes" or "no", pos and pos.zone or "?", pool and #pool.samples or 0))
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
