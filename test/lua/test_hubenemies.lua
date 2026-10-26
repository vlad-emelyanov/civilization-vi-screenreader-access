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

-- ===========================================================================
-- G3a / G3b / G4 wording
-- ===========================================================================
test("scout alarm, escaped, killed, raid expected", function()
	eq(HubEnemies.AlarmText("Barbarian Scout", "Rome", "3 tiles east", "W"),
		"Alarm: Barbarian Scout has seen Rome, 3 tiles east. If it gets back to its camp, a raid follows. Kill it: W targets it")
	eq(HubEnemies.EscapedText("Barbarian Scout", "north-east"), "Barbarian Scout escaped. Expect a raid from the north-east in a few turns")
	eq(HubEnemies.EscapedText("Barbarian Scout", nil), "Barbarian Scout escaped. Expect a raid in a few turns")
	eq(HubEnemies.KilledText("Barbarian Scout"), "Barbarian Scout killed, no raid from it")
	eq(HubEnemies.RaidExpectedText("north-east"), "Raid expected from the north-east")
end)

test("scout heading away names a known camp, the plain case does not", function()
	local old = { ["63:1"] = e("Barbarian Scout", 12, 10, { scout = true, alarmed = true }) }
	local new = { ["63:1"] = e("Barbarian Scout", 14, 10, { scout = true, alarmed = true, where = "4 tiles east of Sivas", campText = "4 tiles north-east" }) }
	eq(HubEnemies.Describe(old, new, {}, dist), "Enemies: Barbarian Scout heading away from Sivas, toward its camp 4 tiles north-east, now 4 tiles east of Sivas.")
	new["63:1"].campText = nil
	eq(HubEnemies.Describe(old, new, {}, dist), "Enemies: Barbarian Scout heading away from Sivas, now 4 tiles east of Sivas.")
end)

test("an alarmed scout that vanished is not 'out of sight' (its own line says escaped); the alarm turn skips 'new'", function()
	local old = { ["63:1"] = e("Barbarian Scout", 15, 10, { alarmed = true }) }
	eq(HubEnemies.Describe(old, {}, {}, dist), nil)
	eq(HubEnemies.Describe({}, { ["63:1"] = e("Barbarian Scout", 12, 10, { alarmNow = true }) }, {}, dist), nil)
end)

test("raid wording: groups, defense, own soldiers", function()
	eq(HubEnemies.PluralName("Spearman", 2), "Spearmen")
	eq(HubEnemies.PluralName("Warrior", 2), "Warriors")
	eq(HubEnemies.PluralName("Horseman", 1), "Horseman")
	eq(HubEnemies.RaidText(nil, "Rome", 3, { { name = "Horseman", count = 1, relative = "3 tiles north" }, { name = "Spearman", count = 2, relative = "4 tiles north" } },
		15, { "Warrior in Rome", "Slinger 2 tiles west" }),
		"Raid: 3 barbarians near Rome: Horseman 3 tiles north, 2 Spearmen 4 tiles north. Rome defense 15. Your nearest soldiers: Warrior in Rome, Slinger 2 tiles west")
	eq(HubEnemies.RaidText("Japan", "Antium", 4, { { name = "Samurai", count = 4, relative = nil } }, nil, {}),
		"Japan: 4 units near Antium: 4 Samurais in Antium. You have no soldiers near")
end)

test("civilian danger and the lone mover", function()
	eq(HubEnemies.DangerText("Builder", "Rome", "Barbarian Horseman", "2 tiles east", "Move it into Rome"),
		"Builder near Rome in danger: Barbarian Horseman 2 tiles east. Move it into Rome")
	eq(HubEnemies.DangerText("Settler", nil, "Barbarian Warrior", nil, nil), "Settler in danger: Barbarian Warrior")
	eq(HubEnemies.AloneText("Settler", 3, "Barbarian Warrior " .. HubEnemies.FromPathText(2, false), "Shift+E"),
		"Settler moving alone, 3 turns. Barbarian Warrior 2 tiles from the path. Escort first: J then M sends a soldier, Shift+E forms the escort")
	eq(HubEnemies.FromPathText(0, false), "on the path")
	eq(HubEnemies.FromPathText(1, true), "1 tile from the target")
	eq(HubEnemies.EscortHintText("Warrior", "Shift+E"), "Warrior here too: Shift+E forms an escort")
end)

test("scout flag: target player, -1 when missing", function()
	eq(HubEnemies.ScoutTarget({ GetBarbarianTargetPlayer = function() return 0 end }), 0)
	eq(HubEnemies.ScoutTarget({ GetBarbarianTargetPlayer = function() return -1 end }), -1)
	eq(HubEnemies.ScoutTarget({}), -1)
end)

test("scout camp: only a revealed camp plot is named", function()
	Game = Game or {}
	local old = Game.GetBarbarianManager
	Game.GetBarbarianManager = function() return { GetTribeCampLocation = function() return 20, 12 end } end
	local unit = { GetBarbarianTribeIndex = function() return 13 end, GetX = function() return 14 end, GetY = function() return 10 end }
	world.revealed_all = false
	eq(HubEnemies.ScoutCampPlot(unit), nil)
	eq(HubEnemies.CampTextFor(unit, 10, 10), nil)
	world.revealed_all = true
	local plot = HubEnemies.ScoutCampPlot(unit)
	eq(plot ~= nil and plot:GetX() or nil, 20)
	-- a camp nearer the city than the scout is not "toward its camp"
	Game.GetBarbarianManager = function() return { GetTribeCampLocation = function() return 11, 10 end } end
	eq(HubEnemies.CampTextFor(unit, 10, 10), nil)
	Game.GetBarbarianManager = old
end)

