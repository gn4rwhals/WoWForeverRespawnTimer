-- Util: small pure helpers. No WoW API calls, so busted can test them.
local _, ns = ...

local Util = {}
ns.Util = Util

-- "Creature-0-4372-0-17-299-0000123456" -> 299. Splits on "-" without
-- assuming digits, since Forever obfuscates the server and spawn fields.
-- Returns nil for players, pets, objects or anything unparsable.
function Util.ParseNpcID(guid)
	if type(guid) ~= "string" then return nil end
	local parts = {}
	for part in guid:gmatch("[^-]+") do parts[#parts + 1] = part end
	if parts[1] ~= "Creature" and parts[1] ~= "Vehicle" then return nil end
	return tonumber(parts[6])
end

-- 45 -> "45s", 125 -> "2m 05s", 3720 -> "1h 02m". Negative counts as 0.
function Util.FormatDuration(seconds)
	seconds = math.max(0, math.floor(seconds + 0.5))
	if seconds < 60 then return seconds .. "s" end
	if seconds < 3600 then
		return string.format("%dm %02ds", math.floor(seconds / 60), seconds % 60)
	end
	return string.format("%dh %02dm", math.floor(seconds / 3600), math.floor(seconds % 3600 / 60))
end

-- Positions are { c = continentID, x = yards, y = yards }. Returns yards, or
-- nil when either is missing or they are on different continents.
function Util.Distance(a, b)
	if not (a and b) or a.c ~= b.c then return nil end
	local dx, dy = a.x - b.x, a.y - b.y
	return math.sqrt(dx * dx + dy * dy)
end

function Util.Median(list)
	local n = #list
	if n == 0 then return nil end
	local sorted = {}
	for i = 1, n do sorted[i] = list[i] end
	table.sort(sorted)
	if n % 2 == 1 then return sorted[(n + 1) / 2] end
	return (sorted[n / 2] + sorted[n / 2 + 1]) / 2
end

-- Median that ignores values below 0.5x the full-list median (a different
-- mob of the same type, seen early). Lists under 3 use the plain median.
-- Returns the median and how many values it used.
function Util.RobustMedian(list)
	local median = Util.Median(list)
	if not median or #list < 3 then return median, #list end
	local kept = {}
	for _, v in ipairs(list) do
		if v >= median * 0.5 then kept[#kept + 1] = v end
	end
	return Util.Median(kept), #kept
end
