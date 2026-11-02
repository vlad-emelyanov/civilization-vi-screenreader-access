-- ReligionText.lua: pure text helpers of the religion screen
stub("engine")
include("ReligionText")

test("Join", function()
	eq(ReligionText_Join({}), "none")
	eq(ReligionText_Join({ "A" }), "A")
	eq(ReligionText_Join({ "A", "B" }), "A and B")
	eq(ReligionText_Join({ "A", "B", "C" }), "A, B and C")
end)

test("Count", function()
	eq(ReligionText_Count(1, "city", "cities"), "1 city")
	eq(ReligionText_Count(0, "city", "cities"), "0 cities")
	eq(ReligionText_Count(4, "city", "cities"), "4 cities")
end)

test("Followers sorted, zero dropped", function()
	eq(ReligionText_Followers({}), "no followers")
	eq(ReligionText_Followers({ { name = "Hinduism", followers = 2 }, { name = "Islam", followers = 0 }, { name = "Buddhism", followers = 6 } }), "6 Buddhism, 2 Hinduism")
end)

test("CityLine", function()
	eq(ReligionText_CityLine("Rome", "Buddhism", { { name = "Buddhism", followers = 6 }, { name = "Hinduism", followers = 2 } }), "Rome: majority Buddhism, 6 Buddhism, 2 Hinduism")
	eq(ReligionText_CityLine("Rome", nil, {}), "Rome: no religion")
	eq(ReligionText_CityLine("Rome", nil, { { name = "Hinduism", followers = 1 } }), "Rome: no majority, 1 Hinduism")
end)

test("Founder, Beliefs, ToChoose, Capital", function()
	eq(ReligionText_Founder(true, "Rome"), "founded by you")
	eq(ReligionText_Founder(false, "Phoenicia"), "founded by Phoenicia")
	eq(ReligionText_Beliefs({}), "no beliefs yet")
	eq(ReligionText_Beliefs({ "Choral Music", "Tithe" }), "Choral Music and Tithe")
	eq(ReligionText_ToChoose(1), "1 belief to choose")
	eq(ReligionText_ToChoose(2), "2 beliefs to choose")
	eq(ReligionText_Capital("follower belief"), "Follower belief")
	eq(ReligionText_Capital(""), "")
end)

test("Spread / Convert results", function()
	eq(ReligionText_SpreadResult("Buddhism", "Rome", 2), "Buddhism spread in Rome, 2 spreads left")
	eq(ReligionText_SpreadResult("Buddhism", "Rome", 1), "Buddhism spread in Rome, 1 spread left")
	eq(ReligionText_SpreadResult("Buddhism", "Rome", 0), "Buddhism spread in Rome, no spreads left")
	eq(ReligionText_SpreadResult("", nil, nil), "Religion spread")
	eq(ReligionText_ConvertResult({ "Line Infantry" }, 1), "Converted 1 barbarian unit: Line Infantry, 1 spread left")
	eq(ReligionText_ConvertResult({ "A", "B" }, nil), "Converted 2 barbarian units: A, B")
	eq(ReligionText_ConvertResult({}, 0), "Convert Barbarians used, no spreads left")
	eq(ReligionText_ConvertResult({}, nil, false), "Convert Barbarians did not take effect")
	eq(ReligionText_ConvertResult({}, nil, true), "Convert Barbarians used")
	eq(ReligionText_ActionDescription("UNITOPERATION_LAUNCH_INQUISITION") ~= nil, true)
	eq(ReligionText_ActionDescription("UNITOPERATION_FORTIFY"), nil)
end)

test("InitiatesCombat: religious strength and not a missionary class", function()
	eq(ReligionText_InitiatesCombat(110, false), true)		-- Apostle
	eq(ReligionText_InitiatesCombat(75, false), true)		-- Inquisitor
	eq(ReligionText_InitiatesCombat(100, true), false)		-- Missionary (ABILITY_RELIGIOUS_CANNOT_ATTACK)
	eq(ReligionText_InitiatesCombat(90, true), false)		-- Guru
	eq(ReligionText_InitiatesCombat(0, false), false)		-- Builder, Settler, soldiers
	eq(ReligionText_InitiatesCombat(nil, false), false)
end)

test("CanInitiateCombat reads the unit type tags once", function()
	GameInfo = {
		Units = { [1] = { UnitType = "UNIT_APOSTLE" }, [2] = { UnitType = "UNIT_MISSIONARY" }, [3] = { UnitType = "UNIT_BUILDER" },
			UNIT_APOSTLE = {}, UNIT_MISSIONARY = {}, UNIT_GURU = {} },
		TypeTags = function()
			local rows = { { Type = "ABILITY_RELIGIOUS_CANNOT_ATTACK", Tag = "CLASS_MISSIONARY" }, { Type = "UNIT_MISSIONARY", Tag = "CLASS_MISSIONARY" },
				{ Type = "UNIT_GURU", Tag = "CLASS_MISSIONARY" }, { Type = "UNIT_APOSTLE", Tag = "CLASS_RELIGIOUS" } }
			local i = 0
			return function() i = i + 1; return rows[i] end
		end }
	local function unit(typeIndex, strength) return { GetReligiousStrength = function() return strength end, GetUnitType = function() return typeIndex end } end
	eq(ReligionText_CanInitiateCombat(unit(1, 110)), true)
	eq(ReligionText_CanInitiateCombat(unit(2, 100)), false)
	eq(ReligionText_CanInitiateCombat(unit(3, 0)), false)
	eq(ReligionText_CanInitiateCombat(nil), false)
end)

test("NoTargetLine names the unit", function()
	eq(ReligionText_NoTargetLine("Apostle"), "Apostle: no religious units in reach")
end)
