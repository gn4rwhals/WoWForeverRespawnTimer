local helper = require("spec.helper")

describe("Paused", function()
	local function load(isInInstance, secret)
		_G.CreateFrame = function()
			return { RegisterEvent = function() end, SetScript = function() end }
		end
		_G.SlashCmdList = {}
		_G.IsInInstance = isInInstance
		_G.issecretvalue = secret
		return helper.load("Core")
	end

	after_each(function()
		_G.IsInInstance, _G.issecretvalue = nil, nil
	end)

	it("is true inside an instance and false outside", function()
		assert.is_true(load(function() return true, "party" end).Paused())
		assert.is_false(load(function() return false, "none" end).Paused())
	end)

	it("counts a secret answer or an error as inside", function()
		assert.is_true(load(function() return true end, function() return true end).Paused())
		assert.is_true(load(function() error("blocked") end).Paused())
		assert.is_true(load(nil).Paused())
	end)
end)
