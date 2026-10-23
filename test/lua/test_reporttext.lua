-- ReportText.lua: wording of the Reports screen lines
stub("engine")
include("ReportText")

test("signed numbers and screen texts", function()
	eq(ReportText_Signed(4), "plus 4")
	eq(ReportText_Signed(-2.5), "minus 2.5")
	eq(ReportText_Signed(0), "0")
	eq(ReportText_Signed("+3"), "plus 3")
	eq(ReportText_Signed("-12"), "minus 12")
	eq(ReportText_Signed(" "), nil)
	eq(ReportText_Signed(nil), nil)
	eq(ReportText_Signed("0"), "0")
end)

test("tab line", function()
	eq(ReportText_Tab("Yields", 1, 4), "Yields, 1 of 4 tabs")
end)

test("city income skips zero yields", function()
	eq(ReportText_CityIncome("Rome", { { label = "production", value = 12 }, { label = "gold", value = 8 }, { label = "tourism", value = 0 } }),
		"Rome: production plus 12, gold plus 8")
	eq(ReportText_CityIncome("Rome", { { label = "gold", value = 0 } }), "Rome: no yields")
end)

test("line item from screen texts", function()
	eq(ReportText_LineItem("Library", { { label = "science", value = "+2" }, { label = "gold", value = " " }, { label = "culture", value = "+1" } }),
		"Library: science plus 2, culture plus 1")
	eq(ReportText_LineItem("Barracks", { { label = "gold", value = " " } }), "Barracks")
end)

test("currency line", function()
	eq(ReportText_Currency("Gold", "+30", "-12", "+18", "245"), "Gold: income plus 30, expenses minus 12, net plus 18, balance 245")
	eq(ReportText_Currency("Science", "+9", nil, nil, "0"), "Science: income plus 9, balance 0")
end)

test("expenses", function()
	eq(ReportText_UnitExpense("Warrior", 3, 3), "Warrior, 3 units, minus 3 gold")
	eq(ReportText_UnitExpense("Archer", 1, 1), "Archer, 1 unit, minus 1 gold")
	eq(ReportText_BuildingExpense("Rome", "Library", 1), "Rome, Library: minus 1 gold")
end)

test("deals", function()
	eq(ReportText_Deal("Dido", true, "4 gold per turn", 12), "Deal with Dido: you give 4 gold per turn, 12 turns left")
	eq(ReportText_Deal("Dido", false, "1 Silk", 1), "Deal with Dido: they give 1 Silk, 1 turn left")
end)

test("resources", function()
	eq(ReportText_Resource({ name = "Silk", class = "luxury", total = 2, amenityCities = 4, exported = 1 }),
		"Silk, luxury, 2, amenities to 4 cities, 1 traded away")
	eq(ReportText_Resource({ name = "Iron", class = "strategic", total = 3, stockpile = 12, maximum = 20 }),
		"Iron, strategic, plus 3 per turn, stockpile 12 of 20")
	eq(ReportText_Resource({ name = "Iron", class = "strategic", total = 3 }), "Iron, strategic, plus 3")
	eq(ReportText_Resource({ name = "Wheat", class = "bonus", total = 5, imported = 2 }), "Wheat, bonus, 5, 2 received in trades")
	eq(ReportText_Resource({ name = "Wheat", class = "bonus", total = 5, amenityCities = 1 }), "Wheat, bonus, 5, amenities to 1 city")
end)

test("resource detail", function()
	eq(ReportText_ResourceDetail("Silk", { { source = "Rome", kind = "owned", amount = 2 }, { source = "Deal with Dido", kind = "exported", amount = -1 } }, { "1 to Rome" }),
		"Silk: Rome, owned, plus 2. Deal with Dido, exported, minus 1. Amenities: 1 to Rome")
	eq(ReportText_ResourceDetail("Silk", {}, nil), "Silk: no sources")
end)

test("city status", function()
	eq(ReportText_CityStatus({ name = "Rome", population = 9, housing = 10, growthStatus = "Normal", turnsUntilGrowth = 4,
		amenities = 2, amenitiesRequired = 3, happiness = "Content", warWeariness = 0, loyalty = 90, maxLoyalty = 100, loyaltyPerTurn = -2,
		production = "Library", productionTurns = 3, strength = 12, damage = 0 }),
		"Rome, population 9, housing 10, growth normal, grows in 4 turns, amenities 2 of 3 needed, content, loyalty 90 of 100, minus 2 per turn, producing Library in 3 turns, defense 12")
	eq(ReportText_CityStatus({ name = "Tyre", population = 1, housing = 2, turnsUntilGrowth = -3, amenities = 0, amenitiesRequired = 0,
		warWeariness = 1, siege = true, occupied = true, strength = 8, damage = 5 }),
		"Tyre, population 1, housing 2, starving in 3 turns, amenities 0 of 0 needed, war weariness minus 1 amenities, defense 8, damage 5, under siege, occupied")
end)

test("gossip", function()
	eq(ReportText_Gossip(98, "Dido built a [ICON_Campus] Campus in Tyre"), "Turn 98: Dido built a Campus in Tyre")
end)
