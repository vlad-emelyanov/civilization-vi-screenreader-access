-- StatusMessagePanel.lua mod block: which game status lines are dropped as already spoken by the hub.
-- The game's text templates contain {LOC_GRAMMAR_A_AN << x}, which the engine resolves to "a" or "an" depending on
-- the word; the code turns " a <arg>" into "an?" so both forms match (the "a/an" bug).
local Strings = stub("engine")
Strings.LOC_COMBAT_YOUR_UNIT_DAMAGED_ENEMY = "Your {1_UnitName} damaged an enemy {2_EnUName}({3_Num} damage)!"
Strings.LOC_COMBAT_YOU_KILLED_ENEMY_UNIT = "While defending, your {2_UnitName} ({5_Num} damage) killed a {3_EnemyAdjective} {4_EnemyUnitName}!"
Strings.LOC_COMBAT_ENEMY_UNIT_WITHDREW = "Your {1_UnitName} ({2_Num} damage) was attacked by an enemy {3_EnUName} ({4_Num} damage)!"

Strings.LOC_COMBAT_YOUR_DISTRICT_BOMBARDED_ENEMY = "{1_Name} bombarded an enemy {2_EnUName}! ({3_Damage} damage)"

load_mod_block("Assets/UI/Panels/StatusMessagePanel.lua", 1)

local function covered(msg) return SRIsCoveredCombatMessage(msg) end

test("nothing is covered unless the hub just spoke a combat line", function()
	Clock.now = 100
	eq(covered("Your Warrior damaged an enemy Archer(12 damage)!"), false)
	SRCombatSpoken()
	eq(covered("Your Warrior damaged an enemy Archer(12 damage)!"), true)
	Clock.now = 101.9
	eq(covered("Your Warrior damaged an enemy Archer(12 damage)!"), true)
	Clock.now = 102.5
	eq(covered("Your Warrior damaged an enemy Archer(12 damage)!"), false)
end)

test("a and an both match", function()
	Clock.now = 200
	SRCombatSpoken()
	eq(covered("While defending, your Warrior (3 damage) killed a Barbarian Horseman!"), true)
	eq(covered("While defending, your Warrior (3 damage) killed an Aztec Eagle Warrior!"), true)
end)

test("other texts, city targets and withdrawals of other templates stay", function()
	Clock.now = 300
	SRCombatSpoken()
	eq(covered("Your Warrior damaged the city of Rome (12 damage)!"), false)
	eq(covered("Production of Campus complete"), false)
	eq(covered(nil), false)
end)

test("whitespace differences do not matter", function()
	Clock.now = 400
	SRCombatSpoken()
	eq(covered("  Your Warrior   damaged an enemy Archer(12 damage)!"), true)
	eq(covered("Your Warrior was attacked by an enemy Slinger (5 damage) (2 damage)!"), false)
	eq(covered("Your Warrior (2 damage) was attacked by an enemy Slinger (5 damage)!"), true)
end)

test("a city bombard line is dropped once the hub spoke the fight", function()
	Clock.now = 500
	SRCombatSpoken()
	eq(covered("Lugdunum bombarded an enemy Catapult! (0 damage)"), true)
end)
