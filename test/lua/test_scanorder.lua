-- HubCursor: X scan order in attack modes (attackable without war, hostile, would declare war, rest) and the W no-enemy message
stub("engine")
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

local function order(list)
	table.sort(list, HubCursor.ScanEntryBefore)
	local ids = {}
	for _, e in ipairs(list) do table.insert(ids, e.id) end
	return table.concat(ids, ",")
end

test("hostile target first even when a peaceful unit is nearer", function()
	eq(order({
		{ id = "vilnius", index = 1, distance = 2, hostile = false, war = true, valid = false },
		{ id = "barb", index = 2, distance = 6, hostile = true, valid = false },
	}), "barb,vilnius")
end)

test("attackable first, then hostile out of range, then would-declare-war, then the rest, nearest first", function()
	eq(order({
		{ id = "rest", index = 1, distance = 1, hostile = false, war = false, valid = false },
		{ id = "war", index = 2, distance = 1, hostile = false, war = true, valid = false },
		{ id = "farhostile", index = 3, distance = 5, hostile = true, valid = false },
		{ id = "far", index = 4, distance = 4, hostile = true, valid = true },
		{ id = "near", index = 5, distance = 2, hostile = true, valid = true },
	}), "near,far,farhostile,war,rest")
end)

test("same rank and distance: plot index decides", function()
	eq(order({ { id = "b", index = 9, distance = 3, hostile = true }, { id = "a", index = 4, distance = 3, hostile = true } }), "a,b")
end)

test("no enemy message", function()
	eq(HubCursor.NoEnemyText("Archer", "Barbarian Archer", "6 tiles north-east"),
		"No enemy in range of the Archer. Nearest enemy: Barbarian Archer, 6 tiles north-east")
	eq(HubCursor.NoEnemyText("Archer", nil, nil), "No enemy in view")
end)

test("IsAttackMode: only attack modes, a move only with the attack intent", function()
	InterfaceModeTypes.MOVE_TO = 1
	InterfaceModeTypes.RANGE_ATTACK = 2
	InterfaceModeTypes.DEPLOY = 3
	istrue(HubTargets.IsAttackMode(2))
	istrue(not HubTargets.IsAttackMode(3))
	istrue(not HubTargets.IsAttackMode(1))
	istrue(not HubTargets.IsAttackMode(nil))
end)
