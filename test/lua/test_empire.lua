-- EmpireText.lua (pure wording of the empire overview) and HubEmpire.lua (gather + list) against stubbed engine objects
stub("engine")
include("ScreenReader")
include("KeyNavList")
include("EmpireText")

local function city(extra)
	local d = {
		name = "Rome", population = 8, foodSurplus = 4,
		growth = { occupied = false, turnsUntilGrowth = 4, housing = 14, housingMultiplier = 1 },
		amenities = { have = 3, needed = 2, mood = "Content" },
		defense = { wallMax = 100, underSiege = false },
		production = { name = "Harbor", turns = 5 },
	}
	for k, v in pairs(extra or {}) do d[k] = v end
	return d
end

local function facts(extra)
	local f = EmpireText.FactsFromReport(city())
	for k, v in pairs(extra or {}) do if v == "NONE" then f[k] = nil else f[k] = v end end
	return f
end

local function texts(problems)
	local out = {}
	for i, p in ipairs(problems) do out[i] = p.text end
	return out
end

test("a healthy city has no problems and a plain line", function()
	local f = facts()
	eq(#EmpireText.CityProblems(f), 0)
	eq(EmpireText.CityLine(f, 0), "Rome, population 8, growing in 4 turns, Harbor 5 turns")
end)

test("city line: problems, no production, starving", function()
	local f = facts({ production = "NONE", productionTurns = "NONE", turnsUntilGrowth = -2, foodSurplus = -3 })
	eq(EmpireText.CityLine(f, 3), "Rome, population 8, starving, no production, 3 problems")
	eq(EmpireText.CityLine(f, 1), "Rome, population 8, starving, no production, 1 problem")
end)

test("starving, most urgent first", function()
	local f = facts({ turnsUntilGrowth = -2, foodSurplus = -3, production = "NONE", productionTurns = "NONE" })
	listeq(texts(EmpireText.CityProblems(f)), {
		"Rome is starving, food minus 3, loses a citizen in 2 turns",
		"Rome: no production",
	})
end)

test("danger, siege and loyalty come before hunger", function()
	local f = facts({ danger = { count = 3, civ = "Egypt" }, underSiege = true, loyaltyTurnsToLoss = 4, loyaltyPerTurn = -6, loyalty = 40,
		turnsUntilGrowth = -1, foodSurplus = -1 })
	listeq(texts(EmpireText.CityProblems(f)), {
		"Rome in danger, 3 units of Egypt near",
		"Rome under siege",
		"Rome loyalty falling, lost in 4 turns",
		"Rome is starving, food minus 1, loses a citizen in 1 turn",
	})
end)

test("unhappy names the mood and the deficit", function()
	local f = facts({ amenitiesHave = 1, amenitiesNeeded = 3, mood = "Unhappy" })
	listeq(texts(EmpireText.CityProblems(f)), { "Rome unhappy, amenities minus 2" })
	f.mood = ""
	listeq(texts(EmpireText.CityProblems(f)), { "Rome unhappy, amenities minus 2" })
end)

test("housing: full in N turns, and full with growth stopped", function()
	local f = facts({ housing = 9 })
	listeq(texts(EmpireText.CityProblems(f)), { "Rome: housing full in 4 turns" })
	f = facts({ housing = 8, turnsUntilGrowth = 0, housingMultiplier = 0 })
	listeq(texts(EmpireText.CityProblems(f)), { "Rome: housing full, growth stopped" })
	f = facts({ housing = 8, foodSurplus = 0 })
	eq(#EmpireText.CityProblems(f), 0, "no surplus: housing is not the limit")
	f = facts({ housing = 9, occupied = true })
	eq(#EmpireText.CityProblems(f), 0, "an occupied city does not grow")
end)

test("slow production from 20 turns on", function()
	local f = facts({ production = "Harbor", productionTurns = 24 })
	listeq(texts(EmpireText.CityProblems(f)), { "Rome: Harbor takes 24 turns" })
	eq(#EmpireText.CityProblems(facts({ productionTurns = 19 })), 0)
end)

test("undefended city next to an enemy; falling loyalty without a conversion date", function()
	local f = facts({ undefended = { enemy = "Egypt" }, loyaltyPerTurn = -2, loyalty = 71, loyaltyLevel = 2, loyaltyTopLevel = 3 })
	listeq(texts(EmpireText.CityProblems(f)), {
		"Rome undefended, no garrison and no walls, at war with Egypt",
		"Rome loyalty 71, falling 2 a turn",
	})
	-- a loyal city (top level) that loses a little is not a problem
	eq(#EmpireText.CityProblems(facts({ loyaltyPerTurn = -2, loyalty = 99, loyaltyLevel = 3, loyaltyTopLevel = 3 })), 0)
end)

test("attention list merges the cities by urgency, then name", function()
	local a = EmpireText.CityProblems(facts({ name = "Setia", production = "Harbor", productionTurns = 24 }))
	local b = EmpireText.CityProblems(facts({ name = "Rome", turnsUntilGrowth = -2, foodSurplus = -3 }))
	local c = EmpireText.CityProblems(facts({ name = "Antium", production = "NONE", productionTurns = "NONE" }))
	local all = {}
	for _, list in ipairs{ a, b, c } do for _, p in ipairs(list) do table.insert(all, p) end end
	local sorted = EmpireText.Attention(all)
	listeq(texts(sorted), {
		"Rome is starving, food minus 3, loses a citizen in 2 turns",
		"Antium: no production",
		"Setia: Harbor takes 24 turns",
	})
end)

test("city order: biggest first, then name", function()
	local list = { { name = "Ostia", population = 3 }, { name = "Rome", population = 8 }, { name = "Antium", population = 3 } }
	table.sort(list, EmpireText.CityLess)
	eq(list[1].name .. list[2].name .. list[3].name, "RomeAntiumOstia")
end)

test("city summary: yields, growth, amenities, production lines of the report", function()
	local items = {
		{ key = "yields", text = "Yields: food plus 4" }, { key = "growth", text = "Population 8 of 14 housing" },
		{ key = "borders", text = "Borders" }, { key = "amenities", text = "Amenities 3 of 2" }, { key = "production", text = "Production: Harbor" },
	}
	eq(EmpireText.CitySummary("Rome", items), "Rome. Yields: food plus 4. Population 8 of 14 housing. Amenities 3 of 2. Production: Harbor")
end)

test("units: idle builders, orders, soldiers, busy; empty", function()
	local items = EmpireText.UnitItems{ total = 20, needOrders = 7, needNames = { Warrior = 4, Builder = 3 }, idle = { Builder = 3 },
		soldiers = 12, formation = 4, busy = { fortified = 5, moving = 2, exploring = 1 } }
	local out = {}
	for i, item in ipairs(items) do out[i] = item.text end
	listeq(out, { "3 Builders idle", "7 units need orders", "12 soldiers, 4 in formation", "Busy: 5 fortified, 1 exploring, 2 moving" })
	eq(items[2].detail, "Need orders: 3 Builders, 4 Warriors")
	items = EmpireText.UnitItems{ total = 1, needOrders = 1, needNames = { Scout = 1 }, idle = {}, soldiers = 1, formation = 0, busy = {} }
	eq(items[1].text, "1 unit needs orders")
	eq(items[2].text, "1 soldier")
	items = EmpireText.UnitItems{ total = 0, needOrders = 0, idle = {}, soldiers = 0, formation = 0, busy = {} }
	eq(items[1].text, "No units")
	eq(items[1].noAction, true)
end)

test("victory lines", function()
	eq(EmpireText.VictoryLine{ kind = "science", done = 1, total = 4, next = "Launch Moon Landing", leaderName = "Russia", leaderDone = 2 },
		"Science: 1 of 4 milestones, next Launch Moon Landing; leader Russia, 2 of 4")
	eq(EmpireText.VictoryLine{ kind = "science", done = 2, total = 4, next = "Build Spaceport", leaderIsYou = true },
		"Science: 2 of 4 milestones, next Build Spaceport; you lead")
	eq(EmpireText.VictoryLine{ kind = "science", done = 4, total = 4, lightYears = 120, lightTotal = 500, leaderIsYou = true },
		"Science: 4 of 4 milestones, light years 120 of 500; you lead")
	eq(EmpireText.VictoryLine{ kind = "culture", visiting = 120, required = 400, leaderName = "Unmet civilization", leaderVisiting = 200, leaderRequired = 380 },
		"Culture: 120 of 400 foreign tourists; leader Unmet civilization, 200 of 380")
	eq(EmpireText.VictoryLine{ kind = "domination", held = 1, total = 6, leaderName = "Egypt", leaderHeld = 3 },
		"Domination: you hold 1 of 6 capitals; leader Egypt, holds 3")
	eq(EmpireText.VictoryLine{ kind = "religion", hasReligion = true, converted = 1, total = 5, leaderName = "Greece", leaderConverted = 3 },
		"Religion: followers majority in 1 of 5 civs; leader Greece, 3 of 5")
	eq(EmpireText.VictoryLine{ kind = "religion", hasReligion = false, converted = 0, total = 5, leaderName = "Greece", leaderConverted = 3 },
		"Religion: you have not founded a religion; leader Greece, 3 of 5")
	eq(EmpireText.VictoryLine{ kind = "diplomatic", points = 8, required = 20, leaderName = "Russia", leaderPoints = 12 },
		"Diplomatic: 8 of 20 victory points; leader Russia, 12")
	eq(EmpireText.VictoryLine{ kind = "score", score = 480, position = 1, count = 6, leaderIsYou = true, endTurn = 500 },
		"Score: 480, first of 6; you lead; game ends turn 500")
	eq(EmpireText.VictoryLine{ kind = "score", score = 300, position = 3, count = 6, leaderName = "Russia", leaderScore = 520, endTurn = 0 },
		"Score: 300, third of 6; leader Russia, 520")
	eq(EmpireText.VictoryLine{ kind = "other", name = "Proxy War", position = 2, leaderName = "Egypt" },
		"Proxy War: you are second; leader Egypt")
end)

test("ranking detail", function()
	eq(EmpireText.Ranking{ { name = "Russia", text = "2 of 4" }, { name = "You", text = "1 of 4" } }, "Ranking: 1. Russia, 2 of 4. 2. You, 1 of 4")
	eq(EmpireText.Ranking{}, "No ranking")
end)

test("standing: wars, militaries, era", function()
	local items = EmpireText.StandingItems{ met = 3, atWar = { "Egypt", "Rome" }, cityStatesAtWar = 1,
		military = { { name = "Russia", value = 340, atWar = false }, { name = "Egypt", value = 200.4, atWar = true } }, myMilitary = 120, eraTurns = 5 }
	eq(items[1].text, "At war with Egypt, Rome and 1 city-state")
	eq(items[2].text, "Strongest militaries: Russia 340; Egypt 200.4, at war; your military 120")
	eq(items[3].text, "Next era in 5 turns")
	items = EmpireText.StandingItems{ met = 2, atWar = {}, military = {} }
	eq(items[1].text, "At peace with all 2 civilizations you have met")
	eq(#items, 1)
	items = EmpireText.StandingItems{ met = 0, atWar = {}, military = {} }
	eq(items[1].text, "You have not met any civilization")
end)

test("opening line", function()
	eq(EmpireText.OpenLine(3, 8, 7), "Empire, 3 need attention, 8 cities, 7 units need orders")
	eq(EmpireText.OpenLine(1, 1, 1), "Empire, 1 needs attention, 1 city, 1 unit needs orders")
	eq(EmpireText.OpenLine(0, 8, 0), "Empire, nothing urgent, 8 cities")
end)

-- ---------------------------------------------------------------------------
--	HubEmpire: gather and list against stubs
-- ---------------------------------------------------------------------------
local CITY_DATA = {
	Rome = city({ name = "Rome", population = 8, foodSurplus = -3, growth = { occupied = false, turnsUntilGrowth = -2, housing = 14, housingMultiplier = 1 } }),
	Setia = city({ name = "Setia", population = 5, production = { name = "Harbor", turns = 24 } }),
}

local function makeUnit(id, name, combat, activity)
	return { GetID = function() return id end, GetName = function() return name end, GetCombat = function() return combat end,
		GetRangedCombat = function() return 0 end, GetBombardCombat = function() return 0 end,
		GetMilitaryFormation = function() return 0 end, activity = activity }
end

local FAIL_CITY = false
local function makeCity(id, name, x)
	local d = CITY_DATA[name]
	local c = { GetID = function() return id end, GetName = function() return name end, GetX = function() return x end, GetY = function() return 5 end, GetOwner = function() return 0 end }
	if d then
		c.GetPopulation = function() if FAIL_CITY then error("boom") end return d.population end
		c.GetGrowth = function() return {
			GetFoodSurplus = function() return d.foodSurplus end, GetTurnsUntilGrowth = function() return d.growth.turnsUntilGrowth end,
			GetHousing = function() return d.growth.housing end, GetHousingGrowthModifier = function() return d.growth.housingMultiplier or 1 end,
			GetTurnsUntilStarvation = function() if d.foodSurplus < 0 then return -d.growth.turnsUntilGrowth end return -1 end,
			GetAmenities = function() return d.amenities.have end, GetAmenitiesNeeded = function() return d.amenities.needed end } end
		GameInfo = GameInfo or {}; GameInfo.Buildings = GameInfo.Buildings or {}
		GameInfo.Buildings[id] = { Name = d.production.name }
		c.GetBuildQueue = function() return { GetCurrentProductionTypeHash = function() return id end,
			GetTurnsLeft = function() return d.production.turns end } end
	end
	return c
end

local function setupHub(opts)
	opts = opts or {}
	Printed = {}
	MilitaryFormationTypes = { STANDARD_FORMATION = 0 }
	KeyNavErrorHandler = tostring
	local cities = { makeCity(1, "Rome", 3), makeCity(2, "Setia", 9) }
	local units = { makeUnit(1, "Builder", 0, "needs orders"), makeUnit(2, "Warrior", 10, "fortified"), makeUnit(3, "Builder", 0, "sleeping") }
	Game.GetLocalPlayer = function() return 0 end
	Game.IsVictoryEnabled = function(v) return v == "VICTORY_SCORE" end
	Game.GetMaxGameTurns = function() return 500 end
	Game.GetEras = function() return { GetNextEraCountdown = function() return 4 end } end
	local me = {
		GetCities = function() return { Members = function() local i = 0; return function() i = i + 1; if cities[i] == nil then return nil end; return i, cities[i] end end,
			FindID = function(_, id) return cities[id] end } end,
		GetUnits = function() return { Members = function() local i = 0; return function() i = i + 1; if units[i] == nil then return nil end; return i, units[i] end end } end,
		GetDiplomacy = function() return { HasMet = function(_, id) return id == 1 end, IsAtWarWith = function(_, id) return id == 1 end } end,
		GetScore = function() return 480 end,
	}
	local other = { GetScore = function() return 300 end, GetDiplomacy = function() return {} end }
	Players = { [0] = me, [1] = other }
	PlayerManager = { GetAliveMajorIDs = function() return { 0, 1 } end, GetAliveMinorIDs = function() return {} end }
	PlayerConfigurations = { [0] = { IsHuman = function() return true end }, [1] = { IsHuman = function() return false end } }
	PlotDescription_GetCivName = function(id) return id == 1 and "Egypt" or "Rome" end
	GameInfo = { Victories = function() return function() return nil end end, Buildings = GameInfo.Buildings, Districts = {}, Units = {}, Projects = {} }
	FAIL_CITY = opts.failCities == true
	CityManager = { GetDistrictAt = function() return nil end }
	CityReport_Gather = function(c) return CITY_DATA[c:GetName()] end
	CityReport_BuildItems = function(d) return { { key = "yields", text = "Yields of " .. d.name } } end
	HubEnemies = { ScanCityDanger = function() return opts.danger or {} end }
	HubMenus = { StandingValues = function(id) return { military = id == 0 and 120 or 340 } end }
	HubPlaces = {
		UnitActivity = function(u) return u.activity end,
		IdleActivity = function(u) return u.activity == "sleeping" and "sleeping" or nil end,
		Open = function(restore) HubPlaces.opened = restore end,
	}
	HubTargets = { CanOpenMode = function() return true end }
	HubCursor = { SetCursor = function(x, y) HubCursor.at = x .. "," .. y end }
	HubCityReport = { OpenReport = function(title, key, prefer) HubCityReport.called = prefer end }
	local mode
	HubCore = {
		IsLocalPlayerActive = function() return true end,
		IsModeOpen = function(name) return mode ~= nil and mode.name == name end,
		OpenMode = function(name, list, title, onClose) mode = { name = name, list = list, onClose = onClose }; list.Open(title) end,
		CloseMode = function() if mode then local m = mode; mode = nil; m.list.Reset(); if m.onClose then m.onClose() end end end,
	}
	return function() return mode end
end

local function key(k) return Input{ key = k, up = true } end

local function sections(items)
	local seen, order = {}, {}
	for _, item in ipairs(items) do if not seen[item.section] then seen[item.section] = true; table.insert(order, item.section) end end
	return table.concat(order, ",")
end

include("HubEmpire")

test("Gather: groups in order, counts, texts", function()
	setupHub()
	local data = HubEmpire.Gather()
	eq(sections(data.items), "Needs attention,Cities,Units,Victories,Standing")
	eq(data.cities, 2)
	eq(data.needOrders, 1)
	eq(data.attention, 2)
	eq(data.items[1].text, "Rome is starving, food minus 3, loses a citizen in 2 turns")
	eq(data.items[2].text, "Setia: Harbor takes 24 turns")
	eq(data.items[3].text, "Rome, population 8, starving, Harbor 5 turns, 1 problem")
	eq(data.items[4].text, "Setia, population 5, growing in 4 turns, Harbor 24 turns, 1 problem")
	local byKey = {}
	for _, item in ipairs(data.items) do byKey[item.key] = item end
	eq(byKey["u:idle:Builder"].text, "1 Builder idle")
	eq(byKey["u:orders"].text, "1 unit needs orders")
	eq(byKey["u:soldiers"].text, "1 soldier")
	eq(byKey["u:busy"].text, "Busy: 1 fortified")
	eq(byKey["v:score"].text, "Score: 480, first of 2; you lead; game ends turn 500")
	eq(byKey["v:score"].detail, "Ranking: 1. You, 480 points. 2. Egypt, 300 points")
	eq(byKey["s:war"].text, "At war with Egypt")
	eq(byKey["s:military"].text, "Strongest militaries: Egypt 340, at war; your military 120")
	eq(byKey["s:era"].text, "Next era in 5 turns")
end)

test("Gather: a danger entry adds the first problem; a failing group is left out and logged", function()
	setupHub{ danger = { { city = makeCity(2, "Setia", 9), count = 2, civs = { "Egypt" } } } }
	local data = HubEmpire.Gather()
	eq(data.items[1].text, "Setia in danger, 2 units of Egypt near")
	setupHub{ failCities = true }
	data = HubEmpire.Gather()
	eq(data.cities, 2)		-- a failed city keeps a minimal row, the count stays right
	eq(data.items[1].text, "Nothing urgent")
	eq(data.items[1].uncounted, true)
	eq(data.items[2].text, "Rome, details unavailable")
	setupHub()
	-- a broken group does not take the others down
	HubPlaces.UnitActivity = function() error("boom") end
	ClearPrinted()
	data = HubEmpire.Gather()
	eq(sections(data.items):find("Standing", 1, true) ~= nil, true)
	local logged = false
	for _, line in ipairs(Printed) do if line:find("HubEmpire unit error", 1, true) then logged = true end end
	eq(logged, true)
end)

test("Open speaks the opening line and the first item; Enter on a city opens its report; Space is the summary", function()
	local mode = setupHub()
	ClearPrinted()
	HubEmpire.Open()
	listeq(Spoken(), { "Empire, 2 need attention, 2 cities, 1 unit needs orders, 12 options",
		"Needs attention, 2: Rome is starving, food minus 3, loses a citizen in 2 turns, 1 of 12" })
	eq(mode().name, "empire")
	-- Page Down: the Cities group
	ClearPrinted()
	mode().list.HandleInput(Input{ key = Keys.VK_NEXT })
	eq(Spoken()[1] ~= nil, true)
	-- Space on the first problem: the city summary
	ClearPrinted()
	mode().list.HandleInput(key(Keys.VK_SPACE))
	eq(Spoken()[#Spoken()], "Rome. Yields of Rome")
	-- Enter on a problem opens the city report through the cursor
	mode().list.Reset()
	mode().list.Open("Empire")
	mode().list.HandleInput(key(Keys.VK_RETURN))
	eq(HubCursor.at, "3,5")
	eq(HubCityReport.called, true)
end)

test("Enter on a units line opens the places list at Your units; the empty line only repeats", function()
	local mode = setupHub()
	HubEmpire.Open()
	local list = mode().list
	-- focus the "orders" item
	for _ = 1, 10 do
		list.HandleInput(Input{ key = Keys.VK_DOWN })
		if list.GetFocusKey() == "u:orders" then break end
	end
	eq(list.GetFocusKey(), "u:orders")
	list.HandleInput(key(Keys.VK_RETURN))
	eq(HubPlaces.opened.catName, "Your units")
end)

test("Toggle closes an open list; Escape closes", function()
	local mode = setupHub()
	HubEmpire.Toggle()
	eq(mode() ~= nil, true)
	HubEmpire.Toggle()
	eq(mode(), nil)
	HubEmpire.Open()
	mode().list.HandleInput(key(Keys.VK_ESCAPE))
	eq(mode(), nil)
end)

test("ordinals: 21st, 22nd, 23rd, 11th", function()
	eq(EmpireText.Ordinal(3), "third")
	eq(EmpireText.Ordinal(11), "11th")
	eq(EmpireText.Ordinal(21), "21st")
	eq(EmpireText.Ordinal(22), "22nd")
	eq(EmpireText.Ordinal(23), "23rd")
	eq(EmpireText.Ordinal(12), "12th")
end)

test("reopening while open keeps the data", function()
	local mode = setupHub()
	HubEmpire.Open()
	HubEmpire.Open()
	eq(mode() ~= nil, true)
	ClearPrinted()
	mode().list.HandleInput(Input{ key = Keys.VK_DOWN })
	eq(#Spoken() > 0 and Spoken()[1] ~= "Nothing available", true)
end)

test("Space on a city reads the report lazily; a minimal row has no problems", function()
	local mode = setupHub()
	HubEmpire.Open()
	local list = mode().list
	for _ = 1, 5 do
		if list.GetFocusKey() == "c:1" then break end
		list.HandleInput(Input{ key = Keys.VK_DOWN })
	end
	ClearPrinted()
	list.HandleInput(key(Keys.VK_SPACE))
	eq(Spoken()[1], "Rome. Yields of Rome")
	eq(#EmpireText.CityProblems({ name = "X", minimal = true }), 0)
end)

test("zero food with the engine's -1 is not starving; housing at 25 percent is slowed, not stopped", function()
	local f = facts({ turnsUntilGrowth = -1, foodSurplus = 0 })
	eq(#EmpireText.CityProblems(f), 0)
	eq(EmpireText.GrowthState(f), "not growing")
	f = facts({ housing = 8, turnsUntilGrowth = 20, housingMultiplier = 0.25 })
	listeq(texts(EmpireText.CityProblems(f)), { "Rome: housing full, growth slowed 75 percent" })
end)
