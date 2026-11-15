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

	it("never learns from a GUID first seen in combat, even on a later sighting", function()
		local e = new()
		e:RecordDeath("guid-a", 299, 1000, HERE)
		assert.is_nil(e:RecordBound("add", 299, 1300, FAR))
		assert.is_true(e:IsSeen("add"))
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

	it("gives no sample when the player was away for over MAX_AWAY seconds", function()
		local e, store = new()
		e:RecordDeath("guid-a", 299, 1000, HERE)
		for _ = 1, 13 do e:Tick(FAR, 5) end -- 65s out of range
		local sample, why, gap = e:RecordAlive("guid-b", 299, 1400, NEAR)
		assert.is_nil(sample)
		assert.are.same({ "away", 400 }, { why, gap })
		assert.is_nil(store[299])
		assert.is_nil(e:RecordAlive("guid-c", 299, 1410, NEAR)) -- death is used up
	end)

	it("still learns after a brief excursion", function()
		local e = new()
		e:RecordDeath("guid-a", 299, 1000, HERE)
		e:Tick(NEAR, 5)
		e:Tick(FAR, 5)
		e:Tick(NEAR, 5)
		assert.are.equal(300, e:RecordAlive("guid-b", 299, 1300, NEAR))
	end)

	it("learns when the player stayed 80 yards away, inside AWAY_RADIUS", function()
		local e = new()
		e:RecordDeath("guid-a", 299, 1000, HERE)
		for _ = 1, 60 do e:Tick({ c = 0, x = 180, y = 100 }, 5) end
		assert.are.equal(300, e:RecordAlive("guid-b", 299, 1300, HERE))
	end)

	it("counts a tick with no position or on another continent as away", function()
		local e = new()
		e:RecordDeath("guid-a", 299, 1000, HERE)
		e:Tick(nil, 5)
		e:Tick({ c = 1, x = 100, y = 100 }, 5)
		assert.are.equal(10, e.deaths["guid-a"].awaySecs)
	end)

	it("ignores samples far from the type median, in area and type estimates", function()
		local e, store = new()
		store[299] = { samples = { 68, 260, 287, 66, 290 }, areas = {
			{ c = 0, x = 100, y = 100, samples = { 68, 287, 66 } } } }
		assert.are.same({ seconds = 287, n = 1, scope = "area" }, e:Estimate(299, NEAR))
		assert.are.same({ seconds = 287, n = 3, scope = "type" }, e:Estimate(299, FAR))
		store[299] = { samples = { 260, 270, 280, 2963 }, areas = {
			{ c = 0, x = 100, y = 100, samples = { 260, 2963 } } } }
		assert.are.same({ seconds = 260, n = 1, scope = "area" }, e:Estimate(299, NEAR))
	end)

	it("uses the type estimate when filtering leaves an area nothing", function()
		local e, store = new()
		store[299] = { samples = { 100, 110, 120 }, areas = {
			{ c = 0, x = 100, y = 100, samples = { 20, 1000 } } } }
		assert.are.same({ seconds = 110, n = 3, scope = "type" }, e:Estimate(299, NEAR))
	end)

	it("scales the away budget with the gap", function()
		local e = new()
		e:RecordDeath("a", 299, 1000, HERE)
		e:Tick(FAR, 25)
		assert.is_nil(e:RecordAlive("b", 299, 1096, NEAR)) -- 25s > 0.2 * 96
		e:RecordDeath("c", 299, 2000, HERE)
		e:Tick(FAR, 25)
		assert.are.equal(300, e:RecordAlive("d", 299, 2300, NEAR)) -- 25s <= 60
		e:RecordDeath("f", 299, 3000, HERE)
		e:Tick(FAR, 20)
		assert.are.equal(100, e:RecordAlive("g", 299, 3100, NEAR)) -- exactly 0.2 * 100
		e:RecordDeath("h", 299, 4000, HERE)
		e:Tick(FAR, 21)
		assert.is_nil(e:RecordAlive("i", 299, 4100, NEAR))
	end)

	describe("RecordBound", function()
		-- Two bounds from two kills of npcID 299, gaps g1 and g2.
		local function twoBounds(e, g1, g2)
			e:RecordDeath("a", 299, 1000, HERE)
			e:RecordBound("b", 299, 1000 + g1, HERE)
			e:RecordDeath("c", 299, 5000, HERE)
			e:RecordBound("d", 299, 5000 + g2, HERE)
		end

		it("records the gap as an upper bound for a fresh mob near a pending death", function()
			local e, store = new()
			e:RecordDeath("a", 299, 1000, HERE)
			assert.are.equal(500, e:RecordBound("b", 299, 1500, NEAR))
			assert.are.same({ 500 }, store[299].bounds)
			assert.are.same({}, store[299].samples)
		end)

		it("records nothing when far away, wrong npcID, no position or already seen", function()
			local e, store = new()
			e:RecordDeath("a", 299, 1000, HERE)
			assert.is_nil(e:RecordBound("b", 299, 1500, FAR))
			assert.is_nil(e:RecordBound("c", 300, 1500, HERE))
			assert.is_nil(e:RecordBound("n", 299, 1500, nil))
			assert.is_nil(e:RecordBound("c", 299, 1500, HERE)) -- already seen above
			assert.is_nil(store[299])
			assert.is_nil(store[300])
		end)

		it("reports whether a GUID has been seen", function()
			local e = new()
			assert.is_false(e:IsSeen("x"))
			e:RecordBound("x", 299, 0, HERE)
			assert.is_true(e:IsSeen("x"))
		end)

		it("never learns from a GUID first seen in combat", function()
			local e = new()
			e:RecordDeath("a", 299, 1000, HERE)
			e:RecordBound("add", 299, 1300, FAR)
			assert.is_nil(e:RecordAlive("add", 299, 1300, NEAR))
			assert.are.equal(300, e:RecordAlive("respawn", 299, 1300, NEAR))
		end)

		it("does not consume the death: a later fresh sighting still gives a sample", function()
			local e, store = new()
			e:RecordDeath("a", 299, 1000, HERE)
			e:RecordBound("b", 299, 1500, HERE)
			assert.are.equal(600, e:RecordAlive("c", 299, 1600, HERE))
			assert.are.same({ 600 }, store[299].samples)
		end)

		it("gives one death only one bound", function()
			local e, store = new()
			e:RecordDeath("a", 299, 1000, HERE)
			e:RecordBound("b", 299, 1500, HERE)
			assert.is_nil(e:RecordBound("c", 299, 1600, HERE))
			assert.are.same({ 500 }, store[299].bounds)
		end)

		it("caps bounds at MAX_SAMPLES, dropping the oldest", function()
			local e, store = new()
			for i = 1, e.MAX_SAMPLES + 1 do
				e:RecordDeath("d" .. i, 299, i * 1000, HERE)
				e:RecordBound("b" .. i, 299, i * 1000 + 100 + i, HERE)
			end
			assert.are.equal(e.MAX_SAMPLES, #store[299].bounds)
			assert.are.equal(102, store[299].bounds[1])
		end)

		it("needs two bounds before estimating, and uses their median", function()
			local e = new()
			e:RecordDeath("a", 299, 1000, HERE)
			e:RecordBound("b", 299, 1500, HERE)
			assert.is_nil(e:Estimate(299, HERE))
			e:RecordDeath("c", 299, 5000, HERE)
			e:RecordBound("d", 299, 5900, HERE)
			e:RecordDeath("f", 299, 9000, HERE)
			e:RecordBound("g", 299, 9700, HERE)
			-- bounds 500, 900, 700
			assert.are.same({ seconds = 700, n = 3, scope = "bound" }, e:Estimate(299, HERE))
		end)

		it("is not driven by a single false low bound", function()
			local e = new()
			twoBounds(e, 50, 3000)
			assert.are.equal(3000, e:Estimate(299, HERE).seconds)
		end)

		it("closes a bounded death when its respawn dies, so the next sample is not doubled", function()
			local e, store = new()
			e:RecordDeath("a", 299, 0, HERE)
			assert.are.equal(900, e:RecordBound("b", 299, 900, HERE))
			e:RecordDeath("b", 299, 950, HERE)
			assert.are.equal(900, e:RecordAlive("c", 299, 1850, HERE))
			assert.are.same({ 900 }, store[299].samples)
		end)

		it("lets samples win over bounds", function()
			local e = new()
			twoBounds(e, 300, 400)
			e:RecordDeath("f", 299, 9000, HERE)
			e:RecordAlive("g", 299, 9900, HERE)
			local est = e:Estimate(299, HERE)
			assert.are.same({ 1, "area" }, { est.n, est.scope })
		end)

		it("works with an old entry that has no bounds field", function()
			local e, store = new()
			store[299] = { samples = {} }
			assert.is_nil(e:Estimate(299, HERE))
		end)

		it("never gives a corpse a remaining time from bounds alone", function()
			local e = new()
			twoBounds(e, 500, 700)
			e:RecordDeath("z", 299, 9000, HERE)
			local c = e:Corpse("z", 9100)
			assert.is_nil(c.remaining)
			assert.are.equal("bound", c.estimate.scope)
		end)

		it("is removed by Clear", function()
			local e, store = new()
			twoBounds(e, 500, 700)
			e:Clear(299)
			assert.is_nil(store[299])
		end)
	end)
end)

describe("Estimator pets", function()
	it("MarkPet drops learned data and pending deaths, true only once", function()
		local e, store = new()
		e:RecordDeath("a", 756, 0, HERE)
		e:RecordAlive("b", 756, 300, HERE)
		e:RecordDeath("c", 756, 400, HERE)
		e:SetOverride(756, 60)
		assert.is_true(e:MarkPet(756))
		assert.is_false(e:MarkPet(756))
		assert.are.same({ pet = true }, store[756])
		assert.is_nil(e.deaths["c"])
		assert.is_true(e:IsPet(756))
		assert.is_false(e:IsPet(299))
	end)

	it("Estimate is nil for a pet and Clear undoes the flag", function()
		local e = new()
		e:MarkPet(756)
		assert.is_nil(e:Estimate(756, HERE))
		e:Clear(756)
		assert.is_false(e:IsPet(756))
	end)
end)
