-- CityReportData.lua: plain city table -> report items
stub("engine")
include("CityReportData")

local function city()
	return {
		name = "Rome", population = 6, foodSurplus = 4,
		yields = {
			food = { value = 9, tooltip = "+3 [ICON_Food] from Pasture[NEWLINE]+6 from tiles" },
			production = { value = 12, tooltip = "" }, gold = { value = 8, tooltip = "" },
			science = { value = 6, tooltip = "" }, culture = { value = 3, tooltip = "" }, faith = { value = 2.5, tooltip = "" },
		},
		growth = { occupied = false, turnsUntilGrowth = 11, housingMultiplier = 1, housing = 14, foodPerTurn = 9, foodNeeded = 30,
			happinessGrowthModifier = 0, otherGrowthModifier = 0, occupationMultiplier = 0, housingAdvice = "",
			housingSources = { fromBuildings = 2, fromWater = 3, fromCivics = 0 } },
		amenities = { have = 3, needed = 2, mood = "Content", growthPercent = 0, yieldPercent = 0, advice = "",
			sources = { { label = "luxuries", value = 4 }, { label = "civics", value = 0 } }, losses = { { label = "war weariness", value = -1 } } },
		defense = { hp = 200, hpMax = 200, wall = 100, wallMax = 100, strength = 28, underSiege = false },
		production = { name = "Builder", turns = 1, percent = 0.5, description = "", queued = 2 },
		districts = {
			{ name = "City Center", pillaged = false, buildings = { { name = "Palace", pillaged = false } }, yield = "" },
			{ name = "Campus", pillaged = false, buildings = { { name = "Library", pillaged = true } }, yield = "+2 Science" },
			{ name = "Commercial Hub", pillaged = false, buildings = {}, yield = "" },
		},
		wonders = { { name = "Pyramids", pillaged = false } }, buildingsNum = 2, districtsCount = 2, districtsMax = 3,
		citizens = { total = 6, specialists = 1, working = 5, byDistrict = { { name = "Campus", count = 1 } }, favored = {} },
		religion = { beliefs = {}, others = {} },
		tradingPosts = {},
	}
end

local function find(items, key)
	for _, item in ipairs(items) do if item.key == key then return item end end
end

test("a base game city gives 8 items in order", function()
	local items = CityReport_BuildItems(city())
	local keys = {}
	for i, item in ipairs(items) do keys[i] = item.key end
	eq(table.concat(keys, ","), "yields,growth,amenities,defense,production,districts,citizens,religion")
	for _, item in ipairs(items) do
		istrue(item.text ~= nil and item.text ~= "", item.key .. " has text")
		istrue(item.detail ~= nil and item.detail ~= "", item.key .. " has detail")
	end
end)

test("yields: food is the surplus, others the amount", function()
	local item = find(CityReport_BuildItems(city()), "yields")
	eq(item.text, "Yields: food plus 4, production 12, gold 8, science 6, culture 3, faith 2.5")
	contains(item.detail, "Pasture")
end)

test("growth: normal, starving, stopped by housing, occupied", function()
	local d = city()
	eq(find(CityReport_BuildItems(d), "growth").text, "Population 6, plus 4 food, grows in 11 turns, housing 6 of 14")
	d.growth.turnsUntilGrowth = -3; d.foodSurplus = -2
	contains(find(CityReport_BuildItems(d), "growth").text, "starving, loses a citizen in 3 turns")
	d = city(); d.growth.turnsUntilGrowth = 0; d.growth.housingMultiplier = 0
	contains(find(CityReport_BuildItems(d), "growth").text, "growth stopped: housing")
	d = city(); d.growth.occupied = true
	contains(find(CityReport_BuildItems(d), "growth").text, "occupied")
	d = city(); d.growth.housingMultiplier = 0.25
	contains(find(CityReport_BuildItems(d), "growth").text, "slowed 75 percent by housing")
	contains(find(CityReport_BuildItems(city()), "growth").detail, "from buildings 2, water 3")
end)

test("amenities", function()
	local item = find(CityReport_BuildItems(city()), "amenities")
	eq(item.text, "Amenities 3 of 2, Content")
	contains(item.detail, "luxuries plus 4")
	contains(item.detail, "war weariness minus 1")
	local d = city(); d.amenities.growthPercent = -10; d.amenities.yieldPercent = -10
	contains(find(CityReport_BuildItems(d), "amenities").text, "growth minus 10 percent")
end)

test("loyalty only when present", function()
	local d = city()
	eq(find(CityReport_BuildItems(d), "loyalty"), nil)
	d.loyalty = { current = 100, max = 100, perTurn = 8, level = "Loyal", sources = { { label = "Governor", value = 8 } },
		influence = { { name = "Rome", value = 20 } }, rival = "Greece" }
	local item = find(CityReport_BuildItems(d), "loyalty")
	eq(item.text, "Loyalty 100, plus 8 per turn, Loyal, may turn to Greece")
	contains(item.detail, "Governor plus 8")
	contains(item.detail, "Rome 20")
end)

test("defense and siege", function()
	local d = city()
	eq(find(CityReport_BuildItems(d), "defense").text, "Health 200 of 200, walls 100 of 100, defense strength 28")
	d.defense.underSiege = true; d.defense.wallMax = 0
	eq(find(CityReport_BuildItems(d), "defense").text, "Health 200 of 200, no walls, defense strength 28, under siege")
end)

test("production", function()
	local d = city()
	eq(find(CityReport_BuildItems(d), "production").text, "Production: Builder, 1 turn, 2 more queued, Tab opens production")
	d.production = { name = "" }
	eq(find(CityReport_BuildItems(d), "production").text, "Production: nothing, Tab opens production")
end)

test("districts, buildings, wonders", function()
	local item = find(CityReport_BuildItems(city()), "districts")
	eq(item.text, "Districts: City Center (Palace), Campus (Library (pillaged)), Commercial Hub. Wonders: Pyramids")
	contains(item.detail, "Commercial Hub: no buildings")
	contains(item.detail, "yields +2 Science")
end)

test("citizens", function()
	local item = find(CityReport_BuildItems(city()), "citizens")
	eq(item.text, "6 citizens: 5 working tiles, 1 specialist")
	contains(item.detail, "Specialists: Campus 1")
end)

test("religion", function()
	local d = city()
	eq(find(CityReport_BuildItems(d), "religion").text, "Religion: none")
	d.religion = { majorityName = "Judaism", majorityFollowers = 3, beliefs = { "Tithe" }, others = { { name = "Islam", followers = 1 } } }
	eq(find(CityReport_BuildItems(d), "religion").text, "Religion: Judaism, 3 followers")
	contains(find(CityReport_BuildItems(d), "religion").detail, "Islam 1")
end)

test("great works and trading posts are optional items", function()
	local d = city()
	d.greatWorks = { slots = 3, filled = 1, names = { "Mona Lisa" } }
	d.tradingPosts = { "Greece", "Egypt" }
	local items = CityReport_BuildItems(d)
	eq(find(items, "greatworks").text, "Great works: 1 of 3 slots, Mona Lisa")
	eq(find(items, "tradingposts").text, "Trading posts: Greece, Egypt")
end)

test("a broken section loses only itself", function()
	local d = city()
	d.defense = nil
	local items = CityReport_BuildItems(d)
	eq(find(items, "defense"), nil)
	istrue(find(items, "citizens") ~= nil)
end)
