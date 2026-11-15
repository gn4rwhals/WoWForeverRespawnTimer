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
	if est:IsPet(npcID) then return nil end
	if not dead then
		local e = est:Estimate(npcID, pos)
		return e and ("Typical respawn " .. estimateText(e)) or nil
	end
	local corpse = est:Corpse(guid, now)
	if corpse then
		local died = "Died " .. fmt(corpse.diedAgo) .. " ago"
		if corpse.estimate and corpse.estimate.scope == "bound" then
			local left = corpse.estimate.seconds - corpse.diedAgo
			if left <= 0 then return died .. ", respawn due (upper bound passed)" end
			return died .. ", respawns within at most " .. fmt(left)
		end
		if not corpse.remaining then return died .. ", respawn: no data yet" end
		if corpse.remaining <= 0 then return died .. ", respawn due" end
		return died .. ", respawn in ~" .. fmt(corpse.remaining)
	end
	local e = est:Estimate(npcID, pos)
	return e and ("Respawn " .. estimateText(e)) or "Respawn: no data yet"
end

-- Turns a pet title format ("%s's Pet") into a Lua pattern, or nil when it
-- has no %s. "%%" is a literal percent sign.
local function formatPattern(format)
	local out, hasName, i = {}, false, 1
	while i <= #format do
		local c, n = format:sub(i, i), format:sub(i + 1, i + 1)
		if c == "%" and n == "s" then
			out[#out + 1], hasName, i = "(.+)", true, i + 2
		elseif c == "%" and n == "%" then
			out[#out + 1], i = "%%", i + 2
		else
			out[#out + 1], i = c:find("%p") and ("%" .. c) or c, i + 1
		end
	end
	return hasName and ("^" .. table.concat(out) .. "$") or nil
end

-- lines: { { text, type, n }, ... } (readable, n = position in the tooltip).
-- opts: ownerType (line type of the owner line), skipTypes (line types to
-- ignore), formats (pet title formats). Returns the owner's name and how it
-- was found ("type" or "text"), or nil.
function ns.PetOwner(lines, opts)
	if opts.ownerType ~= nil then
		for _, l in ipairs(lines) do
			if l.type == opts.ownerType and l.n <= 3 then return l.text, "type" end
		end
	end
	local skip = {}
	for _, t in ipairs(opts.skipTypes) do skip[t] = true end
	for _, format in ipairs(opts.formats) do
		local pattern = formatPattern(format)
		for _, l in ipairs(pattern and lines or {}) do
			if l.n == 2 and not skip[l.type] then
				local owner = l.text:match(pattern)
				if owner then return owner, "text" end
			end
		end
	end
	return nil
end

-- Tooltip data -> readable { text, type, n } entries, dropping secret or odd lines.
function ns.PetLines(data)
	local out = {}
	local lines = type(data) == "table" and ns.Readable(data.lines)
	if type(lines) ~= "table" then return out end
	for i, line in ipairs(lines) do
		if type(line) == "table" and not ns.IsSecret(line) then
			local text = ns.Readable(line.leftText)
			if type(text) == "string" then
				out[#out + 1] = { text = text, type = ns.Readable(line.type), n = i }
			end
		end
	end
	return out
end

local PET_GLOBALS = { "UNITNAME_TITLE_PET", "UNITNAME_TITLE_GUARDIAN", "UNITNAME_TITLE_MINION",
	"UNITNAME_TITLE_CREATION", "UNITNAME_TITLE_COMPANION", "UNITNAME_TITLE_CHARM" }
local QUEST_TYPES = { "QuestTitle", "QuestObjective", "QuestPlayer" }

-- Marks npcID as a pet when its tooltip data says it has an owner. Returns
-- true if at least one line was readable (so the check was meaningful).
function ns.CheckPet(unit, npcID, data)
	local T = Enum.TooltipDataLineType
	local opts = { ownerType = T and T.UnitOwner, skipTypes = {}, formats = {} }
	for _, name in ipairs(QUEST_TYPES) do
		if T and T[name] ~= nil then opts.skipTypes[#opts.skipTypes + 1] = T[name] end
	end
	for _, name in ipairs(PET_GLOBALS) do
		if type(_G[name]) == "string" then opts.formats[#opts.formats + 1] = _G[name] end
	end
	local lines = ns.PetLines(data)
	local owner, how = ns.PetOwner(lines, opts)
	if owner and ns.estimator:MarkPet(npcID) then
		ns.Debug("pet", npcID, ns.Readable(UnitName(unit)) or "?", "(owner " .. owner .. ", via " .. how .. ")")
	end
	-- Done only once the owner line (line 2) was readable, or an owner was found.
	if owner then return true end
	for _, l in ipairs(lines) do
		if l.n == 2 then return true end
	end
	return false
end

TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
	if tooltip ~= GameTooltip or not ns.estimator then return end
	local _, unit = tooltip:GetUnit()
	if not unit then return end
	local guid, npcID, dead = ns.Tracker.Read(unit)
	if not guid then return end
	ns.CheckPet(unit, npcID, data)
	local line = ns.TooltipLine(guid, npcID, dead, GetServerTime(), ns.Tracker.PlayerPos())
	if line then tooltip:AddLine(line, COLOR[1], COLOR[2], COLOR[3]) end
end)
