-- Tooltip: adds a respawn line to the unit tooltip on mouseover.
local _, ns = ...
local Util = ns.Util
local fmt = Util.FormatDuration

local COLOR = { 0.6, 0.8, 1 }

local function estimateText(est)
	if est.scope == "manual" then return "~" .. fmt(est.seconds) .. " (manual)" end
	if est.scope == "bound" then return "at most " .. fmt(est.seconds) .. " (upper bound, " .. est.n .. " kills)" end
	local samples = est.n .. (est.n == 1 and " sample" or " samples")
	if est.scope == "area" then return "~" .. fmt(est.seconds) .. " (" .. samples .. " here)" end
	return "~" .. fmt(est.seconds) .. " (" .. samples .. ", other spots)"
end

-- Returns the line to show, or nil to show nothing. pos is the player's
-- position, used to pick the nearest spawn area's estimate.
function ns.TooltipLine(guid, npcID, dead, now, pos)
	local est = ns.estimator
	if not dead then
		local e = est:Estimate(npcID, pos)
		return e and ("Typical respawn " .. estimateText(e)) or nil
	end
	local corpse = est:Corpse(guid, now)
	if corpse then
		local died = "Died " .. fmt(corpse.diedAgo) .. " ago"
		if corpse.estimate and corpse.estimate.scope == "bound" then
			return died .. ", respawns within at most " .. fmt(corpse.estimate.seconds)
		end
		if not corpse.remaining then return died .. ", respawn: no data yet" end
		if corpse.remaining <= 0 then return died .. ", respawn due" end
		return died .. ", respawn in ~" .. fmt(corpse.remaining)
	end
	local e = est:Estimate(npcID, pos)
	return e and ("Respawn " .. estimateText(e)) or "Respawn: no data yet"
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
	if tooltip ~= GameTooltip or not ns.estimator then return end
	local _, unit = tooltip:GetUnit()
	if not unit then return end
	local guid, npcID, dead = ns.Tracker.Read(unit)
	if not guid then return end
	local line = ns.TooltipLine(guid, npcID, dead, GetServerTime(), ns.Tracker.PlayerPos())
	if line then tooltip:AddLine(line, COLOR[1], COLOR[2], COLOR[3]) end
end)
