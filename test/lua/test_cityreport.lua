-- CityReportData.lua: plain city table -> report items
stub("engine")
include("CityReportData")
-- strings carry [KEY:kb|button] tokens (SRKey): compare the keyboard wording
local rawEq = eq
local function eq(actual, expected, msg)
	if type(actual) == "string" then actual = actual:gsub("%[KEY:([^%]|]+)|?[^%]]*%]", "%1") end
	rawEq(actual, expected, msg)
end

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
	eq(table.concat(keys, ","), "yields,growth,amenities,religion,defense,production,districts,citizens")
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
	eq(find(CityReport_BuildItems(d), "growth").text, "Population 6 of 14 housing, plus 4 food, grows in 11 turns")
	d.growth.housing = 6
	eq(find(CityReport_BuildItems(d), "growth").text, "Population 6 of 6 housing, housing full, plus 4 food, grows in 11 turns")
	d.growth.housing = 7
	eq(find(CityReport_BuildItems(d), "growth").text, "Population 6 of 7 housing, 1 free housing, plus 4 food, grows in 11 turns")
	d = city()
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
	eq(item.text, "Loyalty 100, plus 8 per turn, Loyal")
	contains(item.detail, "The city would turn to Greece if loyalty ran out")
	d.loyalty.levelIndex = 3
	eq(find(CityReport_BuildItems(d), "loyalty").text, "Loyalty 100, plus 8 per turn, Loyal")
	d.loyalty.levelIndex = 2; d.loyalty.level = "Content"
	eq(find(CityReport_BuildItems(d), "loyalty").text, "Loyalty 100, plus 8 per turn, Content, may turn to Greece")
	d.loyalty.levelIndex = 3; d.loyalty.level = "Loyal"; d.loyalty.perTurn = -2
	eq(find(CityReport_BuildItems(d), "loyalty").text, "Loyalty 100, minus 2 per turn, Loyal, may turn to Greece")
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
	rawEq(find(CityReport_BuildItems(d), "production").text:find("[KEY:Tab] opens production", 1, true) ~= nil, true)
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

test("religion rows: majority, no majority, none, pantheon, next, holy city", function()
	local d = city()
	d.population = 11
	d.religion = { beliefs = { "Tithe" }, others = {}, citizens = 11, pantheon = "Fertility Rites",
		majority = { name = "Eastern Orthodoxy", followers = 6 },
		rows = { { name = "Eastern Orthodoxy", followers = 6, pressure = 4 }, { name = "Buddhism", followers = 1, pressure = 1 } },
		majorityName = "Eastern Orthodoxy", holyCityOf = "Eastern Orthodoxy" }
	local item = find(CityReport_BuildItems(d), "religion")
	eq(item.text, "Religion: Eastern Orthodoxy majority, 6 of 11 citizens, others Buddhism 1, holy city of Eastern Orthodoxy")
	contains(item.detail, "Pressure per turn: Eastern Orthodoxy 4, Buddhism 1")
	contains(item.detail, "Pantheon: Fertility Rites")
	d.religion.nextName = "Buddhism"; d.religion.nextTurns = 5; d.religion.holyCityOf = nil
	contains(find(CityReport_BuildItems(d), "religion").text, ", turns to Buddhism in 5 turns")
	d.population = 8
	d.religion = { beliefs = {}, others = {}, citizens = 8, rows = { { name = "Eastern Orthodoxy", followers = 2 }, { name = "Buddhism", followers = 1 } } }
	eq(find(CityReport_BuildItems(d), "religion").text, "Religion: no majority. Eastern Orthodoxy 2, Buddhism 1, of 8 citizens")
	d.religion = { beliefs = {}, others = {}, citizens = 8, rows = {}, pantheon = "Fertility Rites" }
	eq(find(CityReport_BuildItems(d), "religion").text, "Religion: none, pantheon Fertility Rites")
	d.religion = { beliefs = {}, others = {}, citizens = 8, rows = {} }
	eq(find(CityReport_BuildItems(d), "religion").text, "Religion: none")
end)

test("religion comes right after loyalty", function()
	local d = city()
	d.loyalty = { current = 100, max = 100, perTurn = 8, level = "Loyal", sources = {}, influence = {} }
	local keys = {}
	for i, item in ipairs(CityReport_BuildItems(d)) do keys[i] = item.key end
	eq(table.concat(keys, ","), "yields,growth,amenities,loyalty,religion,defense,production,districts,citizens")
end)

