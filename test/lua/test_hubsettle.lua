-- HubSettle.lua: wording of the danger hint / guard and the arrival-build sentence (pure parts), the Enter arming
stub("engine")
Keys.VK_SHIFT, Keys.VK_CONTROL, Keys.VK_ALT = 16, 17, 18
local world = stub("world").new{ width = 30, height = 20 }
world:install()
include("ScreenReader")
include("PlotDescription")
include("HubCore")
include("HubEnemies")

-- HubSettle needs the list machinery and BuildScan at load time: permissive stand-ins for those only
KeyNavList_Create = function() return {} end
local realInclude = include
include = function(name)
	if name == "BuildScan" then return end
	return realInclude(name)
end
BuildScan_Improvements = function() return nil end
HubMenus = {}
HubCursor = {}
HubTargets = {}
local path = ROOT .. "/ScreenReaderAccess/Assets/UI/Accessibility/HubSettle.lua"
local chunk, err = loadstring(sr_read(path), "@" .. path)
assert(chunk, err)
chunk()

test("danger hint on a tile item", function()
	eq(HubSettle.DangerItemText("Barbarian Man-At-Arms", 1), "danger: Barbarian Man-At-Arms 1 tile away")
	eq(HubSettle.DangerItemText("Barbarian Archer", 2), "danger: Barbarian Archer 2 tiles away")
	eq(HubSettle.DangerItemText("Barbarian Archer", 0), "danger: Barbarian Archer on the tile")
end)

test("danger guard sentence", function()
	eq(HubSettle.DangerGuardText("Barbarian Man-At-Arms", 1, "Wheat"), "Danger: Barbarian Man-At-Arms 1 tile from Wheat. Enter again sends it anyway")
end)

test("first Enter on a dangerous tile warns, second within 10 s goes through, an other key in between resets", function()
	local g = { turn = -1, warnSig = nil, warnTime = 0, confirmSig = nil }
	eq(HubEnemies.GuardDecision(g, 70, "5:10:63:1", 100), "warn")
	eq(HubEnemies.GuardDecision(g, 70, "5:10:63:1", 104), "confirm")
	local h = { turn = -1, warnSig = nil, warnTime = 0, confirmSig = nil }
	HubEnemies.GuardDecision(h, 70, "5:10:63:1", 100)
	h.warnSig = nil		-- what HubSettle.OnOtherKey does
	eq(HubEnemies.GuardDecision(h, 70, "5:10:63:1", 101), "warn")
end)

test("key names are SRKey tokens", function()
	eq(HubSettle.ArrivalBuildText("Farm", true, true), "[KEY:Enter] builds Farm")
	eq(HubSettle.ArrivalStaleText("Farm", ""), "Farm is no longer possible here. [KEY:X|X] lists other tiles")
end)

test("arrival sentence", function()
	eq(HubSettle.ArrivalBuildText("Farm", true, true), "Enter builds Farm")
	eq(HubSettle.ArrivalBuildText("Farm", false, true), "Farm can be built next turn: select it and press Enter")
	eq(HubSettle.ArrivalBuildText("Farm", true, false), "Select it and press Enter to build Farm")
end)

test("armed Enter: needs the builder selected, on the tile, with moves; other keys disarm an immediate arming only", function()
	local unit = { id = 9, x = 4, y = 4, moves = 2 }
	local obj = {
		GetID = function() return unit.id end, GetX = function() return unit.x end, GetY = function() return unit.y end,
		GetMovesRemaining = function() return unit.moves end,
	}
	UnitManager.GetQueuedDestination = function() return nil end
	local selected = obj
	UI.GetHeadSelectedUnit = function() return selected end
	local idx = Map.GetPlot(4, 4):GetIndex()
	HubSettle.m_pending = { unitId = 9, plotIndex = idx, type = "IMPROVEMENT_FARM", name = "Farm", keepOnKeys = false }
	assert(HubSettle.BuildEnterArmed())
	unit.moves = 0
	assert(not HubSettle.BuildEnterArmed())		-- no moves: Enter is the game's again
	unit.moves = 2
	selected = nil
	assert(not HubSettle.BuildEnterArmed())
	selected = obj
	HubSettle.OnOtherKey(Keys.VK_SHIFT)
	assert(HubSettle.m_pending ~= nil)			-- a modifier alone does not count
	HubSettle.OnOtherKey(65)
	assert(HubSettle.m_pending == nil)
	-- armed for a later turn: keys do not disarm it
	HubSettle.m_pending = { unitId = 9, plotIndex = idx, type = "IMPROVEMENT_FARM", name = "Farm", keepOnKeys = true }
	HubSettle.OnOtherKey(65)
	assert(HubSettle.BuildEnterArmed())
	-- another order for the unit, a queued move, or a turn more than one later: disarmed
	HubSettle.OnUnitOrder(0, 9)
	assert(HubSettle.m_pending == nil)
	HubSettle.m_pending = { unitId = 9, plotIndex = idx, type = "IMPROVEMENT_FARM", name = "Farm", keepOnKeys = true, turn = Game.GetCurrentGameTurn() - 2 }
	assert(not HubSettle.BuildEnterArmed())
	assert(HubSettle.m_pending == nil)
	HubSettle.m_pending = { unitId = 9, plotIndex = idx, type = "IMPROVEMENT_FARM", name = "Farm", keepOnKeys = true }
	assert(HubSettle.BuildEnterArmed())
	-- moved off the tile: disarmed
	unit.x = 5
	assert(not HubSettle.BuildEnterArmed())
	assert(HubSettle.m_pending == nil)
end)

