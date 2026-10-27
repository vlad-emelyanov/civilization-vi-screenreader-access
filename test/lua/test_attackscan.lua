-- HubCursor / HubTargets (round 27, M5 + M9): X in an attack mode walks only the attackable plots, nearest first;
-- the empty message counts enemies out of range; the transfer list is nearest first with distances.
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

test("attack scan entries: only the given plots, nearest first, all valid", function()
	-- plot index = y * 30 + x
	local targets = { [5 * 30 + 9] = true, [5 * 30 + 6] = true, [4 * 30 + 12] = true }
	local found = HubCursor.AttackScanEntries(targets, 5, 5)
	eq(#found, 3)
	eq(found[1].x, 6)
	eq(found[2].x, 9)
	eq(found[3].x, 12)
	for _, e in ipairs(found) do istrue(e.valid) end
end)

test("attack scan entries: empty set gives no stops", function()
	eq(#HubCursor.AttackScanEntries({}, 5, 5), 0)
end)

test("no enemy text: out of range count", function()
	eq(HubCursor.NoEnemyText("Archer", "Barbarian Archer", "6 tiles north-east", 0),
		"No enemy in range of the Archer. Nearest enemy: Barbarian Archer, 6 tiles north-east")
	eq(HubCursor.NoEnemyText("Archer", "Barbarian Archer", "6 tiles north-east", 1),
		"No enemy in range of the Archer. Nearest enemy: Barbarian Archer, 6 tiles north-east, 1 more enemy in view out of range")
	eq(HubCursor.NoEnemyText("Archer", "Barbarian Archer", nil, 3),
		"No enemy in range of the Archer. Nearest enemy: Barbarian Archer, 3 more enemies in view out of range")
	eq(HubCursor.NoEnemyText("Archer", nil, nil, 2), "No enemy in view")
end)

test("transfer items: nearest city first, then by name, with distance text", function()
	local items = HubTargets.TransferItems({
		{ name = "Rome", distance = 5, plotIndex = 10 },
		{ name = "Antium", distance = 1, plotIndex = 11 },
		{ name = "Capua", distance = 5, plotIndex = 12 },
		{ name = "Zama", distance = 5, plotIndex = 9 },
	})
	eq(#items, 4)
	eq(items[1].text, "Antium, 1 tile")
	eq(items[2].text, "Capua, 5 tiles")
	eq(items[3].text, "Rome, 5 tiles")
	eq(items[4].text, "Zama, 5 tiles")
	eq(items[1].plotIndex, 11)
end)