test("power: underpowered, powered, none needed, generates only, absent", function()
	local d = city()
	eq(find(CityReport_BuildItems(d), "power"), nil)
	d.power = { current = 4, required = 6, generatedTotal = 0, status = "underpowered", description = "Buildings work at half speed.",
		consumed = { { label = "Coal Power Plant", value = 4 } }, needed = { { label = "Factory", value = 2 }, { label = "Stadium", value = 4 } },
		generated = {}, advice = "Build a power plant." }
	local item = find(CityReport_BuildItems(d), "power")
	eq(item.text, "Power 4 of 6 needed, underpowered")
	contains(item.detail, "From: Coal Power Plant 4. Needed by: Factory 2, Stadium 4. Build a power plant")
	eq(item.detail:find("..", 1, true), nil)
	eq(item.detail:sub(-1) ~= ".", true)
	d.power = { current = 6, required = 6, generatedTotal = 0, status = "powered", consumed = {}, needed = {}, generated = {} }
	eq(find(CityReport_BuildItems(d), "power").text, "Power 6 of 6, powered")
	d.power = { current = 0, required = 0, generatedTotal = 0, status = "none" }
	eq(find(CityReport_BuildItems(d), "power"), nil)
	d.power = { current = 0, required = 0, generatedTotal = 8, status = "none", generated = { { label = "Coal Power Plant", value = 8 } } }
	item = find(CityReport_BuildItems(d), "power")
	eq(item.text, "Power: none needed, generates 8")
	contains(item.detail, "Generates: Coal Power Plant 8")
end)

test("power: doubled source name is said once", function()
	local d = city()
	d.power = { current = 3, required = 3, generatedTotal = 0, status = "powered",
		consumed = { { label = "Rome Rome", value = 2 }, { label = "Coal Power Plant Coal Power Plant", value = 1 }, { label = "Rome Hall", value = 1 } } }
	contains(find(CityReport_BuildItems(d), "power").detail, "From: Rome 2, Coal Power Plant 1, Rome Hall 1")
end)

test("power comes right after loyalty", function()
	local d = city()
	d.loyalty = { current = 100, max = 100, perTurn = 8, level = "Loyal", sources = {}, influence = {} }
	d.power = { current = 2, required = 2, generatedTotal = 0, status = "powered" }
	local keys = {}
	for i, item in ipairs(CityReport_BuildItems(d)) do keys[i] = item.key end
	eq(table.concat(keys, ","), "yields,growth,amenities,loyalty,power,religion,defense,production,districts,citizens")
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

local function manage()
	return {
		focus = { { key = "food", name = "Food", state = "normal" }, { key = "gold", name = "Gold", state = "ignored" } },
		tiles = {
			{ key = "t5", plotIndex = 5, relative = "2 tiles north-east", desc = "Grassland, Farm, 3 Food 1 Production", count = 1, max = 1, locked = true },
			{ key = "t6", plotIndex = 6, relative = "1 tile west", desc = "Plains, 1 Food 1 Production", count = 0, max = 1, locked = false },
		},
		districts = { { key = "d9", plotIndex = 9, name = "Campus", count = 1, max = 2, perSlot = "+2 science", locked = false } },
		buy = { { key = "b7", plotIndex = 7, relative = "3 tiles east", desc = "Hills, 2 Production", cost = 60 } },
		gold = 40,
	}
end

test("management items are absent without d.manage", function()
	local items = CityReport_BuildItems(city())
	eq(find(items, "focus"), nil)
	eq(find(items, "tiles"), nil)
	eq(find(items, "specialists"), nil)
end)

test("management items: focus, tiles, specialists", function()
	local d = city()
	d.manage = manage()
	local items = CityReport_BuildItems(d)
	eq(find(items, "focus").text, "Focus: none, ignoring gold. Enter to change")
	eq(find(items, "focus").manage, "focus")
	eq(find(items, "tiles").text, "Tiles: 5 of 6 citizens on tiles. Enter to manage")
	eq(find(items, "specialists").text, "Specialists: 1 of 2 slots in Campus. Enter to manage")
	d.manage.focus[1].state = "favored"
	d.manage.focus[2].state = "normal"
	eq(find(CityReport_BuildItems(d), "focus").text, "Focus: food. Enter to change")
	d.manage.districts = {}
	eq(find(CityReport_BuildItems(d), "specialists"), nil)
end)

test("tile lines", function()
	local items = CityManage_TileItems(manage())
	eq(#items, 3)
	eq(items[1].text, "2 tiles north-east, Grassland, Farm, 3 Food 1 Production, worked, locked")
	eq(items[2].text, "1 tile west, Plains, 1 Food 1 Production, not worked")
	eq(items[3].text, "3 tiles east, Hills, 2 Production, can buy, 60 gold, need 20 more")
	eq(CityManage_TileState(items[1].tile), "Locked")
	eq(CityManage_TileState(items[2].tile), "Not worked")
	items[1].tile.locked = false
	eq(CityManage_TileState(items[1].tile), "Worked, not locked")
end)

test("district and focus lines, totals", function()
	local m = manage()
	eq(CityManage_DistrictItems(m)[1].text, "Campus, 1 of 2 specialists, +2 science each")
	local f = CityManage_FocusItems(m)
	eq(#f, 4)
	eq(f[1].text, "Food focus, off")
	eq(f[3].text, "Ignore food, off")
	eq(f[4].text, "Ignore gold, on")
	eq(CityManage_Totals(city()), "Food plus 4, production 12")
end)
