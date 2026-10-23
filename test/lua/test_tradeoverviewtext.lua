-- TradeOverviewText.lua: trade overview opening, route, slot and detail text
stub("engine")
include("TradeOverviewText")

test("opening with the first route", function()
	eq(TradeOverviewText_Opening{ used = 2, capacity = 3, tab = "My routes", count = 2, first = "Rome to Bologna, 4 turns left", index = 1 },
		"Trade routes: 2 of 3 used. My routes, 2 routes. Rome to Bologna, 4 turns left, 1 of 2")
end)

test("opening without routes or capacity", function()
	eq(TradeOverviewText_Opening{ tab = "Routes to my cities", count = 0 }, "Trade routes. Routes to my cities, no routes")
	eq(TradeOverviewText_Tab("Available routes", 1), "Available routes, 1 route")
end)

test("route with turns, yields, trading post and trader", function()
	local text = TradeOverviewText_Route{ origin = "Rome", destination = "Bologna", turns = 4,
		yields = { { name = "Gold", amount = 4 }, { name = "Food", amount = 0 }, { name = "Science", amount = 1 } },
		tradingPost = true, trader = "trader in Rome" }
	eq(text, "Rome to Bologna, 4 turns left, plus 4 Gold, plus 1 Science, trading post, trader in Rome")
end)

test("route minimal: one turn, owner, pressure", function()
	eq(TradeOverviewText_Route{ origin = "A", destination = "B", owner = "Egypt", turns = 1, yields = {},
		pressure = { name = "Islam", amount = 3 } }, "A to B, Egypt, 1 turn left, pressure 3 Islam")
	eq(TradeOverviewText_Route{ origin = "A", destination = "B", yields = {} }, "A to B")
end)

test("route with distance; tab switch opening; total differs", function()
	eq(TradeOverviewText_Route{ origin = "Rome", destination = "Bologna", distance = 12, yields = {} }, "Rome to Bologna, 12 tiles")
	eq(TradeOverviewText_Opening{ short = true, tab = "Available routes", count = 3, first = "Rome to Bologna", index = 1 },
		"Available routes, 3 routes. Rome to Bologna, 1 of 3")
	eq(TradeOverviewText_Opening{ used = 1, capacity = 3, tab = "My routes", count = 1, total = 3, first = "Rome to X", index = 1 },
		"Trade routes: 1 of 3 used. My routes, 1 route. Rome to X, 1 of 3")
end)

test("slots", function()
	eq(TradeOverviewText_Slot{ trader = "Rome" }, "Unused route slot, idle trader in Rome")
	eq(TradeOverviewText_Slot{}, "Unused route slot, no idle trader")
end)

test("detail joins tooltip, their yields, distance, trading post", function()
	eq(TradeOverviewText_Detail{ tooltip = "From districts", theirName = "Bologna", theirYields = { { name = "Gold", amount = 2 } },
		distance = 7, tradingPost = false }, "From districts. Bologna gets: plus 2 Gold. Distance 7 tiles. No trading post yet")
	eq(TradeOverviewText_Detail{ theirYields = {}, distance = 1, tradingPost = true }, "Distance 1 tile. Trading post established")
end)
