-- ResourceTech.lua: which tech / civic unlocks the improvement of a resource (tile text, trees, city report)
stub("engine")
local world = stub("world").new{ width = 20, height = 14 }
world:install()
include("ResourceTech")
include("CityReportData")

local function rows(list) return function() local i = 0; return function() i = i + 1; return list[i] end end end
local function indexed(list, key)
	local t = {}
	for i, row in ipairs(list) do row.Index = i - 1; t[i - 1] = row; t[row[key]] = row end
	return t
end

GameInfo.Improvements = indexed({
	{ ImprovementType = "IMPROVEMENT_FARM", Name = "Farm" },
	{ ImprovementType = "IMPROVEMENT_MINE", Name = "Mine", PrereqTech = "TECH_BRONZE_WORKING" },
	{ ImprovementType = "IMPROVEMENT_PASTURE", Name = "Pasture", PrereqTech = "TECH_ANIMAL_HUSBANDRY" },
	{ ImprovementType = "IMPROVEMENT_PLANTATION", Name = "Plantation", PrereqTech = "TECH_IRRIGATION" },
	{ ImprovementType = "IMPROVEMENT_UNIQUE_MINE", Name = "Unique Mine", PrereqTech = "TECH_MINING", TraitType = "TRAIT_OTHER_CIV" },
	{ ImprovementType = "IMPROVEMENT_FISHING_BOATS", Name = "Fishing Boats", PrereqTech = "TECH_SAILING", Domain = "DOMAIN_SEA" },
	{ ImprovementType = "IMPROVEMENT_CHATEAU", Name = "Chateau", PrereqCivic = "CIVIC_HUMANISM" },
}, "ImprovementType")
GameInfo.Technologies = indexed({
	{ TechnologyType = "TECH_POTTERY", Name = "Pottery" },
	{ TechnologyType = "TECH_MINING", Name = "Mining" },
	{ TechnologyType = "TECH_BRONZE_WORKING", Name = "Bronze Working" },
	{ TechnologyType = "TECH_ANIMAL_HUSBANDRY", Name = "Animal Husbandry" },
	{ TechnologyType = "TECH_IRRIGATION", Name = "Irrigation" },
	{ TechnologyType = "TECH_SAILING", Name = "Sailing" },
}, "TechnologyType")
GameInfo.Civics = indexed({ { CivicType = "CIVIC_HUMANISM", Name = "Humanism" } }, "CivicType")
GameInfo.TechnologyPrereqs = rows{
	{ Technology = "TECH_BRONZE_WORKING", PrereqTech = "TECH_MINING" },
	{ Technology = "TECH_IRRIGATION", PrereqTech = "TECH_POTTERY" },
}
GameInfo.CivicPrereqs = rows{}
GameInfo.Improvement_ValidBuildUnits = rows{}
GameInfo.Improvement_ValidResources = rows{
	{ ImprovementType = "IMPROVEMENT_FARM", ResourceType = "RESOURCE_WHEAT" },
	{ ImprovementType = "IMPROVEMENT_MINE", ResourceType = "RESOURCE_IRON" },
	{ ImprovementType = "IMPROVEMENT_UNIQUE_MINE", ResourceType = "RESOURCE_IRON" },
	{ ImprovementType = "IMPROVEMENT_PASTURE", ResourceType = "RESOURCE_HORSES" },
	{ ImprovementType = "IMPROVEMENT_PASTURE", ResourceType = "RESOURCE_SHEEP" },
	{ ImprovementType = "IMPROVEMENT_PLANTATION", ResourceType = "RESOURCE_WINE" },
	{ ImprovementType = "IMPROVEMENT_FISHING_BOATS", ResourceType = "RESOURCE_FISH" },
	{ ImprovementType = "IMPROVEMENT_CHATEAU", ResourceType = "RESOURCE_SILVER" },
}

-- what the player has researched, and the turns each unresearched tech needs
local have = { TECH_MINING = true }
local turnsFor = { TECH_MINING = 2, TECH_BRONZE_WORKING = 3, TECH_ANIMAL_HUSBANDRY = 4, TECH_POTTERY = 2, TECH_IRRIGATION = 5, TECH_SAILING = 6 }
local haveCivic = {}
local techNames = {}
for i = 0, 5 do techNames[i] = GameInfo.Technologies[i].TechnologyType end
Players[0].GetTechs = function()
	return {
		HasTech = function(_, index) return have[techNames[index]] == true end,
		GetTurnsToResearch = function(_, index) return turnsFor[techNames[index]] end,
	}
end
Players[0].GetCulture = function()
	return { HasCivic = function() return haveCivic.humanism == true end, GetTurnsToProgressCivic = function() return 7 end }
end

local owned = {}
Map.GetCityPlots = function() return { GetPurchasedPlots = function() return owned end } end
world:city(0, 5, 5, "Rome")
world:city(0, 12, 8, "Antium")
local ROME = { GetX = function() return 5 end, GetY = function() return 5 end }

local function put(x, y, props, own)
	props.owner = own and 0 or -1
	world:set(x, y, props)
	if own then table.insert(owned, y * 20 + x) end
	return Map.GetPlot(x, y)
end

