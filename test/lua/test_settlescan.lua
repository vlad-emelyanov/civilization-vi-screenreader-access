-- SettleScan.lua: can a city be founded here, and how are sites scored
stub("engine")
local world = stub("world").new{ width = 20, height = 14 }
world:install()
include("SettleScan")

local function reasonAt(x, y)
	local ok, reason = SettleScan_CheckPlot(Map.GetPlot(x, y), {})
	return ok, reason
end

test("plain land is fine", function()
	eq(reasonAt(5, 5), true)
end)

test("terrain blockers", function()
	world:set(1, 1, { terrain = "water" })
	world:set(2, 1, { terrain = "water", lake = true })
	world:set(3, 1, { mountain = true })
	world:set(4, 1, { wonder = true })
	world:set(5, 1, { impassable = true })
	world:set(6, 1, { city = true })
	local function why(x) local _, r = reasonAt(x, 1); return r end
	eq(why(1), "water")
	eq(why(2), "lake")
	eq(why(3), "mountain")
	eq(why(4), "natural wonder")
	eq(why(5), "impassable")
	eq(why(6), "already a city")
end)

test("edge of the map and unexplored", function()
	local ok, reason = SettleScan_CheckPlot(nil, {})
	eq(ok, false)
	eq(reason, "edge of the map")
	world:set(8, 8, { hidden = true })
	local ok2, reason2 = reasonAt(8, 8)
	eq(ok2, false)
	eq(reason2, "unexplored")
end)

test("foreign territory names the owner", function()
	world:set(10, 3, { owner = 2 })
	local ok, reason = reasonAt(10, 3)
	eq(ok, false)
	eq(reason, "owned by LOC_CIV_2")
end)

test("too close to a city: distance 3 blocks, 4 is fine", function()
	world:city(0, 10, 8, "Rome")
	local cities = { { x = 10, y = 8, owner = 0, id = 1 } }
	local ok3, why3 = SettleScan_CheckPlot(Map.GetPlot(13, 8), cities)
	eq(ok3, false)
	eq(why3, "too close to Rome")
	local ok4 = SettleScan_CheckPlot(Map.GetPlot(14, 8), cities)
	eq(ok4, true)
end)

test("a city on a plot we have not seen is not named", function()
	world:set(15, 12, { hidden = true, city = true })
	local ok, why = SettleScan_CheckPlot(Map.GetPlot(16, 12), { { x = 15, y = 12, owner = 1, id = 9 } })
	eq(ok, false)
	eq(why, "")
end)

test("CannotText", function()
	eq(SettleScan_CannotText(nil), "cannot settle")
	eq(SettleScan_CannotText(""), "cannot settle")
	eq(SettleScan_CannotText("water"), "cannot settle: water")
end)

-- A fresh world per scoring test: the scan caches per turn, so each test uses its own settler position
local function freshWorld()
	local w = stub("world").new{ width = 20, height = 14 }
	-- poor everywhere, so that the one good site stands out
	for y = 0, 13 do for x = 0, 19 do w:set(x, y, { food = 1, prod = 0, terrain = "desert" }) end end
	w:install()
	Game.GetCurrentGameTurn = function() return math.random(1, 1e9) end		-- defeats the scan cache
	return w
end

local function settler(w, x, y)
	local u = w:unit(0, x, y, { moves = 2 })
	return w.fakeUnit(u)
end

test("scan prefers the river site with good yields", function()
	local w = freshWorld()
	for dy = -2, 2 do for dx = -2, 2 do w:set(10 + dx, 7 + dy, { food = 3, prod = 2, terrain = "grass" }) end end
	w:set(10, 7, { river = true })
	local scan = SettleScan_Scan(settler(w, 4, 7), true)
	istrue(#scan.list > 0, "no candidates")
	local best = scan.best
	istrue(math.abs(best.x - 10) <= 1 and math.abs(best.y - 7) <= 1, "best is " .. best.x .. "," .. best.y)
	eq(best.items[1] ~= nil, true)
	istrue(best.score > scan.list[#scan.list].score or #scan.list == 1)
end)

test("scan ignores sites that fail the rules (water, near a city)", function()
	local w = freshWorld()
	for x = 0, 19 do w:set(x, 6, { terrain = "water" }) end
	w:city(0, 8, 9, "Rome")
	local scan = SettleScan_Scan(settler(w, 8, 10), true)
	for _, c in ipairs(scan.list) do
		istrue(c.y ~= 6, "settled on water")
		istrue(Map.GetPlotDistance(c.x, c.y, 8, 9) > 3, "too close to Rome: " .. c.x .. "," .. c.y)
	end
	eq(scan.hereReason, "too close to Rome")
end)

test("hostile units nearby lower the score", function()
	local w = freshWorld()
	for dy = -2, 2 do for dx = -2, 2 do w:set(10 + dx, 7 + dy, { food = 3, prod = 2, terrain = "grass" }) end end
	local calm = SettleScan_Scan(settler(w, 4, 7), true)
	local calmScore
	for _, c in ipairs(calm.list) do if c.x == 10 and c.y == 7 then calmScore = c.static end end
	w:unit(63, 11, 7, { combat = 8 })		-- a barbarian
	local danger = SettleScan_Scan(settler(w, 4, 7), true)
	local dangerScore, text
	for _, c in ipairs(danger.list) do
		if c.x == 10 and c.y == 7 then dangerScore = c.static; text = table.concat(c.negatives, "|") end
	end
	istrue(calmScore ~= nil and dangerScore ~= nil, "site missing")
	istrue(dangerScore < calmScore, "score did not drop")
	contains(text, "barbarians nearby")
end)

test("unreachable sites are not offered", function()
	local w = freshWorld()
	for dy = -2, 2 do for dx = -2, 2 do w:set(10 + dx, 7 + dy, { food = 3, prod = 2, terrain = "grass" }) end end
	w.unreachable = {}
	for y = 0, 13 do for x = 8, 12 do w.unreachable[y * 20 + x] = true end end
	local scan = SettleScan_Scan(settler(w, 4, 7), true)
	for _, c in ipairs(scan.list) do
		istrue(c.x < 8 or c.x > 12, "offered unreachable " .. c.x .. "," .. c.y)
	end
end)
