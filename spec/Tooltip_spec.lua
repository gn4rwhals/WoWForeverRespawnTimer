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
		assert.are.equal("Died 1m 00s ago, respawns within at most 17m 00s", ns.TooltipLine("e", 299, true, 4060))
		assert.are.equal("Died 30m 00s ago, respawns within at most 17m 00s", ns.TooltipLine("e", 299, true, 5800))
	end)
end)
