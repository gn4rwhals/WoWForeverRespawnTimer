local helper = require("spec.helper")

local HERE = { c = 0, x = 0, y = 0 }

local function setup()
	-- Tooltip.lua hooks the tooltip when loaded; stub the WoW globals it touches.
	_G.Enum = { TooltipDataType = { Unit = 2 } }
	_G.TooltipDataProcessor = { AddTooltipPostCall = function() end }
	local ns = helper.load("Util", "Estimator", "Tooltip")
	ns.estimator = ns.Estimator.New({})
	return ns
end

describe("TooltipLine", function()
	it("shows nothing for a live mob with no data", function()
		local ns = setup()
		assert.is_nil(ns.TooltipLine("g", 299, false, 0))
	end)

	it("shows the typical respawn for a live mob", function()
		local ns = setup()
		ns.estimator:RecordDeath("a", 299, 0, HERE)
		ns.estimator:RecordAlive("b", 299, 300, HERE)
		assert.are.equal("Typical respawn ~5m 00s (1 sample here)", ns.TooltipLine("b", 299, false, 400, HERE))
		assert.are.equal("Typical respawn ~5m 00s (1 sample, other spots)",
			ns.TooltipLine("b", 299, false, 400, { c = 0, x = 5000, y = 0 }))
	end)

	it("counts down on a corpse we saw die", function()
		local ns = setup()
		ns.estimator:SetOverride(299, 300)
		ns.estimator:RecordDeath("c", 299, 1000, HERE)
		assert.are.equal("Died 1m 12s ago, respawn in ~3m 48s", ns.TooltipLine("c", 299, true, 1072))
		assert.are.equal("Died 5m 10s ago, respawn due", ns.TooltipLine("c", 299, true, 1310))
	end)

	it("says no data for a corpse we saw die without an estimate", function()
		local ns = setup()
		ns.estimator:RecordDeath("c", 299, 1000, HERE)
		assert.are.equal("Died 30s ago, respawn: no data yet", ns.TooltipLine("c", 299, true, 1030))
	end)

	it("falls back to the estimate for a corpse we did not see die", function()
		local ns = setup()
		assert.are.equal("Respawn: no data yet", ns.TooltipLine("x", 299, true, 0))
		ns.estimator:SetOverride(299, 90)
		assert.are.equal("Respawn ~1m 30s (manual)", ns.TooltipLine("x", 299, true, 0))
	end)

	it("words bounds as an upper bound, never a countdown", function()
		local ns = setup()
		local est = ns.estimator
		est:RecordDeath("a", 299, 0, HERE)
		est:RecordBound("b", 299, 1020, HERE)
		assert.is_nil(ns.TooltipLine("b", 299, false, 1100, HERE)) -- one bound is not enough
		est:RecordDeath("c", 299, 2000, HERE)
		est:RecordBound("d", 299, 3020, HERE)
		assert.are.equal("Typical respawn at most 17m 00s (upper bound, 2 kills)",
			ns.TooltipLine("d", 299, false, 3100, HERE))
		est:RecordDeath("e", 299, 4000, HERE)
		assert.are.equal("Died 1m 00s ago, respawns within at most 16m 00s", ns.TooltipLine("e", 299, true, 4060))
		assert.are.equal("Died 30m 00s ago, respawn due (upper bound passed)", ns.TooltipLine("e", 299, true, 5800))
	end)
end)

local FMT = { "%s's Pet", "%s's Guardian" }
local QUEST_TITLE = 17 -- stub for Enum.TooltipDataLineType.QuestTitle
local function opts(extra)
	local o = { formats = FMT, skipTypes = { QUEST_TITLE } }
	for k, v in pairs(extra or {}) do o[k] = v end
	return o
end