test("BrowserFor: settler, builder, action unit, anything else", function()
	local saved = { settler = HubCore.IsSettler, scan = BuildScan_Improvements, act = HubSettle.ActivationPlots }
	local unit = {}
	local kind = { settler = false, builder = false, act = false }
	HubCore.IsSettler = function() return kind.settler end
	BuildScan_Improvements = function() if kind.builder then return {} end end
	HubSettle.ActivationPlots = function() if kind.act then return {} end end
	eq(HubSettle.BrowserFor(nil), nil)
	eq(HubSettle.BrowserFor(unit), nil)
	kind.act = true
	eq(HubSettle.BrowserFor(unit).text, "Browse tiles to act on")
	kind.builder = true
	eq(HubSettle.BrowserFor(unit).text, "Browse tiles to improve")
	kind.settler = true
	eq(HubSettle.BrowserFor(unit).text, "Browse settle spots")
	eq(type(HubSettle.BrowserFor(unit).open), "function")
	HubCore.IsSettler, BuildScan_Improvements, HubSettle.ActivationPlots = saved.settler, saved.scan, saved.act
end)

test("BuildItemTextOf: improvement first, then where, then the tile, then turns and status", function()
	local e = { name = "Plains, Rainforest", relative = "2 tiles south", turns = 2, worked = true }
	eq(HubSettle.BuildItemTextOf(e, "Lumber Mill plus 2 production", nil), "Lumber Mill plus 2 production, 2 tiles south, Plains Rainforest, 2 turns, worked")
	eq(HubSettle.BuildItemTextOf({ name = "Crabs", relative = "1 tile north", turns = 1 }, "Fishing Boats plus 1 food", "danger: Archer 2 tiles away"),
		"Fishing Boats plus 1 food, 1 tile north, Crabs, 1 turn, danger: Archer 2 tiles away")
	eq(HubSettle.BuildItemTextOf({ name = "Wheat", here = true }, "Farm plus 1 food", nil), "Farm plus 1 food, here, Wheat")
end)

test("identical tile items get a position, then a number", function()
	local items = {
		{ text = "Farm plus 1 food, 2 tiles north-west, Plains Floodplains, 2 turns, worked", where = function() return "1 tile west of Rome" end },
		{ text = "Farm plus 1 food, 2 tiles north-west, Plains Floodplains, 2 turns, worked", where = function() return "2 tiles north of Rome" end },
		{ text = "Mine plus 1 production, here, Hills", where = function() return "in Rome" end },
		{ text = "Farm, 1 tile east, Wheat, 1 turn", where = function() return "x" end },
		{ text = "Farm, 1 tile east, Wheat, 1 turn", where = function() return "x" end },
	}
	HubSettle.Disambiguate(items)
	eq(items[1].text, "Farm plus 1 food, 2 tiles north-west, Plains Floodplains, 2 turns, worked, 1 tile west of Rome")
	eq(items[2].text, "Farm plus 1 food, 2 tiles north-west, Plains Floodplains, 2 turns, worked, 2 tiles north of Rome")
	eq(items[3].text, "Mine plus 1 production, here, Hills")
	eq(items[4].text, "Farm, 1 tile east, Wheat, 1 turn, x, 1 of 2")
	eq(items[5].text, "Farm, 1 tile east, Wheat, 1 turn, x, 2 of 2")
end)
