-- HubPlaces.lua: the categories of the places list (J), their sorting, unit activity words, the send-a-unit chooser
stub("engine")
Keys.M = 77
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
	for _, c in ipairs(world.cities) do if c.x == x and c.y == y then return { GetName = function() return c.name end } end end
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
	eq(activity(true), "fortified")
	scout.fortify = 0
	eq(activity(true), "turn skipped")
	scout.activity = 4
	eq(activity(true), "on alert")
	scout.activity = 5
	eq(activity(true), "healing")
	scout.activity = 6
	eq(activity(true), "exploring")
	scout.activity = 1
	scout.dest = 5 * 30 + 5
	local moving = activity(false)
	assert(moving and moving:find("^moving to Rome, 2 turns"), tostring(moving))
	scout.dest = nil
end)

test("units category lists every unit with its activity and position", function()
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

test("send chooser: fastest first, unreachable units dropped, nothing reachable gives no items", function()
	units[#units + 1] = nil
	addUnit(2, "Warrior", 20, 5)
	addUnit(3, "Archer", 6, 5)
	local items = HubPlaces.BuildSendItems({ name = "Tribal Village", x = 8, y = 3 })
	eq(items[1].name, "Archer")
	eq(#items, 2)
	world.unreachable = { [3 * 30 + 8] = true }
	eq(#HubPlaces.BuildSendItems({ name = "Tribal Village", x = 8, y = 3 }), 0)
	world.unreachable = nil
end)
