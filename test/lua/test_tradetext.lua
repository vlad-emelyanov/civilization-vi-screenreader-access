-- TradeText.lua: route item text, ordering, detail
stub("engine")
include("TradeText")

test("route item with yields, trading post and quest", function()
	local text = TradeText_Route{ name = "Bologna", owner = "city-state", distance = 12,
		yields = { { name = "Gold", amount = 4 }, { name = "Food", amount = 0 }, { name = "Science", amount = 1 } },
		tradingPost = true, quest = true }
	eq(text, "Bologna, city-state, 12 tiles, plus 4 Gold, plus 1 Science, trading post, quest")
end)

test("route item without yields, one tile, pressure, previous", function()
	local text = TradeText_Route{ name = "Rome", owner = "yours", distance = 1, yields = {},
		pressure = { name = "Catholicism", amount = 2 }, previous = true }
	eq(text, "Rome, yours, 1 tile, pressure 2 Catholicism, previous route")
end)

test("fractional and negative yields", function()
	eq(TradeText_YieldList{ { name = "Food", amount = 2.5 }, { name = "Gold", amount = -1 } }, "plus 2.5 Food, minus 1 Gold")
end)

test("sort: yield sum descending, then distance, then name", function()
	local routes = {
		{ name = "C", distance = 5, yields = { { name = "Gold", amount = 3 } } },
		{ name = "B", distance = 9, yields = { { name = "Gold", amount = 6 } } },
		{ name = "A", distance = 5, yields = { { name = "Gold", amount = 3 } } },
		{ name = "D", distance = 2, yields = { { name = "Gold", amount = 3 } } },
	}
	TradeText_SortRoutes(routes)
	local names = {}
	for i, r in ipairs(routes) do names[i] = r.name end
	eq(table.concat(names, ","), "B,D,A,C")
end)

test("detail joins tooltip, their yields and path length", function()
	local text = TradeText_Detail{ tooltip = "From districts", theirName = "Bologna",
		theirYields = { { name = "Gold", amount = 2 } }, pathLength = 7 }
	eq(text, "From districts. Bologna gets: plus 2 Gold. Path 7 tiles")
	eq(TradeText_Detail{ tooltip = "", theirYields = {}, pathLength = 0 }, "")
end)

test("origin city item", function()
	eq(TradeText_Origin{ name = "Florence", distance = 5 }, "Florence, 5 tiles")
	eq(TradeText_WhatsNext("Rome", "Enter", "Escape"), "Enter confirms the route to Rome, Escape goes back to the list")
end)

test("route passes cities and hazards", function()
	eq(TradeText_PassText({}), "")
	eq(TradeText_PassText({ "Rome" }), "Passes through Rome")
	eq(TradeText_PassText({ "Rome", "Antium", "Ostia" }), "Passes through Rome, Antium and Ostia")
	eq(TradeText_HazardText({}), "")
	eq(TradeText_HazardText({ { name = "Barbarian Camp", distance = 2 } }), "Passes 2 tiles from a Barbarian Camp")
	eq(TradeText_HazardText({ { name = "Barbarian Camp", distance = 2 }, { name = "Barbarian Warrior", distance = 1 }, { name = "Barbarian Warrior", distance = 1 } }),
		"Passes 1 tile from 2 Barbarian Warriors, 2 tiles from a Barbarian Camp")
	eq(TradeText_Detail{ pathLength = 5, passCities = { "Rome" }, hazards = { { name = "Barbarian Camp", distance = 1 } } },
		"Path 5 tiles. Passes through Rome. Passes 1 tile from a Barbarian Camp")
end)