local iron = put(6, 5, { resource = "Iron" }, true)
local wheat = put(4, 5, { resource = "Wheat" }, true)
local wheatFarm = put(5, 4, { resource = "Wheat", improvement = 0 }, true)
local horses = put(5, 6, { resource = "Horses" }, true)
local sheep = put(7, 5, { resource = "Sheep" }, false)
local sheep2 = put(4, 6, { resource = "Sheep" }, true)
local wine = put(3, 5, { resource = "Wine" }, true)
local foreignIron = put(8, 8, { resource = "Iron", owner = 3 }, false)
foreignIron = Map.GetPlot(8, 8)
world:set(8, 8, { owner = 3 })
local fish = put(5, 3, { resource = "Fish", terrain = "water" }, true)
local silver = put(12, 9, { resource = "Silver" }, true)

test("a resource whose improvement needs a tech", function()
	local info = ResourceTech_Info(iron)
	eq(info.status, "needs")
	eq(info.improvement, "Mine")
	eq(info.need.name, "Bronze Working")
	eq(info.need.kind, "tech")
	eq(ResourceTech_Short(iron), "needs Bronze Working")
end)

test("a unique improvement of another civ is never named", function()
	eq(ResourceTech_Info(iron).improvement, "Mine")		-- not "Unique Mine" although Mining is known
end)

test("improvable now: possible on my tile, silent outside my borders", function()
	eq(ResourceTech_Info(wheat).status, "possible")
	eq(ResourceTech_Short(wheat), "farm possible")
	eq(ResourceTech_Short(sheep), "needs Animal Husbandry")
	have.TECH_ANIMAL_HUSBANDRY = true
	eq(ResourceTech_Short(sheep), nil)			-- unowned: nothing to build there
	eq(ResourceTech_Short(horses), "pasture possible")
	have.TECH_ANIMAL_HUSBANDRY = nil
end)

test("an improved tile says nothing", function()
	eq(ResourceTech_Info(wheatFarm).status, "improved")
	eq(ResourceTech_Info(wheatFarm).improvedWith, "Farm")
	eq(ResourceTech_Short(wheatFarm), nil)
	eq(ResourceTech_Full(wheatFarm), nil)
end)

test("foreign tiles and tiles without a resource are skipped", function()
	eq(ResourceTech_Short(foreignIron), nil)
	eq(ResourceTech_Short(Map.GetPlot(10, 10)), nil)
end)

test("sea resources need a sea improvement", function()
	eq(ResourceTech_Short(fish), "needs Sailing")
end)

test("a civic prerequisite", function()
	local info = ResourceTech_Info(silver)
	eq(info.need.kind, "civic")
	eq(ResourceTech_Short(silver), "needs Humanism")
	eq(ResourceTech_Turns(info.need), 7)
end)

test("full form: turns of research along the path", function()
	eq(ResourceTech_Full(iron), "Iron: Mine needs Bronze Working, 3 turns of research")
	eq(ResourceTech_Full(wine), "Wine: Plantation needs Irrigation, 7 turns of research")		-- Irrigation 5 + Pottery 2
	eq(ResourceTech_Full(wheat), "Wheat: Farm can be built now")
end)

test("a resource the player cannot see is not named", function()
	local real = Players[0].GetResources
	Players[0].GetResources = function() return { IsResourceVisible = function() return false end } end
	eq(ResourceTech_Info(iron), nil)
	eq(ResourceTech_Short(iron), nil)
	Players[0].GetResources = real
end)

test("path turns count each missing node once", function()
	local has = function(t) return have[t] == true end
	local turnsOf = function(t) return turnsFor[t] end
	eq(ResourceTech_PathTurns("tech", "TECH_BRONZE_WORKING", has, turnsOf), 3)
	have.TECH_MINING = nil
	eq(ResourceTech_PathTurns("tech", "TECH_BRONZE_WORKING", has, turnsOf), 5)
	have.TECH_MINING = true
	eq(ResourceTech_PathTurns("tech", "TECH_MINING", has, turnsOf), 0)
end)

test("tree scan: techs that improve resources near my cities, cheapest first", function()
	local groups = ResourceTech_Scan("tech")
	local names = {}
	for _, g in ipairs(groups) do table.insert(names, g.name) end
	-- Bronze Working 3 (Iron), Animal Husbandry 4 (Horses, 2 Sheep: one unowned inside range 3), Irrigation 7 (Wine), Sailing 6 (Fish)
	listeq(names, { "Bronze Working", "Animal Husbandry", "Sailing", "Irrigation" })
	local ah = groups[2]
	eq(ah.total, 3)
	eq(ResourceTech_NodePhrase(groups, "TECH_ANIMAL_HUSBANDRY"), "improves 2 Sheep and 1 Horses near your cities")
	eq(ResourceTech_NodePhrase(groups, "TECH_BRONZE_WORKING"), "improves 1 Iron near your cities")
	eq(ResourceTech_NodePhrase(groups, "TECH_POTTERY"), nil)
	eq(ResourceTech_GroupText(groups[1]), "Bronze Working, 3 turns: Iron near Rome")
	eq(ResourceTech_GroupText(groups[4]), "Irrigation, 7 turns, needs Pottery: Wine near Rome")
	eq(#ResourceTech_Scan("civic"), 1)
	eq(ResourceTech_Scan("civic")[1].name, "Humanism")
end)

test("city report resources entry", function()
	local city = { GetX = ROME.GetX, GetY = ROME.GetY }
	local res = ResourceTech_CityResources(city)
	eq(#res.improved, 1)
	eq(res.improved[1].name, "Wheat")
	local items = CityReport_BuildItems({ resources = res })
	local text
	for _, item in ipairs(items) do if item.key == "resources" then text = item.text end end
	contains(text, "Improved: Wheat (Farm)")
	contains(text, "Not improved: ")
	contains(text, "Iron, needs Bronze Working")
	contains(text, "Wheat, a builder can make a farm now")
end)
