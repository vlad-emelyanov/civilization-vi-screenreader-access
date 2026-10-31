-- UnitDetails.lua: the wording of Shift+I and the short strength / city defence phrases
stub("engine")
local world = stub("world").new{ width = 20, height = 12 }
world:install()
include("ScreenReader")
include("PlotDescription")

test("own melee unit: level, experience, promotion, strength, moves, health, promotions", function()
	eq(UnitDetails_Text{ name = "Warrior", own = true, strength = 20, level = 1, xp = 5, xpNext = 15, promotionAvailable = true,
		moves = 2, maxMoves = 2, sight = 2, damage = 0, maxDamage = 100, promotions = { "Battlecry", "Tortoise" } },
		"Warrior, level 1, 5 of 15 experience, promotion available. Strength 20. 2 of 2 moves, sight 2. Health 100 of 100. Promotions: Battlecry, Tortoise.")
end)

test("ranged unit says ranged strength and range", function()
	eq(UnitDetails_Text{ name = "Archer", own = true, strength = 15, ranged = 25, range = 2, level = 1, xp = 0, xpNext = 15, moves = 1.5, maxMoves = 2,
		damage = 40, maxDamage = 100 },
		"Archer, level 1, 0 of 15 experience. Strength 15. Ranged 25, range 2. 1.5 of 2 moves. Health 60 of 100.")
end)

test("foreign unit: owner in the name, no experience, no moves", function()
	eq(UnitDetails_Text{ name = "Egyptian Archer", own = false, strength = 15, ranged = 25, range = 2, level = 2, xp = 7, xpNext = 30,
		moves = 2, maxMoves = 2, damage = 40, maxDamage = 100, promotions = { "Volley" } },
		"Egyptian Archer, level 2. Strength 15. Ranged 25, range 2. Health 60 of 100. Promotions: Volley.")
end)

test("civilian: moves, charges, no strength, no level, health only when hurt", function()
	eq(UnitDetails_Text{ name = "Builder", own = true, moves = 2, maxMoves = 2, sight = 2, damage = 0, maxDamage = 100, buildCharges = 3, level = 1 },
		"Builder. 2 of 2 moves, sight 2. 3 charges left.")
	eq(UnitDetails_Text{ name = "Settler", own = true, moves = 2, maxMoves = 2, damage = 20, maxDamage = 100 },
		"Settler. 2 of 2 moves. Health 80 of 100.")
end)

test("religious unit and great person", function()
	eq(UnitDetails_Text{ name = "Missionary", own = true, religious = 110, spreads = 3, moves = 3, maxMoves = 3 },
		"Missionary. Religious strength 110. 3 of 3 moves. Spreads left 3.")
	eq(UnitDetails_Text{ name = "Sun Tzu", own = true, moves = 2, maxMoves = 2, actionCharges = 1, passive = "Art of War" },
		"Sun Tzu. 2 of 2 moves. 1 action charge left. Passive effect: Art of War.")
end)

test("bombard unit", function()
	eq(UnitDetails_Text{ name = "Catapult", own = false, strength = 25, bombard = 35, range = 2 },
		"Catapult. Strength 25. Bombard 35, range 2.")
end)

test("military first", function()
	local list = UnitDetails_Order{ { name = "Builder" }, { name = "Warrior", military = true }, { name = "Settler" } }
	eq(list[1].name, "Warrior"); eq(list[2].name, "Builder"); eq(list[3].name, "Settler")
end)

test("short strength and city defence", function()
	eq(UnitDetails_ShortStrength(15, 25, 0), "strength 15, ranged 25")
	eq(UnitDetails_ShortStrength(0, 0, 0), nil)
	eq(UnitDetails_CityDefenseText(28, 0, 100, 0, 200), "strength 28, walls 100 of 100, health 200 of 200")
	eq(UnitDetails_CityDefenseText(28, 50, 100, 50, 200), "strength 28, walls 50 of 100, health 150 of 200")
	eq(UnitDetails_CityDefenseText(20, 0, 0, 0, 200), "strength 20, health 200 of 200")
end)
