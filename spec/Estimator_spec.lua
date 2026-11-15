local helper = require("spec.helper")

local HERE = { c = 0, x = 100, y = 100 }
local NEAR = { c = 0, x = 110, y = 100 } -- 10 yards away
local FAR = { c = 0, x = 300, y = 100 }  -- 200 yards away

local function new()
	local ns = helper.load("Util", "Estimator")
	local store = {}
	return ns.Estimator.New(store), store
end

describe("Estimator", function()
	it("learns a sample when a new mob appears near a death", function()
		local e, store = new()
		e:RecordDeath("guid-a", 299, 1000, HERE)
		assert.are.equal(300, e:RecordAlive("guid-b", 299, 1300, NEAR))
		assert.are.same({ 300 }, store[299].samples)
		assert.are.same({ seconds = 300, n = 1, scope = "type" }, e:Estimate(299))
		assert.are.same({ seconds = 300, n = 1, scope = "area" }, e:Estimate(299, NEAR))
	end)

	it("keeps separate estimates for separate spawn areas", function()
		local e, store = new()
		local CAMP_B = { c = 0, x = 1000, y = 100 }
		e:RecordDeath("a1", 299, 1000, HERE)
		e:RecordAlive("a2", 299, 1300, HERE)   -- 300s at camp A
		e:RecordDeath("b1", 299, 2000, CAMP_B)
		e:RecordAlive("b2", 299, 2600, CAMP_B) -- 600s at camp B
		assert.are.equal(2, #store[299].areas)
		-- RecordAlive reports which area got the sample, for the debug log.
		e:RecordDeath("a3", 299, 3000, HERE)
		local sample, areaIndex, areaCount = e:RecordAlive("a4", 299, 3200, NEAR)
		assert.are.same({ 200, 1, 2 }, { sample, areaIndex, areaCount })
		assert.are.same({ seconds = 250, n = 2, scope = "area" }, e:Estimate(299, NEAR))
		assert.are.same({ seconds = 600, n = 1, scope = "area" }, e:Estimate(299, CAMP_B))
		-- Far from both camps: every sample for the type.
		assert.are.same({ seconds = 300, n = 3, scope = "type" }, e:Estimate(299, { c = 0, x = 5000, y = 0 }))
	end)

	it("merges nearby deaths into one area and moves its centre", function()
		local e, store = new()
		e:RecordDeath("a1", 299, 1000, { c = 0, x = 100, y = 100 })
		e:RecordAlive("a2", 299, 1300, { c = 0, x = 100, y = 100 })
		e:RecordDeath("b1", 299, 2000, { c = 0, x = 130, y = 100 }) -- 30 yd: same area
		e:RecordAlive("b2", 299, 2400, { c = 0, x = 130, y = 100 })
		local areas = store[299].areas
		assert.are.equal(1, #areas)
		assert.are.equal(115, areas[1].x)
		assert.are.same({ 300, 400 }, areas[1].samples)
	end)

	it("uses the death's area for a corpse countdown", function()
		local e = new()
		local CAMP_B = { c = 0, x = 1000, y = 100 }
		e:RecordDeath("a1", 299, 0, HERE)
		e:RecordAlive("a2", 299, 300, HERE)    -- 300s at camp A
		e:RecordDeath("b1", 299, 1000, CAMP_B)
		e:RecordAlive("b2", 299, 1600, CAMP_B) -- 600s at camp B
		e:RecordDeath("corpse", 299, 2000, CAMP_B)
		assert.are.equal(500, e:Corpse("corpse", 2100).remaining)
	end)

	it("ignores a different npcID, a far sighting, and too short or long gaps", function()
		local e = new()
		e:RecordDeath("guid-a", 299, 1000, HERE)
		assert.is_nil(e:RecordAlive("guid-b", 300, 1300, NEAR))       -- other npc
		assert.is_nil(e:RecordAlive("guid-c", 299, 1300, FAR))        -- too far
		assert.is_nil(e:RecordAlive("guid-d", 299, 1010, NEAR))       -- under MIN_SAMPLE
		assert.is_nil(e:RecordAlive("guid-e", 299, 1000 + 3 * 3600, NEAR)) -- over MAX_SAMPLE
		assert.is_nil(e:Estimate(299))
	end)

	it("never learns from a GUID it has already seen", function()
		local e = new()
		e:RecordAlive("guid-b", 299, 900, NEAR) -- seen alive before the death
		e:RecordDeath("guid-a", 299, 1000, HERE)
		assert.is_nil(e:RecordAlive("guid-b", 299, 1300, NEAR))
	end)

	it("never learns from a GUID marked seen (an add that joined a fight)", function()
		local e = new()
		e:RecordDeath("guid-a", 299, 1000, HERE)
		assert.is_true(e:MarkSeen("add"))
		assert.is_false(e:MarkSeen("add")) -- second mark: nothing new to log
		assert.is_nil(e:RecordAlive("add", 299, 1300, NEAR))
		assert.are.equal(300, e:RecordAlive("respawn", 299, 1300, NEAR))
	end)

	it("rejects a gap of 25s, like a second mob pulled into the fight", function()
		local e = new()
		e:RecordDeath("guid-a", 299, 1000, HERE)
		assert.is_nil(e:RecordAlive("guid-b", 299, 1025, NEAR))
	end)

	it("matches each death only once", function()
		local e = new()
		e:RecordDeath("guid-a", 299, 1000, HERE)
		assert.are.equal(300, e:RecordAlive("guid-b", 299, 1300, NEAR))
		assert.is_nil(e:RecordAlive("guid-c", 299, 1310, NEAR))
	end)

	it("pairs a sighting with the closest death", function()
		local e = new()
		e:RecordDeath("guid-a", 299, 1000, { c = 0, x = 130, y = 100 }) -- 20 yd from NEAR
		e:RecordDeath("guid-b", 299, 1100, { c = 0, x = 112, y = 100 }) -- 2 yd from NEAR
		assert.are.equal(200, e:RecordAlive("guid-c", 299, 1300, NEAR))
	end)

	it("needs positions to match", function()
		local e = new()
		e:RecordDeath("guid-a", 299, 1000, nil)
		assert.is_nil(e:RecordAlive("guid-b", 299, 1300, NEAR))
	end)

	it("uses the median and keeps at most MAX_SAMPLES", function()
		local e, store = new()
		for i = 1, 25 do
			local t = i * 10000
			e:RecordDeath("dead-" .. i, 299, t, HERE)
			e:RecordAlive("alive-" .. i, 299, t + 100 + i, NEAR)
		end
		assert.are.equal(20, #store[299].samples)
		assert.are.equal(106, store[299].samples[1]) -- samples 1-5 dropped
		assert.are.equal(115.5, e:Estimate(299).seconds)
	end)

	it("reports time since death and time remaining for a corpse", function()
		local e = new()
		e:RecordDeath("old", 299, 0, HERE)
		e:RecordAlive("new", 299, 300, NEAR) -- learns 300s
		e:RecordDeath("corpse", 299, 1000, HERE)
		local c = e:Corpse("corpse", 1072)
		assert.are.equal(72, c.diedAgo)
		assert.are.equal(228, c.remaining)
		assert.is_nil(e:Corpse("never-seen-die", 1072))
	end)

	it("leaves remaining nil for a corpse with no estimate", function()
		local e = new()
		e:RecordDeath("corpse", 299, 1000, HERE)
		local c = e:Corpse("corpse", 1050)
		assert.are.equal(50, c.diedAgo)
		assert.is_nil(c.remaining)
	end)

	it("lets a manual override win and clear reset it", function()
		local e = new()
		e:RecordDeath("guid-a", 299, 1000, HERE)
		e:RecordAlive("guid-b", 299, 1300, NEAR)
		e:SetOverride(299, 600)
		assert.are.same({ seconds = 600, n = 1, scope = "manual" }, e:Estimate(299, NEAR))
		e:Clear(299)
		assert.is_nil(e:Estimate(299))
	end)

	it("forgets deaths older than MAX_SAMPLE", function()
		local e = new()
		e:RecordDeath("old", 299, 0, HERE)
		e:RecordDeath("new", 299, 3 * 3600, HERE)
		assert.is_nil(e:Corpse("old", 3 * 3600))
	end)

	it("gives no sample when the player was away at any tick", function()
		local e, store = new()
		e:RecordDeath("guid-a", 299, 1000, HERE)
		e:Tick(1100, NEAR)
		e:Tick(1200, FAR) -- left the area
		e:Tick(1300, NEAR) -- came back
		local sample, why, gap = e:RecordAlive("guid-b", 299, 1400, NEAR)
		assert.is_nil(sample)
		assert.are.same({ "away", 400 }, { why, gap })
		assert.is_nil(store[299])
		assert.is_nil(e:RecordAlive("guid-c", 299, 1410, NEAR)) -- death is used up
	end)

	it("gives a sample when every tick was in range", function()
		local e = new()
		e:RecordDeath("guid-a", 299, 1000, HERE)
		e:Tick(1100, NEAR)
		e:Tick(1200, HERE)
		assert.are.equal(300, e:RecordAlive("guid-b", 299, 1300, NEAR))
	end)

	it("marks a death away when a tick has no position", function()
		local e = new()
		e:RecordDeath("guid-a", 299, 1000, HERE)
		e:Tick(1100, nil)
		assert.is_nil(e:RecordAlive("guid-b", 299, 1300, NEAR))
		assert.is_true(e.deaths["guid-a"].away)
	end)

	it("marks a death away on another continent or with an unknown death position", function()
		local e = new()
		e:RecordDeath("guid-a", 299, 1000, HERE)
		e:RecordDeath("guid-b", 299, 1000, nil)
		e:Tick(1100, { c = 1, x = 100, y = 100 })
		assert.is_true(e.deaths["guid-a"].away)
		assert.is_true(e.deaths["guid-b"].away)
	end)

	it("estimates from the median without short outliers", function()
		local e, store = new()
		store[299] = { samples = { 68, 260, 287, 66 }, areas = {} }
		assert.are.same({ seconds = 273.5, n = 2, scope = "type" }, e:Estimate(299))
		store[299].areas = { { c = 0, x = 100, y = 100, samples = { 68, 260, 287, 66 } } }
		assert.are.same({ seconds = 273.5, n = 2, scope = "area" }, e:Estimate(299, NEAR))
		assert.are.same({ 68, 260, 287, 66 }, store[299].samples) -- raw data untouched
	end)
end)
