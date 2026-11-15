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
end)

describe("PetOwner", function()
	it("returns the owner for a pet title line", function()
		local ns = setup()
		assert.are.equal("Skullsplitter Hunter",
			ns.PetOwner({ "Skullsplitter Panther", "Skullsplitter Hunter's Pet", "Level 30" }, "%s's Pet"))
	end)

	it("returns nil without a match, without a format, or for non-string lines", function()
		local ns = setup()
		assert.is_nil(ns.PetOwner({ "Skullsplitter Panther", "Level 30" }, "%s's Pet"))
		assert.is_nil(ns.PetOwner({ "Hunter's Pet" }, nil))
		assert.is_nil(ns.PetOwner({ false, 5 }, "%s's Pet"))
	end)

	it("escapes Lua magic characters in the format", function()
		local ns = setup()
		assert.are.equal("Bob", ns.PetOwner({ "Pet (of Bob)" }, "Pet (of %s)"))
	end)
end)
