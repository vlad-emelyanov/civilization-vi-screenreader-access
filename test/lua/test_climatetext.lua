-- ClimateText.lua: wording of the World Climate lines
stub("engine")
include("ClimateText")

test("signed and percent", function()
	eq(ClimateText_Signed(0.4), "plus 0.4")
	eq(ClimateText_Signed(-1.26), "minus 1.3")
	eq(ClimateText_Signed(0), "0")
	eq(ClimateText_Percent(12, 100), 12)
	eq(ClimateText_Percent(1, 3), 33)
	eq(ClimateText_Percent(5, 0), 0)
end)

test("phase and temperature", function()
	eq(ClimateText_Phase(2, 7, "Coastal Flooding"), "phase 2 of 7, Coastal Flooding")
	eq(ClimateText_Phase(0, 7, nil), "no climate change phase reached yet")
	eq(ClimateText_Temperature(0.4), "global temperature plus 0.4 degrees")
	eq(ClimateText_Temperature(0), "global temperature 0")
end)

test("contribution", function()
	eq(ClimateText_Contribution(12, 100, 1, 5), "your CO2 contribution 12 percent, ranked 1 of 5 civilizations")
	eq(ClimateText_Contribution(0, 0, 1, 5), "no CO2 emitted yet")
end)

test("summary", function()
	eq(ClimateText_Summary({ phase = 2, maxPhases = 7, phaseName = "Coastal Flooding", temperature = 0.4,
		seaLevel = "sea level rise 1 meter", nextRiseTurns = 30, contribution = "your CO2 contribution 12 percent" }),
		"Phase 2 of 7, Coastal Flooding, global temperature plus 0.4 degrees, sea level rise 1 meter, next sea level rise in 30 turns. Your CO2 contribution 12 percent")
	eq(ClimateText_Summary({ phase = 0, maxPhases = 7, temperature = 0 }), "No climate change phase reached yet, global temperature 0")
end)

test("chances and rows", function()
	eq(ClimateText_Chance("Storms", 12, 3), "Storms: 12 percent chance, 3 of that from climate change")
	eq(ClimateText_Chance("Floods", 5, 0), "Floods: 5 percent chance")
	eq(ClimateText_Volcanoes(4, 2, 5, 1, 3), "Volcanoes: 4 percent eruption chance, 2 active, 5 inactive, 1 volatile, 3 erupted")
	eq(ClimateText_Row("Rome (You)", 120, 350), "Rome (You): 120 CO2, 34 percent")
end)

test("events", function()
	eq(ClimateText_Event({ turn = 85, name = "Hurricane Alfred", typeName = "Storm", location = "Europe", effects = { "3 tiles damaged" } }),
		"Turn 85: Hurricane Alfred, Storm, Europe, 3 tiles damaged")
	eq(ClimateText_Event({ turn = 80, typeName = "Phase 1" }), "Turn 80: Phase 1")
	local e = ClimateText_Effects(2, 1, 0, 3)
	eq(#e, 3)
	eq(e[1], "2 tiles fertilized")
	eq(e[2], "1 tile damaged")
	eq(e[3], "3 population lost")
	eq(ClimateText_Effects(-1, 0, 2, 0)[1], "1 tile lost fertility")
end)
