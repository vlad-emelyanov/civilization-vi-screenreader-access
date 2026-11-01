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

test("Loss: a worked Farm on Wheat costs more than any plain tile; the wording names what it stands on", function()
	local farm = { improvement = "Farm", resource = "Wheat", rclass = "bonus", worked = true, food = 4 }
	eq(PlacementScan_Loss(farm, 5), 6)
	eq(PlacementScan_Loss(farm, 1), 10)		-- a city that barely grows: the food counts again
	eq(PlacementScan_LossText(farm), "removes Farm on Wheat, a citizen works it")
	eq(PlacementScan_LossText({ improvement = "Lumber Mill", feature = "Woods" }), "removes Lumber Mill on Woods")
	eq(PlacementScan_LossText({ improvement = "Mine" }), "removes Mine")
	eq(PlacementScan_LossText({ feature = "Woods", resource = "Deer" }), "removes Woods and Deer")
	eq(PlacementScan_LossText({}), "")
	eq(PlacementScan_Loss({ worked = true, food = 2 }, 0), 0)		-- nothing removed: no loss
	eq(PlacementScan_Loss({ resource = "Iron", rclass = "strategic" }, 5), 4)
end)

test("Sort: a Farm on Wheat loses to a plain tile unless its adjacency leads by more than the loss", function()
	local function c(i, total, loss) return { plotIndex = i, owned = true, total = total, loss = loss, removes = loss > 0 and { "Farm" } or {}, distance = i } end
	local scan = { kind = "district", list = { c(1, 2, 6), c(2, 2, 0), c(3, 9, 6) } }
	PlacementScan_Sort(scan)
	eq(scan.list[1].plotIndex, 3)		-- 9 - 6 beats 2
	eq(scan.list[2].plotIndex, 2)
	eq(scan.list[3].plotIndex, 1)
	scan = { kind = "district", list = { c(1, 2, 6), c(2, 2, 0) } }
	PlacementScan_Sort(scan)
	eq(scan.list[1].plotIndex, 2)
end)

test("Sort: equal score and loss keeps owned, then nearer", function()
	local function c(i, owned, dist) return { plotIndex = i, owned = owned, total = 1, loss = 0, removes = {}, distance = dist } end
	local scan = { kind = "district", list = { c(1, false, 1), c(2, true, 3), c(3, true, 2) } }
	PlacementScan_Sort(scan)
	eq(scan.list[1].plotIndex, 3)
	eq(scan.list[2].plotIndex, 2)
end)

test("Sort: wonders prefer the smaller loss among owned tiles", function()
	local function c(i, loss) return { plotIndex = i, owned = true, total = 0, loss = loss, removes = loss > 0 and { "Farm" } or {}, distance = 1 } end
	local scan = { kind = "wonder", list = { c(1, 6), c(2, 0), c(3, 2) } }
	PlacementScan_Sort(scan)
	eq(scan.list[1].plotIndex, 2)
	eq(scan.list[3].plotIndex, 1)
end)

-- The real scan: a worked Farm on Wheat and a plain tile with the same adjacency (0). Best is the plain one, the Farm says what it removes.
test("Scan: wiring - loss, wording and Best through PlacementScan_Scan", function()
	world:set(3, 3, { owner = 0, improvement = 0, resource = "Wheat", food = 4 })
	world:set(4, 3, { owner = 0 })
	GameInfo.Improvements[0] = { Name = "Farm" }
	GameInfo.Districts = { [9] = { Index = 9, Name = "Neighbourhood", DistrictType = "DISTRICT_NEIGHBORHOOD", OnePerCity = true, Housing = 0 } }
	GameInfo.AppealHousingChanges = function() return function() return nil end end
	GameInfo.Yields[0] = { Name = "Food" }
	GameInfo.Yields[1] = { Name = "Production" }
	Strings.LOC_DISTRICT_ZONE_WILL_REMOVE_FEATURE = "Will remove the {1_Feature} on this tile."
	Strings.LOC_DISTRICT_ZONE_WILL_HARVEST_RESOURCE = "Will remove the {1_Resource} on this tile."
	Strings.LOC_DISTRICT_ZONE_WILL_REMOVE_IMPROVEMENT = "Will remove the {1_Improvement} on this tile."
	for _, xy in ipairs{ {3, 3}, {4, 3} } do
		local plot = Map.GetPlot(xy[1], xy[2])
		local worked = xy[1] == 3
		function plot:GetWorkerCount() return worked and 1 or 0 end
		function plot:GetAdjacencyYield() return 0 end
		function plot:GetAdjacencyBonusTooltip() return "" end
		function plot:GetAppeal() return 0 end
	end
	local farmIndex, plainIndex = Map.GetPlot(3, 3):GetIndex(), Map.GetPlot(4, 3):GetIndex()
	CityManager = {
		GetOperationTargets = function() return { plots = { farmIndex, plainIndex } } end,
		GetCommandTargets = function() return {} end,
		CanStartOperation = function(_, _, params)
			if params.x == 3 then return true, { ok = { "Will remove the Wheat on this tile.", "Will remove the Farm on this tile." } } end
			return true, { ok = {} }
		end,
	}
	UI = UI or {}
	UI.GetInterfaceModeParameter = function() return nil end
	local city = { GetX = function() return 5 end, GetY = function() return 5 end, GetID = function() return 1 end, GetOwner = function() return 0 end,
		GetName = function() return "Lugdunum" end, GetGrowth = function() return { GetFoodSurplus = function() return 1 end } end }
	local scan = PlacementScan_Scan(city, "district", 9)
	eq(#scan.list, 2)
	eq(scan.best.plotIndex, plainIndex)
	local farm = scan.byIndex[farmIndex]
	eq(farm.lossText, "removes Farm on Wheat, a citizen works it")
	eq(farm.loss, 2 + 2 + 2 + 4)		-- improvement, bonus resource, worked, tile food again (surplus 1)
	eq(farm.tileYields, "4 food, 1 production")
	eq(scan.byIndex[plainIndex].lossText, "")
end)
