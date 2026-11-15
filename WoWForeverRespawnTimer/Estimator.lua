-- Estimator: learns respawn delays from deaths and later sightings.
-- Pure logic: time and positions are passed in, no WoW API calls.
--
-- How a sample is learned: a creature dies (RecordDeath). Later a live
-- creature with the same npcID and a GUID we have never seen shows up near
-- that spot (RecordAlive). The gap between the two is one sample. It is an
-- upper bound, because the mob may have respawned before we noticed it.
local _, ns = ...
local Util = ns.Util

local Estimator = {}
Estimator.__index = Estimator
ns.Estimator = Estimator

Estimator.MIN_SAMPLE = 45      -- seconds; shorter gaps are a different mob
Estimator.MAX_SAMPLE = 2 * 3600 -- seconds; longer gaps are noise, deaths expire
-- Yards between the player's position at the death and at the sighting.
-- Player, not mob, positions: nameplates show mobs ~40 yd away, so allow slack.
Estimator.MATCH_RADIUS = 60
-- A death is dropped as a sample if the player spent over MAX_AWAY seconds
-- (or 20% of the gap, if less) farther than AWAY_RADIUS yards from it.
Estimator.AWAY_RADIUS = 100
Estimator.MAX_AWAY = 60
Estimator.MAX_SAMPLES = 20     -- kept per npcID and per area, oldest dropped first
Estimator.AREA_RADIUS = 50     -- yards; a death this close to an area joins it
Estimator.MAX_AREAS = 50       -- per npcID, oldest dropped first

-- store: persisted table (RespawnTimerDB.npcs), npcID -> {
--   samples = {...},  every sample for this npcID (fallback estimate)
--   areas = { { c, x, y, samples = {...} }, ... },  spawn spots, by death position
--   override = seconds,  manual value from /rst set
-- }
function Estimator.New(store)
	return setmetatable({
		store = store,
		deaths = {}, -- guid -> { npcID, t, pos, matched }, this session only
		seen = {},   -- guid -> true for every creature GUID seen alive or dead
	}, Estimator)
end

local function entry(self, npcID)
	local e = self.store[npcID]
	if not e then
		e = { samples = {} }
		self.store[npcID] = e
	end
	e.areas = e.areas or {}
	return e
end

local function push(list, value, max)
	list[#list + 1] = value
	if #list > max then table.remove(list, 1) end
end

-- The area nearest to pos within AREA_RADIUS, or nil.
local function nearestArea(e, pos)
	local best, bestDist
	for _, area in ipairs(e.areas or {}) do
		local dist = Util.Distance(area, pos)
		if dist and dist <= Estimator.AREA_RADIUS and (not bestDist or dist < bestDist) then
			best, bestDist = area, dist
		end
	end
	return best
end

-- Returns the area's index in e.areas and its sample count (for the log).
local function addToArea(e, pos, sample)
	local area = nearestArea(e, pos)
	if area then
		-- Move the area's centre toward the new position (running mean).
		local n = #area.samples
		area.x = (area.x * n + pos.x) / (n + 1)
		area.y = (area.y * n + pos.y) / (n + 1)
	else
		area = { c = pos.c, x = pos.x, y = pos.y, samples = {} }
		push(e.areas, area, Estimator.MAX_AREAS)
	end
	push(area.samples, sample, Estimator.MAX_SAMPLES)
	for i, a in ipairs(e.areas) do
		if a == area then return i, #area.samples end
	end
end

function Estimator:RecordDeath(guid, npcID, t, pos)
	self.seen[guid] = true
	if self.deaths[guid] then return end
	self.deaths[guid] = { npcID = npcID, t = t, pos = pos, matched = false }
	-- Forget deaths too old to ever produce a sample.
	for g, d in pairs(self.deaths) do
		if t - d.t > self.MAX_SAMPLE then self.deaths[g] = nil end
	end
end

-- Remembers a GUID without learning from it (e.g. a mob already in combat
-- when first seen is an add joining a fight, not a fresh respawn).
-- Returns true the first time a GUID is marked.
function Estimator:MarkSeen(guid)
	if self.seen[guid] then return false end
	self.seen[guid] = true
	return true
end

-- Called every dt seconds with the player's position. Time spent away from
-- (or unable to be placed relative to) a pending death is added up, so
-- RecordAlive can skip gaps inflated by the player leaving.
function Estimator:Tick(pos, dt)
	for _, d in pairs(self.deaths) do
		if not d.matched then
			local dist = pos and d.pos and Util.Distance(d.pos, pos)
			if not dist or dist > self.AWAY_RADIUS then d.awaySecs = (d.awaySecs or 0) + dt end
		end
	end
end

-- Returns the learned sample in seconds, the spawn area's index and its
-- sample count, or nil if nothing was learned. If the best match had the
-- player away too long, returns nil, "away", gap (the death is used up, nothing is stored).
function Estimator:RecordAlive(guid, npcID, t, pos)
	if self.seen[guid] then return nil end
	self.seen[guid] = true
	local best, bestDist
	for _, d in pairs(self.deaths) do
		local gap = t - d.t
		if not d.matched and d.npcID == npcID and gap >= self.MIN_SAMPLE and gap <= self.MAX_SAMPLE then
			local dist = Util.Distance(d.pos, pos)
			if dist and dist <= self.MATCH_RADIUS and (not bestDist or dist < bestDist) then
				best, bestDist = d, dist
			end
		end
	end
	if not best then return nil end
	best.matched = true
	local sample = t - best.t
	if (best.awaySecs or 0) > math.min(self.MAX_AWAY, 0.2 * sample) then return nil, "away", sample end
	local e = entry(self, npcID)
	push(e.samples, sample, self.MAX_SAMPLES)
	local areaIndex, areaCount = addToArea(e, best.pos, sample)
	return sample, areaIndex, areaCount
end

-- Returns { seconds, n, scope } or nil when nothing is known. scope is
-- "manual" (/rst set), "area" (samples from the spawn spot nearest pos) or
-- "type" (all samples for this npcID, when no area near pos has any).
function Estimator:Estimate(npcID, pos)
	local e = self.store[npcID]
	if not e then return nil end
	if e.override then return { seconds = e.override, n = #e.samples, scope = "manual" } end
	local area = pos and nearestArea(e, pos)
	-- Typical value for this npcID; samples far from it are false matches.
	local reference = #e.samples >= 3 and Util.Median(e.samples) or nil
	if area and #area.samples > 0 then
		-- An area with enough samples is judged against itself, since camps
		-- can differ; a small one borrows the npcID-wide reference.
		local ref = #area.samples >= 3 and Util.Median(area.samples) or reference
		local median, n = Util.RobustMedian(area.samples, ref)
		if median then return { seconds = median, n = n, scope = "area" } end
	end
	local median, n = Util.RobustMedian(e.samples, reference)
	if not median then median, n = Util.Median(e.samples), #e.samples end
	if not median then return nil end
	return { seconds = median, n = n, scope = "type" }
end

-- For a corpse we saw die: { diedAgo, remaining } (remaining nil if no
-- estimate yet, negative if overdue). nil if we did not see it die.
function Estimator:Corpse(guid, now)
	local d = self.deaths[guid]
	if not d then return nil end
	local est = self:Estimate(d.npcID, d.pos)
	local diedAgo = now - d.t
	return { diedAgo = diedAgo, remaining = est and (est.seconds - diedAgo), estimate = est }
end

function Estimator:SetOverride(npcID, seconds)
	entry(self, npcID).override = seconds
end

function Estimator:Clear(npcID)
	self.store[npcID] = nil
end
