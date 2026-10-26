-- HubEnemies.lua: the turn-start enemy line (pure wording)
stub("engine")
local world = stub("world").new{ width = 30, height = 20 }
world:install()
include("ScreenReader")
include("PlotDescription")
include("HubCore")
include("HubEnemies")

local function dist(x1, y1, x2, y2) return Map.GetPlotDistance(x1, y1, x2, y2) end
local function e(name, x, y, extra)
	local t = { name = name, x = x, y = y, damage = 0, maxhp = 100, where = "3 tiles east of Sivas", anchorName = "Sivas",
		anchorX = 10, anchorY = 10, near = 3, mine = false }
	for k, v in pairs(extra or {}) do t[k] = v end
	return t
end

test("nothing near, nothing said", function()
	eq(HubEnemies.Describe({}, {}, {}, dist), nil)
end)

test("new unit", function()
	eq(HubEnemies.Describe({}, { ["63:1"] = e("Barbarian Horseman", 14, 10, { where = "4 tiles east of Sivas" }) }, {}, dist),
		"Enemies: Barbarian Horseman new, 4 tiles east of Sivas.")
end)

test("moved toward, away, and the territory words", function()
	local old = { ["63:1"] = e("Barbarian Swordsman", 15, 10), ["63:2"] = e("Barbarian Scout", 12, 10, { near = 5 }) }
	local new = { ["63:1"] = e("Barbarian Swordsman", 13, 10, { where = "3 tiles east of Sivas", mine = true }),
		["63:2"] = e("Barbarian Scout", 15, 10, { near = 5, where = "5 tiles east of Sivas" }) }
	eq(HubEnemies.Describe(old, new, {}, dist),
		"Enemies: Barbarian Swordsman moved 2 tiles toward Sivas, now 3 tiles east of Sivas, in your territory; Barbarian Scout moved 3 tiles away from Sivas, now 5 tiles east of Sivas.")
end)

test("out of sight, but not when it died", function()
	local old = { ["63:1"] = e("Barbarian Scout", 15, 10), ["63:2"] = e("Barbarian Warrior", 14, 10) }
	eq(HubEnemies.Describe(old, {}, { ["63:2"] = true }, dist), "Enemies: Barbarian Scout out of sight.")
end)

test("still visible but outside the radius: no longer near", function()
	local old = { ["63:1"] = e("Barbarian Scout", 15, 10) }
	eq(HubEnemies.Describe(old, {}, {}, dist, { ["63:1"] = true }), "Enemies: Barbarian Scout no longer near.")
end)

test("health change and still", function()
	local old = { ["63:1"] = e("Barbarian Warrior", 13, 10) }
	eq(HubEnemies.Describe(old, { ["63:1"] = e("Barbarian Warrior", 13, 10) }, {}, dist), "Enemies: Barbarian Warrior still 3 tiles east of Sivas.")
	eq(HubEnemies.Describe(old, { ["63:1"] = e("Barbarian Warrior", 13, 10, { damage = 60 }) }, {}, dist),
		"Enemies: Barbarian Warrior still 3 tiles east of Sivas, wounded, 40 of 100.")
	old["63:1"].damage = 60
	eq(HubEnemies.Describe(old, { ["63:1"] = e("Barbarian Warrior", 13, 10, { damage = 30 }) }, {}, dist),
		"Enemies: Barbarian Warrior still 3 tiles east of Sivas, healed, 70 of 100.")
end)

test("cap at four, unchanged ones dropped when crowded", function()
	local old, new = {}, {}
	for i = 1, 6 do
		old["63:" .. i] = e("Barbarian Scout", 20, 10, { near = i })
		new["63:" .. i] = e("Barbarian Scout", 19, 10, { near = i })
	end
	old["63:7"] = e("Barbarian Warrior", 13, 10); new["63:7"] = e("Barbarian Warrior", 13, 10)
	local text = HubEnemies.Describe(old, new, {}, dist)
	assert(text:find("; and 2 more%.$"), text)
	assert(not text:find("Warrior"), text)
end)
