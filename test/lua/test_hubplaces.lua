-- HubPlaces.lua: the categories of the places list (J), their sorting, unit activity words, the send-a-unit chooser
stub("engine")
Keys.M = 77
Keys.T = 84
InterfaceModeTypes = {}
local world = stub("world").new{ width = 30, height = 20 }
world:install()
include("ScreenReader")
include("KeyboardNavigation")
include("KeyNavList")
include("PlotDescription")
include("HubCore")
include("HubCursor")
include("HubTargets")
include("HubAnnounce")
HubRegions = { located = {} }
function HubRegions.GetLocatedNotifications() return HubRegions.located end

UI.GetHeadSelectedUnit = function() return nil end
UI.GetHeadSelectedCity = function() return nil end
UI.GetInterfaceMode = function() return -1 end
ActivityTypes = { ACTIVITY_AWAKE = 1, ACTIVITY_SLEEP = 2, ACTIVITY_HOLD = 3, ACTIVITY_SENTRY = 4, ACTIVITY_HEAL = 5,
	ACTIVITY_OPERATION = 6, ACTIVITY_INTERCEPT = 7 }
GameInfo.Units = setmetatable({}, { __index = function(_, i) return { UnitType = "UNIT_X", Name = "x" } end })
GameInfo.Improvements = { [1] = { ImprovementType = "IMPROVEMENT_GOODY_HUT", Name = "Tribal Village" },
	[2] = { ImprovementType = "IMPROVEMENT_FARM", Name = "Farm" }, [3] = { ImprovementType = "IMPROVEMENT_BARBARIAN_CAMP", Name = "Barbarian Camp" } }
GameInfo.Features = { [4] = { Name = "Mount Kailash", NaturalWonder = true } }
Cities = { GetCityInPlot = function(x, y)
	for _, c in ipairs(world.cities) do if c.x == x and c.y == y then return { GetName = function() return c.name end, GetOwner = function() return c.owner end, GetID = function() return c.id end } end end
end }

