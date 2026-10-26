-- CombatText_PickDefender: the unit a shot at a stack really hits (the soldier, never the captured civilian)
stub("engine")
local world = stub("world").new{ width = 30, height = 20 }
world:install()
include("ScreenReader")
include("PlotDescription")
include("CombatText")

local function u(name, c, r, b) return { name = name, GetCombat = function() return c end, GetRangedCombat = function() return r end, GetBombardCombat = function() return b end } end

test("soldier beats the civilian whatever the order", function()
	local builder, man = u("Barbarian Builder", 0, 0, 0), u("Barbarian Man-At-Arms", 45, 0, 0)
	eq(CombatText_PickDefender({ builder, man }).name, "Barbarian Man-At-Arms")
	eq(CombatText_PickDefender({ man, builder }).name, "Barbarian Man-At-Arms")
end)

test("filter and empty", function()
	local builder, man = u("Builder", 0, 0, 0), u("Man", 45, 0, 0)
	eq(CombatText_PickDefender({ builder, man }, function(x) return x == builder end), builder)
	eq(CombatText_PickDefender({}), nil)
end)

test("ranged-only unit counts as a soldier", function()
	eq(CombatText_PickDefender({ u("Builder", 0, 0, 0), u("Archer", 10, 25, 0) }).name, "Archer")
end)

test("melee Combat decides, not ranged: Warrior beats Archer", function()
	local warrior, archer = u("Warrior", 20, 0, 0), u("Archer", 15, 25, 0)
	eq(CombatText_PickDefender({ archer, warrior }).name, "Warrior")
	eq(CombatText_PickDefender({ warrior, archer }).name, "Warrior")
end)
