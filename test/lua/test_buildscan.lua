-- BuildScan.lua: which tiles of a city can the builder improve, and in which order
stub("engine")
local world = stub("world").new{ width = 20, height = 14 }
world:install()
include("BuildScan")

local OPS = { BUILD = "BUILD_IMPROVEMENT" }
UnitOperationTypes = { BUILD_IMPROVEMENT = OPS.BUILD, PARAM_IMPROVEMENT_TYPE = "PARAM_IMP", REPAIR = "REPAIR" }

-- improvements: id -> row (also reachable by type name, like the game's tables)
local IMPS = {
	[0] = { ImprovementType = "IMPROVEMENT_FARM", Name = "Farm", Hash = 1000 },
	[1] = { ImprovementType = "IMPROVEMENT_MINE", Name = "Mine", Hash = 1001 },
	[2] = { ImprovementType = "IMPROVEMENT_PLANTATION", Name = "Plantation", Hash = 1002 },
}
local IMPROVEMENTS = {}
for id, row in pairs(IMPS) do IMPROVEMENTS[id] = row; IMPROVEMENTS[row.ImprovementType] = row end
GameInfo.Improvements = IMPROVEMENTS
GameInfo.Units = { [0] = { UnitType = "UNIT_BUILDER", BuildCharges = 3, Combat = 0, Name = "Builder" }, [1] = { UnitType = "UNIT_WARRIOR", Combat = 20 } }
GameInfo.Yields.YIELD_FOOD.Name = "Food"
GameInfo.Yields.YIELD_PRODUCTION.Name = "Production"
local function rows(list) return function() local i = 0; return function() i = i + 1; return list[i] end end end
GameInfo.Improvement_ValidBuildUnits = rows{
	{ UnitType = "UNIT_BUILDER", ImprovementType = "IMPROVEMENT_FARM" },
	{ UnitType = "UNIT_BUILDER", ImprovementType = "IMPROVEMENT_MINE" },
	{ UnitType = "UNIT_BUILDER", ImprovementType = "IMPROVEMENT_PLANTATION" },
}
GameInfo.Improvement_YieldChanges = rows{
	{ ImprovementType = "IMPROVEMENT_FARM", YieldType = "YIELD_FOOD", YieldChange = 1 },
	{ ImprovementType = "IMPROVEMENT_MINE", YieldType = "YIELD_PRODUCTION", YieldChange = 1 },
}
GameInfo.Improvement_ValidResources = rows{
	{ ImprovementType = "IMPROVEMENT_FARM", ResourceType = "RESOURCE_WHEAT" },
	{ ImprovementType = "IMPROVEMENT_PLANTATION", ResourceType = "RESOURCE_SILK" },
}
GameInfo.Yields = setmetatable({}, { __index = function(_, k)
	if k == "YIELD_FOOD" or k == 0 then return { Index = 0, Name = "Food" } end
	return { Index = 1, Name = "Production" }
end })

-- the engine's answer: improvements allowed per plot index (test sets allowed[index] = { [hash] = true })
local allowed, worked = {}, {}
UnitManager.CanStartOperation = function(_, op, plot, params)
	if op == "REPAIR" then return plot:IsImprovementPillaged() end
	local set = allowed[plot:GetIndex()]
	return set ~= nil and set[params.PARAM_IMP] == true
end
local city = {
	GetID = function() return 1 end, GetName = function() return "Rome" end, GetX = function() return 5 end, GetY = function() return 5 end,
	GetOwner = function() return 0 end,
	GetCitizens = function() return { IsPlotWorked = function(_, x, y) return worked[y * 20 + x] == true end } end,
}
local owned = {}
Map.GetCityPlots = function() return { GetPurchasedPlots = function() return owned end } end

local function own(x, y, hashes)
	local index = y * 20 + x
	table.insert(owned, index)
	if hashes then
		allowed[index] = {}
		for _, h in ipairs(hashes) do allowed[index][h] = true end
	end
	return index
end

local function builder(x, y)
	local u = world:unit(0, x, y, { moves = 2, unitType = 0, name = "Builder" })
	return world.fakeUnit(u)
end

test("a tile with a worked resource comes first, then worked tiles, then the rest by turns", function()
	local wheat = own(7, 5, { 1000 })
	world:set(7, 5, { resource = "Wheat" })
	local plain = own(6, 5, { 1000 })
	local nearWorked = own(6, 6, { 1001 })
	worked[6 * 20 + 6] = true
	local far = own(9, 5, { 1001 })
	local scan = BuildScan_Scan(builder(5, 6), city)
	eq(#scan.list, 4)
	eq(scan.list[1].plotIndex, wheat)
	eq(scan.list[1].resource, "Wheat")
	eq(scan.list[1].improvesResource, true)
	eq(scan.list[2].plotIndex, nearWorked)
	eq(scan.list[2].worked, true)
	eq(scan.list[3].plotIndex, plain)
	eq(scan.list[4].plotIndex, far)
	eq(scan.list[1].improvements[1].name, "Farm")
	eq(scan.list[1].improvements[1].yieldText, "plus 1 food")
end)

test("improvements: the one that works the resource first; improved and impossible tiles are skipped", function()
	owned = {}; allowed = {}; worked = {}
	local both = own(6, 5, { 1001, 1000 })
	world:set(6, 5, { resource = "Wheat" })
	own(7, 5, {})											-- nothing possible: left out
	own(8, 5, { 1000 })
	world:set(8, 5, { improvement = 0 })						-- already improved: left out
	local pillaged = own(9, 5, {})
	world:set(9, 5, { improvement = 0, pillaged = true })		-- pillaged: repair
	local scan = BuildScan_Scan(builder(5, 6), city)
	eq(#scan.list, 2)
	local first
	for _, e in ipairs(scan.list) do if e.plotIndex == both then first = e end end
	eq(first.improvements[1].name, "Farm")
	eq(first.improvements[2].name, "Mine")
	local repair
	for _, e in ipairs(scan.list) do if e.plotIndex == pillaged then repair = e end end
	eq(repair.improvements[1].repair, true)
	contains(repair.improvements[1].name, "pillaged Farm")
end)

test("unreachable tiles are dropped; no moves means nothing", function()
	owned = {}; allowed = {}; worked = {}
	local a = own(6, 5, { 1000 })
	local b = own(7, 5, { 1000 })
	world.unreachable = { [b] = true }
	local scan = BuildScan_Scan(builder(5, 6), city)
	eq(#scan.list, 1)
	eq(scan.list[1].plotIndex, a)
	world.unreachable = nil
	local tired = world.fakeUnit(world:unit(0, 5, 6, { moves = 0, unitType = 0 }))
	local none = BuildScan_Scan(tired, city)
	eq(#none.list, 0)
	eq(none.noMoves, true)
end)

test("only builders: a warrior has no improvement list", function()
	local warrior = world.fakeUnit(world:unit(0, 5, 6, { moves = 2, unitType = 1 }))
	eq(BuildScan_Improvements(warrior), nil)
	eq(#BuildScan_Improvements(builder(5, 6)), 3)
end)

test("cities nearest to the builder first", function()
	world:city(0, 12, 8, "Ottawa")
	world:city(0, 3, 3, "Rome")
	local list = BuildScan_Cities(builder(4, 4))
	eq(list[1].name, "Rome")
	eq(list[2].name, "Ottawa")
end)
