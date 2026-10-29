-- PlacementScan.lua: why a district/building cannot be placed (engine result tables -> sentences)
local Strings = stub("engine")
local world = stub("world").new{ width = 10, height = 10 }
world:install()
GameInfo.Yields.YIELD_FAITH = { Index = 5 }
CityOperationTypes = { BUILD = "BUILD", PARAM_X = "x", PARAM_Y = "y", PARAM_DISTRICT_TYPE = "d", PARAM_BUILDING_TYPE = "b" }
CityOperationResults = { NO_SUITABLE_LOCATION = "nsl", FAILURE_REASONS = "fail", SUCCESS_CONDITIONS = "ok", PLOTS = "plots" }
CityCommandTypes = { PURCHASE = "PURCHASE", PARAM_PLOT_PURCHASE = "pp" }
CityCommandResults = { PLOTS = "plots" }
include("PlacementScan")

Strings.LOC_DISTRICT_ZONE_NO_SUITABLE_LOCATION = "No suitable location."
Strings.LOC_BUILDING_CONSTRUCT_NO_SUITABLE_LOCATION = "No suitable location for building."

-- queue:CanProduce(hash, a, b[, buy]) answers from a table: answers.owned / answers.buy = { can, results }
local function scanWith(answers)
	local queue = { CanProduce = function(_, _, _, _, buy)
		local a = buy and answers.buy or answers.owned
		return a[1], a[2]
	end }
	return { city = { GetBuildQueue = function() return queue end }, hash = 7, typeName = "DISTRICT_CAMPUS", kind = "district" }
end

test("Explain: reasons are cleaned, deduplicated, trailing dots dropped", function()
	local scan = scanWith{
		owned = { false, { fail = { "Requires Population of 4 or greater.", "Needs [ICON_Science] a Library." } } },
		buy = { false, { fail = { "Requires Population of 4 or greater." } } },
	}
	local info = PlacementScan_Explain(scan)
	eq(info.canOwned, false)
	eq(info.canBuy, false)
	listeq(info.reasons, { "Requires Population of 4 or greater", "Needs Science a Library" })
	eq(info.noSuitable, false)
end)

test("Explain: the engine's no-suitable-location tag or text is a flag, not a reason", function()
	local scan = scanWith{
		owned = { false, { fail = { "LOC_DISTRICT_ZONE_NO_SUITABLE_LOCATION" }, nsl = true } },
		buy = { false, { fail = { "No suitable location." } } },
	}
	local info = PlacementScan_Explain(scan)
	eq(info.noSuitable, true)
	eq(#info.reasons, 0)
end)

test("Explain: canProduce results", function()
	local info = PlacementScan_Explain(scanWith{ owned = { true, nil }, buy = { true, nil } })
	eq(info.canOwned, true)
	eq(info.canBuy, true)
end)

test("Cannot: foreign tile, engine reasons, water, unowned", function()
	local plot = Map.GetPlot(2, 2)
	local scan = { kind = "district", hash = 7, city = {}, district = {} }
	world:set(2, 2, { owner = 3 })
	eq(PlacementScan_Cannot(scan, plot), "owned by another civilization")
	world:set(2, 2, { owner = 0 })
	CityManager = { CanStartOperation = function() return false, { fail = { "Too close to the city center." } } end }
	eq(PlacementScan_Cannot(scan, plot), "Too close to the city center")
	CityManager = { CanStartOperation = function() return false, nil end }
	world:set(2, 2, { terrain = "water", owner = 0 })
	eq(PlacementScan_Cannot(scan, plot), "water")
	world:set(2, 2, { terrain = "grass", owner = -1 })
	eq(PlacementScan_Cannot(scan, plot), "not your territory, and the tile cannot be bought for this")
	world:set(2, 2, { owner = 0 })
	eq(PlacementScan_Cannot(scan, plot), "")
	eq(PlacementScan_Cannot(scan, nil), "")
end)

test("Sort: tiles needing an unaffordable purchase go after every placeable tile", function()
	local function c(i, owned, short, total) return { plotIndex = i, owned = owned, shortBy = short, total = total, removes = {}, distance = i } end
	local scan = { kind = "district", list = { c(1, false, 80, 5), c(2, true, nil, 0), c(3, false, 0, 1), c(4, false, 20, 9) } }
	PlacementScan_Sort(scan)
	local ids = {}
	for _, it in ipairs(scan.list) do table.insert(ids, it.plotIndex) end
	eq(table.concat(ids, ","), "3,2,4,1")
end)