describe("PetOwner", function()
	it("matches a pet title line and names the method", function()
		local ns = setup()
		local lines = { { text = "Skullsplitter Panther", n = 1 }, { text = "Skullsplitter Hunter's Pet", n = 2 } }
		local owner, how = ns.PetOwner(lines, opts())
		assert.are.equal("Skullsplitter Hunter", owner)
		assert.are.equal("text", how)
	end)

	it("matches any format in the list", function()
		local ns = setup()
		assert.are.equal("Bob", ns.PetOwner({ { text = "Bob's Guardian", n = 2 } }, opts()))
	end)

	it("prefers the UnitOwner line type", function()
		local ns = setup()
		local owner, how = ns.PetOwner({ { text = "Bob", type = 16, n = 2 } }, opts({ ownerType = 16 }))
		assert.are.equal("Bob", owner)
		assert.are.equal("type", how)
	end)

	it("returns nil without a match", function()
		local ns = setup()
		assert.is_nil(ns.PetOwner({ { text = "Level 30", n = 2 } }, opts()))
		assert.is_nil(ns.PetOwner({ { text = "x", type = 5, n = 2 } }, opts({ ownerType = 16 })))
		assert.is_nil(ns.PetOwner({ { text = "Hunter's Pet", n = 2 } }, opts({ formats = {} })))
	end)

	it("skips the name line and quest lines", function()
		local ns = setup()
		assert.is_nil(ns.PetOwner({ { text = "The Captain's Pet", n = 1 } }, opts()))
		assert.is_nil(ns.PetOwner({ { text = "The Captain's Pet", type = QUEST_TITLE, n = 2 } }, opts()))
	end)

	it("only matches text on line 2, and the owner type on lines up to 3", function()
		local ns = setup()
		local lines = { { text = "Bandit", n = 1 }, { text = "Level 30", n = 2 },
			{ text = "The Captain's Pet", type = 0, n = 3 } }
		assert.is_nil(ns.PetOwner(lines, opts()))
		assert.are.equal("Skullsplitter Hunter", ns.PetOwner({ { text = "Skullsplitter Hunter's Pet", n = 2 } }, opts()))
		assert.is_nil(ns.PetOwner({ { text = "Bob", type = 16, n = 4 } }, opts({ ownerType = 16 })))
		assert.are.equal("Bob", ns.PetOwner({ { text = "Bob", type = 16, n = 3 } }, opts({ ownerType = 16 })))
	end)

	it("ignores formats without %s and unescapes %%", function()
		local ns = setup()
		assert.is_nil(ns.PetOwner({ { text = "Pet", n = 2 } }, opts({ formats = { "Pet" } })))
		assert.are.equal("Bob", ns.PetOwner({ { text = "Bob 100% Pet", n = 2 } }, opts({ formats = { "%s 100%% Pet" } })))
	end)

	it("escapes Lua magic characters in the format", function()
		local ns = setup()
		assert.are.equal("Bob", ns.PetOwner({ { text = "Pet (of Bob)", n = 2 } }, opts({ formats = { "Pet (of %s)" } })))
	end)
end)

describe("PetLines", function()
	it("keeps readable string lines, skipping holes and bad entries", function()
		local ns = setup()
		ns.Readable = function(v) return v ~= "secret" and v or nil end
		ns.IsSecret = function() return false end
		local data = { lines = { { leftText = "Panther" }, { leftText = "secret" }, 5, { leftText = "Hunter's Pet", type = 3 } } }
		assert.are.same({ { text = "Panther", n = 1 }, { text = "Hunter's Pet", type = 3, n = 4 } }, ns.PetLines(data))
	end)

	it("returns an empty list for bad data", function()
		local ns = setup()
		ns.Readable, ns.IsSecret = function(v) return v end, function() return false end
		assert.are.same({}, ns.PetLines(nil))
		assert.are.same({}, ns.PetLines({ lines = 5 }))
	end)
end)

describe("TooltipLine for pets", function()
	it("shows nothing for a pet, alive or dead", function()
		local ns = setup()
		ns.estimator:MarkPet(756)
		assert.is_nil(ns.TooltipLine("g", 756, false, 0))
		assert.is_nil(ns.TooltipLine("g", 756, true, 0))
	end)
end)
