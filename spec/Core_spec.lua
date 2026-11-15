local helper = require("spec.helper")

describe("Paused", function()
	local function yes() return true end
	local function no() return false end

	local function load(isInInstance, isResting, secret)
		_G.CreateFrame = function()
			return { RegisterEvent = function() end, SetScript = function() end }
		end
		_G.SlashCmdList = {}
		_G.IsInInstance, _G.IsResting, _G.issecretvalue = isInInstance, isResting, secret
		return helper.load("Core")
	end

	after_each(function()
		_G.IsInInstance, _G.IsResting, _G.issecretvalue = nil, nil, nil
	end)

	it("is true inside an instance or a rested area, false elsewhere", function()
		assert.is_true(load(function() return true, "party" end, no).Paused())
		assert.is_true(load(function() return false, "none" end, yes).Paused())
		assert.is_false(load(function() return false, "none" end, no).Paused())
	end)

	it("counts a secret answer or an error as paused", function()
		assert.is_true(load(no, yes, function(v) return v == true end).Paused())
		assert.is_true(load(function() error("blocked") end, no).Paused())
		assert.is_true(load(no, nil).Paused())
	end)
end)
