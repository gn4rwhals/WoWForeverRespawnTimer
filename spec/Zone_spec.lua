local helper = require("spec.helper")

local Z = { c = 0, x = 100, y = 100, zone = 1434 }

local function new()
	local ns = helper.load("Util", "Estimator")
	local store, zones = {}, {}
	return ns.Estimator.New(store, zones), store, zones
end

-- Kills npcID once and sees it respawn after gap seconds, at pos.
local n = 0
local function kill(e, npcID, gap, pos)
	n = n + 1
	local t = n * 10000
	e:RecordDeath("d" .. n, npcID, t, pos or Z)
	return e:RecordAlive("a" .. n, npcID, t + gap, pos or Z)
end

local function feed(e, gaps)
	for _, g in ipairs(gaps) do kill(e, 1, g) end
end

describe("Estimator zone pool", function()
	it("feeds from a normal non-quest mob", function()
		local e, _, zones = new()
		e:SetClass(1, "normal")
		kill(e, 1, 300)
		assert.are.same({ 300 }, zones[1434].samples)
	end)

	it("does not feed from rare, elite, unknown class, quest or pet", function()
		local e, _, zones = new()
		e:SetClass(2, "rare")
		e:SetClass(3, "elite")
		e:SetClass(5, "normal")
		e:MarkQuest(5)
		kill(e, 2, 300)
		kill(e, 3, 300)
		kill(e, 4, 300) -- class unknown
		kill(e, 5, 300)
		e:MarkPet(6)
		kill(e, 6, 300)
		assert.is_nil(zones[1434])
	end)

	it("does not feed from bounds, away skips or a death without a zone", function()
		local e, _, zones = new()
		e:SetClass(1, "normal")
		e:RecordDeath("d", 1, 0, Z)
		e:RecordBound("b", 1, 500, Z)
		assert.is_nil(zones[1434])
		e:RecordDeath("d2", 1, 2000, Z)
		e:Tick(nil, 200)
		assert.are.equal("away", select(2, e:RecordAlive("a2", 1, 2300, Z)))
		assert.is_nil(zones[1434])
		kill(e, 1, 300, { c = 0, x = 100, y = 100 })
		assert.is_nil(zones[1434])
	end)

	it("caps the pool and drops the oldest", function()
		local e, _, zones = new()
		e:SetClass(1, "normal")
		for i = 1, 101 do kill(e, 1, 200 + i) end
		assert.are.equal(100, #zones[1434].samples)
		assert.are.equal(202, zones[1434].samples[1])
	end)

	it("works without a zones table", function()
		local ns = helper.load("Util", "Estimator")
		local e = ns.Estimator.New({})
		e:SetClass(1, "normal")
		e:RecordDeath("d", 1, 0, Z)
		assert.are.equal(300, e:RecordAlive("a", 1, 300, Z))
		assert.is_nil(e:Estimate(9, Z))
	end)
end)

describe("Estimator zone fallback", function()
	it("needs 3 pool samples and only applies when the npc has nothing", function()
		local e = new()
		e:SetClass(1, "normal")
		feed(e, { 300, 320 })
		e:SetClass(9, "normal")
		assert.is_nil(e:Estimate(9, Z)) -- only 2 pool samples
		kill(e, 1, 310)
		assert.are.same({ seconds = 310, n = 3, scope = "zone" }, e:Estimate(9, Z))
		-- A normal mob with no data qualifies.
		e:SetClass(8, "normal")
		assert.are.equal("zone", e:Estimate(8, Z).scope)
		-- Own data wins.
		e:SetOverride(8, 99)
		assert.are.equal("manual", e:Estimate(8, Z).scope)
		kill(e, 7, 500)
		assert.are.equal("area", e:Estimate(7, Z).scope)
	end)

	it("keeps bounds ahead of the zone", function()
		local e = new()
		e:SetClass(1, "normal")
		feed(e, { 300, 320, 310 })
		e:SetClass(9, "normal")
		e:RecordDeath("x1", 9, 0, Z)
		e:RecordBound("y1", 9, 600, Z)
		e:RecordDeath("x2", 9, 2000, Z)
		e:RecordBound("y2", 9, 2600, Z)
		assert.are.equal("bound", e:Estimate(9, Z).scope)
	end)

	it("offers nothing for a rare, quest npc, pet or nil zone", function()
		local e = new()
		e:SetClass(1, "normal")
		feed(e, { 300, 320, 310 })
		e:SetClass(2, "rare")
		e:SetClass(3, "normal")
		e:MarkQuest(3)
		e:MarkQuest(4) -- quest flag before the class is known
		e:MarkPet(5)
		e:SetClass(9, "normal")
		assert.is_nil(e:Estimate(2, Z))
		assert.is_nil(e:Estimate(6, Z)) -- class never read (could be a rare)
		assert.is_nil(e:Estimate(7, Z)) -- no entry at all
		assert.is_nil(e:Estimate(3, Z))
		assert.is_nil(e:Estimate(4, Z))
		assert.is_nil(e:Estimate(5, Z))
		assert.is_nil(e:Estimate(9, { c = 0, x = 100, y = 100 }))
		assert.is_nil(e:Estimate(9))
	end)

	it("drops a far outlier in the pool", function()
		local e = new()
		e:SetClass(1, "normal")
		feed(e, { 300, 310, 320, 330, 3000 })
		e:SetClass(9, "normal")
		assert.are.same({ seconds = 315, n = 4, scope = "zone" }, e:Estimate(9, Z))
	end)
end)

describe("Estimator class and quest flags", function()
	it("sets class once and keeps the quest flag", function()
		local e, store = new()
		assert.is_true(e:SetClass(1, "normal"))
		assert.is_false(e:SetClass(1, "rare"))
		assert.are.equal("normal", store[1].class)
		assert.is_true(e:MarkQuest(1))
		assert.is_false(e:MarkQuest(1))
		assert.is_true(store[1].quest)
	end)

	it("creates a flag entry without areas", function()
		local e, store = new()
		e:SetClass(1, "normal")
		assert.are.same({ samples = {}, class = "normal" }, store[1])
	end)

	it("keeps class and quest across Clear, and the pool is unchanged", function()
		local e, store, zones = new()
		e:SetClass(1, "normal")
		e:MarkQuest(1)
		e:SetOverride(1, 50)
		e:Clear(1)
		assert.are.same({ samples = {}, class = "normal", quest = true }, store[1])
		kill(e, 1, 300)
		assert.is_nil(zones[1434])
		e:SetClass(2, "rare")
		e:Clear(2)
		assert.are.equal("rare", store[2].class)
		e:MarkQuest(3)
		e:Clear(3)
		assert.is_true(store[3].quest)
	end)

	it("does not create an entry for a pet", function()
		local e, store = new()
		e:MarkPet(6)
		assert.is_false(e:SetClass(6, "normal"))
		assert.is_false(e:MarkQuest(6))
		assert.are.same({ pet = true }, store[6])
	end)
end)

describe("HasQuestLine", function()
	local T = { QuestTitle = 17, QuestObjective = 8, QuestPlayer = 18, NormalText = 0 }
	local function ns()
		_G.Enum = { TooltipDataType = { Unit = 2 }, TooltipDataLineType = T }
		_G.TooltipDataProcessor = { AddTooltipPostCall = function() end }
		return helper.load("Util", "Estimator", "Tooltip")
	end

	it("detects quest line types", function()
		local n = ns()
		assert.is_true(n.HasQuestLine({ { text = "a", type = 0, n = 1 }, { text = "b", type = 8, n = 3 } }, T))
		assert.is_true(n.HasQuestLine({ { text = "a", type = 17, n = 1 } }, T))
		assert.is_true(n.HasQuestLine({ { text = "a", type = 18, n = 1 } }, T))
		assert.is_false(n.HasQuestLine({ { text = "a", type = 0, n = 1 } }, T))
		assert.is_false(n.HasQuestLine({}, T))
		assert.is_false(n.HasQuestLine({ { text = "a", type = 17, n = 1 } }, nil))
		-- A missing enum value is skipped, not matched against nil types.
		assert.is_false(n.HasQuestLine({ { text = "a", n = 1 } }, { NormalText = 0 }))
	end)

	it("flags the npc through CheckPet and stays flagged", function()
		local n = ns()
		_G.UnitName = function() return "Boar" end
		n.estimator = n.Estimator.New({})
		n.Readable, n.IsSecret = function(v) return v end, function() return false end
		n.Debug = function() end
		local quest = { lines = { { leftText = "Boar", type = 0 }, { leftText = "Kill 5", type = 8 } } }
		n.CheckPet("mouseover", 5, quest)
		assert.is_true(n.estimator.store[5].quest)
		n.CheckPet("mouseover", 5, { lines = { { leftText = "Boar", type = 0 } } })
		assert.is_true(n.estimator.store[5].quest)
	end)
end)

describe("TooltipLine for zone scope", function()
	local function setup()
		_G.Enum = { TooltipDataType = { Unit = 2 } }
		_G.TooltipDataProcessor = { AddTooltipPostCall = function() end }
		local ns = helper.load("Util", "Estimator", "Tooltip")
		ns.estimator = ns.Estimator.New({}, {})
		ns.estimator:SetClass(1, "normal")
		feed(ns.estimator, { 290, 300, 310 })
		ns.estimator:SetClass(9, "normal")
		return ns
	end

	it("labels a live mob", function()
		local ns = setup()
		assert.are.equal("Typical respawn ~5m 00s (zone avg, 3 samples)", ns.TooltipLine("g", 9, false, 0, Z))
	end)

	it("labels a corpse we did not see die", function()
		local ns = setup()
		assert.are.equal("Respawn ~5m 00s (zone avg, 3 samples)", ns.TooltipLine("g", 9, true, 0, Z))
	end)

	it("counts down on a corpse we saw die", function()
		local ns = setup()
		ns.estimator:RecordDeath("c", 9, 1000, Z)
		assert.are.equal("Died 1m 12s ago, respawn in ~3m 48s (zone avg)", ns.TooltipLine("c", 9, true, 1072))
		assert.are.equal("Died 5m 10s ago, respawn due (zone avg)", ns.TooltipLine("c", 9, true, 1310))
	end)
end)