-- units: their state lives in tables so a test can change it
local units = {}
local function addUnit(id, name, x, y, props)
	local u = { id = id, name = name, x = x, y = y, activity = 1, fortify = 0, moves = 2, max = 2, dest = nil, owner = 0 }
	for k, v in pairs(props or {}) do u[k] = v end
	units[#units + 1] = u
	return u
end
local function unitObject(u)
	return {
		GetID = function() return u.id end, GetX = function() return u.x end, GetY = function() return u.y end,
		GetOwner = function() return u.owner end, GetName = function() return u.name end,
		GetFortifyTurns = function() return u.fortify end, GetMovesRemaining = function() return u.moves end,
		GetMaxMoves = function() return u.max end, GetUnitType = function() return 0 end,
	}
end
local basePlayer = Players[0]
local player = setmetatable({
	GetUnits = function() return {
		Members = function() local l = {}; for _, u in ipairs(units) do l[#l + 1] = unitObject(u) end; return ipairs(l) end,
		FindID = function(_, id) for _, u in ipairs(units) do if u.id == id then return unitObject(u) end end end,
	} end,
}, { __index = basePlayer })
rawset(Players, 0, player)
local byId = {}
UnitManager.GetActivityType = function(unit) for _, u in ipairs(units) do if u.id == unit:GetID() then return u.activity end end end
UnitManager.GetQueuedDestination = function(unit) for _, u in ipairs(units) do if u.id == unit:GetID() then return u.dest end end end
UnitManager.GetMoveToPathEx = function(unit, index)
	if world.unreachable and world.unreachable[index] then return nil end
	local u; for _, v in ipairs(units) do if v.id == unit:GetID() then u = v end end
	local d = Map.GetPlotDistance(u.x, u.y, index % 30, math.floor(index / 30))
	return { plots = { 0, index }, turns = { math.max(1, math.ceil(d / 2)) } }
end

world:city(0, 5, 5, "Rome")
world:city(0, 12, 5, "Ostia")
world:city(2, 25, 15, "Babylon")
world.cities[3].id = 1
world:set(8, 3, { improvement = 1 })
world.plots[3 * 30 + 8].object = nil
-- improvements and features through the plot objects: wrap the stub's GetImprovementType / GetFeatureType
local realGetPlot = Map.GetPlot
Map.GetPlot = function(x, y)
	local plot = realGetPlot(x, y)
	if plot == nil then return nil end
	local p = world.plots[y * 30 + x]
	plot.GetImprovementType = function() return p.improvement or -1 end
	plot.GetFeatureType = function() return p.feature or -1 end
	return plot
end
Map.GetPlotCount = nil

HubCursor.GetCursor = function() return 5, 5 end
dofile = nil
include("HubPlaces")

local function names(items) local l = {}; for _, i in ipairs(items) do l[#l + 1] = i.text end; return l end

test("cities are sorted by distance from the reference and say direction and distance", function()
	local cats = HubPlaces.BuildCategories({ plot = Map.GetPlot(5, 5) })
	eq(cats[1].name, "Your cities")
	eq(cats[1].items[1].text, "Rome, here")
	eq(cats[1].items[2].text:match("^Ostia, 7 tiles"), "Ostia, 7 tiles")
end)

test("a city far from the reference comes later", function()
	local cats = HubPlaces.BuildCategories({ plot = Map.GetPlot(12, 6) })
	eq(cats[1].items[1].name, "Ostia")
end)

test("points of interest: tribal village and natural wonder, farm ignored, wonder listed once", function()
	world:set(9, 3, { improvement = 2 })
	world:set(20, 10, { feature = 4 })
	world:set(21, 10, { feature = 4 })
	world:set(2, 12, { improvement = 3 })
	world:set(7, 14, { hidden = true, improvement = 1 })
	local cats = HubPlaces.BuildCategories({ plot = Map.GetPlot(5, 5) })
	local points
	for _, c in ipairs(cats) do if c.name == "Points of interest" then points = c end end
	assert(points, "no points category")
	eq(#points.items, 3)
	eq(points.items[1].name, "Tribal Village")
	local text = table.concat(names(points.items), "|")
	assert(text:find("Barbarian Camp"), text)
	assert(text:find("Mount Kailash"), text)
	assert(not text:find("Farm"), text)
end)

test("unit activity words", function()
	local scout = addUnit(1, "Scout", 8, 3)
	local function activity(forList) return HubPlaces.UnitActivity(unitObject(scout), forList) end
	eq(activity(false), nil)
	eq(activity(true), "needs orders")
	scout.moves = 0
	eq(activity(true), "no moves left")
	scout.moves = 2
	scout.activity = 2
	eq(activity(true), "sleeping")
	scout.activity = 3; scout.fortify = 2
	eq(activity(true), "turn skipped")
	scout.activity = 4
	eq(activity(true), "fortified")
	scout.fortify = 0
	eq(activity(true), "on alert")
	scout.activity = 5
	eq(activity(true), "healing")
	scout.activity = 6
	eq(activity(true), "busy")
	GameInfo.UnitOperations = { [9] = { OperationType = "UNITOPERATION_AUTOMATE_EXPLORE" } }
	HubPlaces.OnOperationAdded(0, 1, 0, 9)
	eq(activity(true), "exploring")
	Clock.now = Clock.now + 5
	HubCore.m_lastKeyTime = Clock.now
	HubPlaces.OnOrderStarted(0, 1)
	eq(activity(true), "busy")
	scout.activity = 1
	scout.dest = 5 * 30 + 5
	local moving = activity(false)
	assert(moving and moving:find("^moving to Rome, 2 turns"), tostring(moving))
	scout.dest = nil
end)

test("units category lists every unit with its activity and position", function()
	HubPlaces.OnOperationAdded(0, 1, 0, 9)
	units[1].activity = 6
	local cats = HubPlaces.BuildCategories({ plot = Map.GetPlot(5, 5) })
	local list
	for _, c in ipairs(cats) do if c.name == "Your units" then list = c end end
	assert(list, "no units category")
	local text = list.items[1].text
	assert(text:find("^Scout, exploring, "), text)
	assert(text:find("of Rome") or text:find("Rome"), text)
	units[1].activity = 1
end)

test("cancel hint is given once, for a fresh pick", function()
	local u = unitObject(units[1])
	HubPlaces.m_hintUnit, HubPlaces.m_hintTime = 1, Clock.now
	eq(HubPlaces.TakeCancelHint(u), true)
	eq(HubPlaces.TakeCancelHint(u), false)
	HubPlaces.m_hintUnit, HubPlaces.m_hintTime = 1, Clock.now - 10
	eq(HubPlaces.TakeCancelHint(u), false)
end)

test("notifications and foreign cities get their categories", function()
	HubRegions.located = { { id = 7, text = "Barbarian camp discovered", x = 2, y = 12 } }
	local cats = HubPlaces.BuildCategories({ plot = Map.GetPlot(5, 5) })
	local got = {}
	for _, c in ipairs(cats) do got[c.name] = c end
	assert(got["Notifications"], "notifications")
	assert(got["Notifications"].items[1].text:find("^Barbarian camp discovered, "), got["Notifications"].items[1].text)
	assert(got["Foreign cities"], "foreign")
	assert(got["Foreign cities"].items[1].text:find("^Babylon"), got["Foreign cities"].items[1].text)
end)

test("fogged plots keep the memory and say last seen; the live state of fog does not leak", function()
	world:set(2, 12, { fogged = true })
	local ctx = { plot = Map.GetPlot(5, 5) }
	local function camp(cats) for _, c in ipairs(cats) do if c.name == "Points of interest" then for _, i in ipairs(c.items) do if i.name == "Barbarian Camp" then return i end end end end end
	local item = camp(HubPlaces.BuildCategories(ctx))
	assert(item and item.text:find("last seen"), item and item.text)
	world:set(14, 12, { fogged = true, improvement = 3 })		-- spawned in the fog: never seen
	local seen = false
	for _, c in ipairs(HubPlaces.BuildCategories(ctx)) do
		for _, i in ipairs(c.items) do if i.x == 14 and i.y == 12 then seen = true end end
	end
	eq(seen, false)
	world:set(2, 12, { fogged = false, improvement = -1 })		-- in view again and gone
	eq(camp(HubPlaces.BuildCategories(ctx)), nil)
end)

test("send chooser: fastest first, unreachable units dropped, nothing reachable gives no items", function()
	units[#units + 1] = nil
	addUnit(2, "Warrior", 20, 5)
	addUnit(3, "Archer", 6, 5)
	local items = HubPlaces.BuildSendItems({ name = "Tribal Village", x = 8, y = 3 })
	eq(items[1].name, "Archer")
	eq(#items, 2)
	-- the place and everything within 2 tiles of it unreachable: nobody can get there
	world.unreachable = {}
	for dy = -2, 2 do for dx = -2, 2 do world.unreachable[(3 + dy) * 30 + 8 + dx] = true end end
	eq(#HubPlaces.BuildSendItems({ name = "Tribal Village", x = 8, y = 3 }), 0)
	world.unreachable = nil
end)

test("send chooser: an unreachable place is approached from a neighbour (next to Rome)", function()
	world.unreachable = { [5 * 30 + 5] = true }		-- Rome itself (occupied / foreign city)
	local items = HubPlaces.BuildSendItems({ name = "Rome", x = 5, y = 5 })
	assert(#items >= 2, #items)
	for _, item in ipairs(items) do
		assert(item.text:find(", next to Rome"), item.text)
		assert(item.nearX ~= nil and Map.GetPlotDistance(item.nearX, item.nearY, 5, 5) == 1)
	end
	for _, item in ipairs(items) do assert(not item.text:find("^Archer"), "Archer already stands next to Rome") end
	assert(items[1].text:find("^Scout, %d+ turns?, next to Rome"), items[1].text)
	-- ring 1 blocked too: the fallback goes to 2 tiles ("near")
	for dy = -1, 1 do for dx = -1, 1 do world.unreachable[(5 + dy) * 30 + 5 + dx] = true end end
	items = HubPlaces.BuildSendItems({ name = "Rome", x = 5, y = 5 })
	assert(#items >= 1 and items[1].text:find(", near Rome"), items[1] and items[1].text)
	world.unreachable = nil
end)

test("send chooser: path finding calls are capped", function()
	local calls = 0
	local real = UnitManager.GetMoveToPathEx
	UnitManager.GetMoveToPathEx = function() calls = calls + 1; return nil end
	for i = 10, 60 do addUnit(i, "Extra", 10 + i % 10, 8) end
	HubPlaces.BuildSendItems({ name = "Rome", x = 5, y = 5 })
	UnitManager.GetMoveToPathEx = real
	assert(calls <= 120, calls)
	for i = #units, 1, -1 do if units[i].id >= 10 then table.remove(units, i) end end
end)

test("order hint: explore has no cancel; wake / cancel only when the game allows them", function()
	local u = unitObject(units[1])
	units[1].activity = 1
	Clock.now = Clock.now + 5
	HubCore.m_lastKeyTime = Clock.now
	HubPlaces.OnOrderStarted(0, 1)		-- drop an explore flag left by an earlier test
	eq(HubPlaces.OrderHint(u), nil)
	HubPlaces.OnOperationAdded(0, 1, 0, 9)
	eq(HubPlaces.OrderHint(u), "Any order stops exploring, Tab for actions")
	Clock.now = Clock.now + 5
	HubCore.m_lastKeyTime = Clock.now
	HubPlaces.OnOrderStarted(0, 1)
	UnitCommandTypes = { WAKE = 1, CANCEL = 2 }
	local allowed = { [1] = true }
	UnitManager.CanStartCommand = function(_, command) return allowed[command] == true end
	units[1].activity = 2
	eq(HubPlaces.OrderHint(u), "Shift+W wakes it")
	allowed = {}
	eq(HubPlaces.OrderHint(u), "Any order replaces it, Tab for actions")
	units[1].activity = 1
	units[1].dest = 5 * 30 + 5
	eq(HubPlaces.OrderHint(u), "Any order replaces it, Tab for actions")
	allowed = { [2] = true }
	eq(HubPlaces.OrderHint(u), "Shift+C cancels the move")
	units[1].dest = nil
	UnitCommandTypes = nil
end)

-- Barbarian Clans mode: the clan leads the camp's line, T is offered while the camp is in view
local function campItem(ctx)
	for _, c in ipairs(HubPlaces.BuildCategories(ctx)) do
		if c.name == "Points of interest" then
			for _, i in ipairs(c.items) do if i.name == "Barbarian Camp" then return i end end
		end
	end
end

test("without the mode a camp line has no clan words", function()
	world:set(2, 12, { fogged = false, improvement = 3 })
	local item = campItem({ plot = Map.GetPlot(5, 5) })
	assert(item and not item.text:find("clan") and not item.text:find("treat"), item and item.text)
	eq(item.clan, nil)
end)

local clanModeOn = true
GameConfiguration = { GetValue = function(key) return key == "GAMEMODE_BARBARIAN_CLANS" and clanModeOn or nil end }
PlotDescription_ResetClanMode()

test("mode off: tribe data in the base game gives no clan words, no hint and a dead T line", function()
	GameInfo.BarbarianTribeNames = { [7] = { TribeDisplayName = "Badger Claw" } }
	GameInfo.BarbarianTribes = { [2] = { Name = "Melee Open" } }
	local manager = {
		GetTribeIndexAtLocation = function(_, x, y) if x == 2 and y == 12 then return 0 end return -1 end,
		GetTribeNameType = function() return 7 end, GetTribeType = function() return 2 end,
	}
	Game.GetBarbarianManager = function() return manager end
	clanModeOn = false
	PlotDescription_ResetClanMode()
	local item = campItem({ plot = Map.GetPlot(5, 5) })
	assert(not item.text:find("clan") and not item.text:find("treat"), item.text)
	eq(item.clan, nil)
	clanModeOn = true
	PlotDescription_ResetClanMode()
	Game.GetBarbarianManager = nil
end)

test("a clan camp says its clan and type first and offers T while in view", function()
	GameInfo.BarbarianTribeNames = { [7] = { TribeDisplayName = "Badger Claw" } }
	GameInfo.BarbarianTribes = { [2] = { Name = "Melee Open" } }
	local manager = {
		GetTribeIndexAtLocation = function(_, x, y) if x == 2 and y == 12 then return 0 end return -1 end,
		GetTribeNameType = function() return 7 end, GetTribeType = function() return 2 end,
	}
	Game.GetBarbarianManager = function() return manager end
	local item = campItem({ plot = Map.GetPlot(5, 5) })
	assert(item.text:find("^Badger Claw clan, Melee Open, Barbarian Camp, "), item.text)
	assert(item.text:find(", T to treat with the clan$"), item.text)
	eq(item.clan, true)
	world:set(2, 12, { fogged = true })
	item = campItem({ plot = Map.GetPlot(5, 5) })
	assert(item.text:find("^Badger Claw clan, Melee Open, Barbarian Camp, .*last seen"), item.text)
	assert(not item.text:find("T to treat"), item.text)
	world:set(2, 12, { fogged = false })
	Game.GetBarbarianManager = nil
end)

-- ===========================================================================
-- Remembering points as they are seen, civilians to capture, T on a clan camp (tech tree key)
-- ===========================================================================
local function pointNames(ctx)
	local out = {}
	for _, c in ipairs(HubPlaces.BuildCategories(ctx)) do
		if c.name == "Points of interest" then for _, i in ipairs(c.items) do out[#out + 1] = i.x .. "," .. i.y end end
	end
	return table.concat(out, "|")
end

test("a village seen by the ImprovementVisibilityChanged event is remembered after it falls back into the fog", function()
	local ctx = { plot = Map.GetPlot(5, 5) }
	world:set(18, 8, { fogged = false, improvement = -1 })
	HubPlaces.OnImprovementVisibilityChanged(18, 8, 1, 1)		-- reported visible with a village (the live plot says nothing yet)
	world:set(18, 8, { fogged = true, improvement = 1 })
	assert(pointNames(ctx):find("18,8", 1, true), pointNames(ctx))
	-- fogged again and gone in the fog: the memory stays (last seen)
	world:set(18, 8, { improvement = -1 })
	assert(pointNames(ctx):find("18,8", 1, true), pointNames(ctx))
	-- seen again, gone
	world:set(18, 8, { fogged = false })
	HubPlaces.OnImprovementVisibilityChanged(18, 8, -1, 1)
	assert(not pointNames(ctx):find("18,8", 1, true), pointNames(ctx))
end)

test("an event for a plot that is in the fog is not remembered (only visible plots count)", function()
	local ctx = { plot = Map.GetPlot(5, 5) }
	world:set(19, 8, { fogged = true, improvement = 1 })
	HubPlaces.OnImprovementVisibilityChanged(19, 8, 1, 1)
	HubPlaces.OnImprovementAddedToMap(19, 8, 1, 0)
	assert(not pointNames(ctx):find("19,8", 1, true), pointNames(ctx))
end)

test("a unit that moves remembers the village next to it", function()
	local ctx = { plot = Map.GetPlot(5, 5) }
	world:set(23, 8, { fogged = false, improvement = 1 })
	HubPlaces.OnUnitMoveComplete(0, 1, 22, 8)
	HubPlaces.OnUnitMoveComplete(0, 1, 22, 8)		-- coalesced: one delayed scan
	eq(#HubCore.m_delayed, 1)
	HubPlaces.ScanMoved()
	HubCore.m_delayed = {}
	world:set(23, 8, { fogged = true })
	assert(pointNames(ctx):find("23,8", 1, true), pointNames(ctx))
	HubPlaces.OnUnitMoveComplete(1, 1, 22, 8)		-- another player's unit: ignored
end)

test("Prime runs once: villages that appear in the fog later are not accepted", function()
	local ctx = { plot = Map.GetPlot(5, 5) }
	world:set(26, 2, { fogged = true, improvement = 1 })
	world:set(27, 2, { fogged = true, improvement = 3 })
	HubPlaces.Prime()
	assert(not pointNames(ctx):find("26,2", 1, true))
	assert(not pointNames(ctx):find("27,2", 1, true))
end)

-- civilians
GameInfo.UnitCaptures = setmetatable({}, { __call = function()
	local rows = { { CapturedUnitType = "UNIT_BUILDER" }, { CapturedUnitType = "UNIT_SETTLER" } }
	local i = 0
	return function() i = i + 1; return rows[i] end
end })
local unitRows = {
	[10] = { UnitType = "UNIT_BUILDER", Name = "Builder", Domain = "DOMAIN_LAND", CanCapture = false },
	[11] = { UnitType = "UNIT_WARRIOR", Name = "Warrior", Domain = "DOMAIN_LAND" },
	[12] = { UnitType = "UNIT_TRADER", Name = "Trader", Domain = "DOMAIN_LAND", CanCapture = false },
	[13] = { UnitType = "UNIT_GALLEY", Name = "Galley", Domain = "DOMAIN_SEA" },
}
local realUnits = GameInfo.Units
GameInfo.Units = setmetatable({}, { __index = function(_, i) return unitRows[i] or { UnitType = "UNIT_X", Name = "x" } end })

local function captureCat(ctx)
	for _, c in ipairs(HubPlaces.BuildCategories(ctx)) do if c.name == "Civilians to capture" then return c end end
end
PlotDescription_FormationName = function(_, text) return text end
local worldUnits = {}
local function addWorldUnit(u) world.units[#world.units + 1] = u; worldUnits[#worldUnits + 1] = u; return u end
local function clearWorldUnits()
	for _, u in ipairs(worldUnits) do for i = #world.units, 1, -1 do if world.units[i] == u then table.remove(world.units, i) end end end
	worldUnits = {}
end
world.units = world.units or {}
local plotUnits = {}
Units.GetUnitsInPlot = function(plot)
	local list = {}
	for _, u in ipairs(plotUnits) do if u.x == plot:GetX() and u.y == plot:GetY() then list[#list + 1] = world.fakeUnit(u) end end
	return list
end

test("no visible enemy civilian: no capture category", function()
	eq(captureCat({ plot = Map.GetPlot(5, 5) }), nil)
end)

test("barbarian builder is listed with its place; trader and warrior are not", function()
	local b = addWorldUnit({ id = 50, owner = 63, x = 9, y = 7, unitType = 10, name = "Builder" })
	addWorldUnit({ id = 51, owner = 63, x = 10, y = 7, unitType = 12, name = "Trader" })
	addWorldUnit({ id = 52, owner = 63, x = 11, y = 7, unitType = 11, combat = 20, name = "Warrior" })
	plotUnits = { b }
	local cat = captureCat({ plot = Map.GetPlot(5, 5) })
	assert(cat, "no category")
	eq(#cat.items, 1)
	assert(cat.items[1].text:find("^Barbarian Builder, "), cat.items[1].text)
	assert(not cat.items[1].text:find("escorted"), cat.items[1].text)
	eq(cat.items[1].kind, "capture")
end)

test("a military unit on the plot is the escort", function()
	local w = addWorldUnit({ id = 53, owner = 63, x = 9, y = 7, unitType = 11, combat = 20, name = "Warrior" })
	plotUnits = { worldUnits[1], w }
	local cat = captureCat({ plot = Map.GetPlot(5, 5) })
	assert(cat.items[1].text:find(", escorted by Warrior$"), cat.items[1].text)
	eq(cat.items[1].escorted, true)
end)

test("a civ at war is listed, a civ at peace is not", function()
	addWorldUnit({ id = 60, owner = 2, x = 14, y = 9, unitType = 10, name = "Builder" })
	local cat = captureCat({ plot = Map.GetPlot(5, 5) })
	eq(#cat.items, 1)
	world.at_war = { [2] = true }
	cat = captureCat({ plot = Map.GetPlot(5, 5) })
	eq(#cat.items, 2)
	assert(cat.items[2].text:find("Builder, "), cat.items[2].text)
	world.at_war = {}
end)

test("the send chooser for a civilian offers only military land units", function()
	addUnit(70, "Builder", 7, 7)
	addUnit(71, "Warrior", 6, 7)
	local types = { [70] = 10, [71] = 11 }
	local function withType(u)
		local o = unitObject(u)
		o.GetUnitType = function() return types[u.id] or 0 end
		o.GetCombat = function() return u.id == 71 and 20 or 0 end
		return o
	end
	local oldGetUnits = player.GetUnits
	player.GetUnits = function() return {
		Members = function() local l = {}; for _, u in ipairs(units) do l[#l + 1] = withType(u) end; return ipairs(l) end,
		FindID = function(_, id) for _, u in ipairs(units) do if u.id == id then return withType(u) end end end,
	} end
	local items = HubPlaces.BuildSendItems({ name = "Barbarian Builder", x = 9, y = 7, capture = true })
	local names = {}
	for _, i in ipairs(items) do names[#names + 1] = i.name end
	eq(table.concat(names, ","), "Warrior")
	player.GetUnits = oldGetUnits
	for i = #units, 1, -1 do if units[i].id >= 70 then table.remove(units, i) end end
end)

test("tech tree key: on a clan camp it treats (in view) or says out of sight; elsewhere it leaves the tech tree alone", function()
	plotUnits = {}
	clearWorldUnits()
	GameInfo.Units = realUnits
	GameInfo.BarbarianTribeNames = { [7] = { TribeDisplayName = "Badger Claw" } }
	GameInfo.BarbarianTribes = { [2] = { Name = "Melee Open" } }
	local manager = {
		GetTribeIndexAtLocation = function(_, x, y) if x == 2 and y == 12 then return 0 end return -1 end,
		GetTribeNameType = function() return 7 end, GetTribeType = function() return 2 end,
	}
	Game.GetBarbarianManager = function() return manager end
	PlotDescription_ResetClanMode()
	HubTargets.GetTargetMode = function() return nil end
	HubCore.IsGamePopupOpen = function() return false end
	HubCore.m_mode = nil
	local opened = {}
	LuaEvents = LuaEvents or {}
	LuaEvents.CityBannerManager_OpenTreatWithTribePopup = function(index) opened[#opened + 1] = index end
	local cx, cy = 5, 5
	HubCursor.GetCursor = function() return cx, cy end
	local pushed = {}
	LuaEvents.SRA_ClanCampUnderCursor = function(on) pushed[#pushed + 1] = on end
	HubPlaces.PushCampState(true)
	eq(pushed[#pushed], false)
	HubPlaces.PushCampState(false)
	eq(#pushed, 1)		-- unchanged: nothing sent
	cx, cy = 2, 12
	world:set(2, 12, { fogged = false, improvement = 3 })
	HubPlaces.PushCampState(false)
	eq(pushed[#pushed], true)
	HubPlaces.OnTechTreeKeyOnCamp()
	eq(opened[1], 12 * 30 + 2)
	world:set(2, 12, { fogged = true })
	HubPlaces.OnTechTreeKeyOnCamp()
	eq(#opened, 1)
	local spoken = Spoken()
	assert(spoken[#spoken]:find("out of sight", 1, true), spoken[#spoken])
	-- a screen is open: false is pushed, the tech tree toggles as before
	world:set(2, 12, { fogged = false })
	HubCore.IsGamePopupOpen = function() return true end
	HubPlaces.PushCampState(false)
	eq(pushed[#pushed], false)
	-- reset on shutdown
	HubCore.IsGamePopupOpen = function() return false end
	HubPlaces.PushCampState(false)
	eq(pushed[#pushed], true)
	HubPlaces.ResetCampState()
	eq(pushed[#pushed], false)
	HubCursor.GetCursor = function() return 5, 5 end
	Game.GetBarbarianManager = nil
end)

-- ===========================================================================
-- Camps: guards, advice, attack party, destroyed; blind spots category
-- ===========================================================================
local function campPoint(ctx)
	for _, c in ipairs(HubPlaces.BuildCategories(ctx)) do
		if c.name == "Points of interest" then
			for _, i in ipairs(c.items) do if i.name == "Barbarian Camp" then return i end end
		end
	end
end
local function barbarian(id, x, y, name)
	local u = { id = id, owner = 63, x = x, y = y, unitType = 11, combat = 20, name = name }
	world.units[#world.units + 1] = u
	return u
end

test("a camp in view says who guards it, in the fog it says how long ago", function()
	GameInfo.Units = setmetatable({}, { __index = function(_, i) return unitRows[i] or { UnitType = "UNIT_X", Name = "x" } end })
	world:set(2, 12, { fogged = false, improvement = 3 })
	local guard = barbarian(300, 2, 12, "Spearman")
	plotUnits = { guard }
	HubPlaces.RefreshSeen()
	local item = campPoint({ plot = Map.GetPlot(5, 5) })
	assert(item.text:find("^Barbarian Camp, .*, guarded by Spearman$"), item.text)
	eq(item.camp, true)
	PlotDescription_GetShort = function() return "Barbarian Camp" end		-- the stub plot cannot describe units
	local advice = item.detail()
	assert(advice:find("Destroying it gives", 1, true) and advice:find("stops raids from it", 1, true), advice)
	assert(advice:find("experience", 1, true), advice)
	-- fogged: the memory speaks, not the live plot (the guard left in the meantime)
	world:set(2, 12, { fogged = true })
	plotUnits = {}
	item = campPoint({ plot = Map.GetPlot(5, 5) })
	assert(item.text:find("guarded by Spearman %(last seen this turn%)$"), item.text)
	-- an empty camp in view
	world:set(2, 12, { fogged = false })
	HubPlaces.RefreshSeen()
	item = campPoint({ plot = Map.GetPlot(5, 5) })
	assert(item.text:find(", not guarded right now$"), item.text)
end)

test("the camp's gold is only stated when the game's data has it", function()
	GameInfo.Improvements.IMPROVEMENT_BARBARIAN_CAMP = GameInfo.Improvements[3]
	GameInfo.Improvements[3].DispersalGold = 50
	local item = campPoint({ plot = Map.GetPlot(5, 5) })
	assert(item.detail():find("gives about 50 gold and stops raids", 1, true), item.detail())
	GameInfo.Improvements[3].DispersalGold = nil
	assert(campPoint({ plot = Map.GetPlot(5, 5) }).detail():find("gives gold and stops raids", 1, true))
end)

test("M on a camp offers an attack party of the two fastest military land units first", function()
	for i = #units, 1, -1 do if units[i].id >= 70 then table.remove(units, i) end end
	local types = { [201] = 11, [202] = 11, [203] = 10 }
	addUnit(201, "Warrior", 3, 12)
	addUnit(202, "Slinger", 8, 12)
	addUnit(203, "Builder", 2, 11)
	local function withType(u)
		local o = unitObject(u)
		o.GetUnitType = function() return types[u.id] or 0 end
		o.GetCombat = function() return (u.id == 201) and 20 or 0 end
		o.GetRangedCombat = function() return (u.id == 202) and 15 or 0 end
		return o
	end
	local oldGetUnits = player.GetUnits
	player.GetUnits = function() return {
		Members = function() local l = {}; for _, u in ipairs(units) do l[#l + 1] = withType(u) end; return ipairs(l) end,
		FindID = function(_, id) for _, u in ipairs(units) do if u.id == id then return withType(u) end end end,
	} end
	local items = HubPlaces.BuildSendItems({ name = "Barbarian Camp", x = 2, y = 12, camp = true })
	eq(items[1].key, "party")
	assert(items[1].text:find("^Attack party, send 2 units: Warrior %d+ turns?, Slinger %d+ turns?$"), items[1].text)
	eq(#items[1].members, 2)
	-- without the camp flag there is no party
	assert(HubPlaces.BuildSendItems({ name = "Barbarian Camp", x = 2, y = 12 })[1].key ~= "party")
	-- one soldier only: no party
	table.remove(units, #units - 1)
	items = HubPlaces.BuildSendItems({ name = "Barbarian Camp", x = 2, y = 12, camp = true })
	assert(items[1].key ~= "party", items[1].key)
	player.GetUnits = oldGetUnits
	for i = #units, 1, -1 do if units[i].id >= 200 then table.remove(units, i) end end
end)

test("a camp destroyed in view is announced with the gold gained", function()
	HubCore.m_ready = true
	local gold = 100
	player.GetTreasury = function() return { GetGoldBalance = function() return gold end } end
	world:set(2, 12, { fogged = false, improvement = 3 })
	plotUnits = {}
	HubPlaces.RefreshSeen()
	HubPlaces.Update(1)		-- samples the treasury
	HubCore.m_delayed = {}
	world:set(2, 12, { improvement = -1 })
	gold = 150
	HubPlaces.OnImprovementRemovedFromMap(2, 12)
	for _, d in ipairs(HubCore.m_delayed) do d.fn() end
	HubCore.m_delayed = {}
	local spoken = Spoken()
	eq(spoken[#spoken], "Barbarian camp destroyed, 50 gold")
	player.GetTreasury = nil
end)

test("a village removed (not a camp) says nothing about a camp", function()
	HubCore.m_ready = true
	world:set(18, 8, { fogged = false, improvement = 1 })
	HubPlaces.RefreshSeen()
	local before = #Spoken()
	HubPlaces.OnImprovementRemovedFromMap(18, 8)
	for _, d in ipairs(HubCore.m_delayed) do d.fn() end
	HubCore.m_delayed = {}
	eq(#Spoken(), before)
end)

test("blind spots: a category after the points of interest, with the game's distances in Space", function()
	-- a block of revealed land out of sight, 5 to 6 tiles north of Rome; everything else in view
	for y = 0, 1 do for x = 4, 8 do world:set(x, y, { fogged = true }) end end
	GameInfo.GlobalParameters = { BARBARIAN_CAMP_MINIMUM_DISTANCE_CITY = { Value = "4" }, BARBARIAN_CAMP_MINIMUM_DISTANCE_ANOTHER_CAMP = { Value = "7" } }
	local cats = HubPlaces.BuildCategories({ plot = Map.GetPlot(5, 5) })
	local names, spot = {}, nil
	for _, c in ipairs(cats) do names[#names + 1] = c.name; if c.name == "Blind spots" then spot = c end end
	assert(spot, table.concat(names, ","))
	local poi, blind = 0, 0
	for i, n in ipairs(names) do if n == "Points of interest" then poi = i end; if n == "Blind spots" then blind = i end end
	eq(blind, poi + 1)
	assert(spot.items[1].text:find("^Blind spot: %d+ tiles out of sight, %d+ tiles? .* of %a+$"), spot.items[1].text)
	eq(spot.items[1].kind, "blind")
	local detail = spot.items[1].detail()
	assert(detail:find("at least 4 tiles from any city and 7 from another camp", 1, true), detail)
end)