test("ships stay out of the raid count", function()
	local old = GameInfo.Units
	GameInfo.Units = { [1] = { Domain = "DOMAIN_SEA" }, [2] = { Domain = "DOMAIN_LAND" } }
	eq(HubEnemies.IsNaval({ GetUnitType = function() return 1 end }), true)
	eq(HubEnemies.IsNaval({ GetUnitType = function() return 2 end }), false)
	GameInfo.Units = old
end)

test("raid decision: full once, silent while unchanged, short every 3 turns, full on new member or first close", function()
	local kind, st = HubEnemies.RaidDecision(nil, "a;b", { }, 10)
	eq(kind, "full")
	kind, st = HubEnemies.RaidDecision(st, "a;b", { }, 11)
	eq(kind, nil)
	kind, st = HubEnemies.RaidDecision(st, "a;b", { }, 13)
	eq(kind, "short")
	kind, st = HubEnemies.RaidDecision(st, "a;b", { }, 14)
	eq(kind, nil)
	kind, st = HubEnemies.RaidDecision(st, "a;b", { "a" }, 14)
	eq(kind, "full")		-- a came within 2 tiles for the first time
	kind, st = HubEnemies.RaidDecision(st, "a;b", { "a" }, 15)
	eq(kind, nil)		-- ... and only the first time
	kind, st = HubEnemies.RaidDecision(st, "a;b;c", { "a" }, 15)
	eq(kind, "full")		-- a member joined
	eq(HubEnemies.RaidContinuesText(nil, "Rome", 2), "Raid near Rome continues, 2 barbarians")
	eq(HubEnemies.RaidContinuesText("Japan", "Rome", 1), "Japan raid near Rome continues, 1 unit")
end)

test("exposed civilians wording", function()
	eq(HubEnemies.ExposedText({ { name = "Settler", enemy = "Barbarian Archer", relative = "2 tiles north-east" } }),
		"Settler exposed: Barbarian Archer 2 tiles north-east. Enter again ends the turn anyway")
	eq(HubEnemies.ExposedText({ { name = "Settler", enemy = "Barbarian Archer", relative = "2 tiles north-east" },
		{ name = "Builder", enemy = "Barbarian Archer", relative = "2 tiles north-east" } }),
		"Settler and Builder exposed: Barbarian Archer 2 tiles north-east. Enter again ends the turn anyway")
	eq(HubEnemies.ExposedText({ { name = "Builder", enemy = "Barbarian Archer", relative = "1 tile east" },
		{ name = "Builder", enemy = "Barbarian Warrior", relative = "3 tiles west" } }),
		"2 Builders exposed: Barbarian Archer 1 tile east, Barbarian Warrior 3 tiles west. Enter again ends the turn anyway")
end)

test("end-turn guard: warn, confirm within 10 s, no nagging after, new set warns again, new turn resets", function()
	local g = { turn = -1, warnSig = nil, warnTime = 0, confirmSig = nil }
	HubEnemies.m_guard = g
	eq(HubEnemies.GuardDecision(g, 5, "", 0), "pass")
	eq(HubEnemies.GuardDecision(g, 5, "1", 100), "warn")
	eq(HubEnemies.GuardDecision(g, 5, "1", 105), "confirm")
	eq(HubEnemies.GuardDecision(g, 5, "1", 120), "pass")		-- the player confirmed: no nagging this turn
	eq(HubEnemies.GuardDecision(g, 5, "1;2", 121), "warn")		-- another set
	eq(HubEnemies.GuardDecision(g, 5, "1;2", 135), "warn")		-- too late: warns again
	HubEnemies.EndTurnGuardOtherKey()
	eq(HubEnemies.GuardDecision(g, 5, "1;2", 136), "warn")		-- another key in between
	eq(HubEnemies.GuardDecision(g, 6, "1", 140), "warn")		-- next turn
end)

test("threat items: one per unit key across rules", function()
	local items, seen = {}, {}
	local e = { key = "63:7", x = 1, y = 2 }
	eq(HubEnemies.AddThreatItem(items, seen, e, "Barbarian Archer", "raiding"), true)
	eq(HubEnemies.AddThreatItem(items, seen, e, "Barbarian Archer", "near your city"), false)
	eq(HubEnemies.AddThreatItem(items, seen, { key = "63:8", x = 1, y = 3 }, "Barbarian Archer", "near your city"), true)
	eq(#items, 2)
	eq(items[1].text, "raiding")
end)

test("end-turn key: stale KeyDown state is dropped", function()
	HubEnemies.m_guard = { turn = -1, warnSig = nil, warnTime = 0, confirmSig = nil, down = true, downBlock = true, text = "x", downTime = 0 }
	Game.GetCurrentGameTurn = function() return 3 end
	HubEnemies.ExposedCivilians = function() return {}, "" end
	eq(HubEnemies.EndTurnKey(false, 5), false)
end)

test("threat item for a soldier near a city has no position of its own (the places list adds it once)", function()
	local archer = { key = "63:9", x = 7, y = 7, unit = {} }
	local realScan, realName = HubEnemies.ScanThreats, PlotDescription_GetUnitName
	HubEnemies.ScanThreats = function() return { raids = {}, civilians = {}, nearCity = {
		{ enemy = archer, city = { GetName = function() return "Rome" end }, d = 2, relative = "2 tiles south-east" } } } end
	PlotDescription_GetUnitName = function() return "Barbarian Archer" end
	local ok, items = pcall(HubEnemies.ThreatItems)
	HubEnemies.ScanThreats, PlotDescription_GetUnitName = realScan, realName
	assert(ok, tostring(items))
	eq(#items, 1)
	eq(items[1].text, "Barbarian Archer, near your city")
end)
