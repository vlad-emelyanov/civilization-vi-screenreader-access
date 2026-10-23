-- SettleScan.lua: resources per ring (ring 1 = the 6 neighbours a new city owns at once)
stub("engine")
include("SettleScan")

-- A fresh poor world per test (the scan caches per turn, so every test defeats the cache)
local function freshWorld()
	local w = stub("world").new{ width = 20, height = 14 }
	for y = 0, 13 do for x = 0, 19 do w:set(x, y, { food = 1, prod = 0, terrain = "desert" }) end end
	w:install()
	Game.GetCurrentGameTurn = function() return math.random(1, 1e9) end
	return w
end

local function settler(w, x, y)
	return w.fakeUnit(w:unit(0, x, y, { moves = 2 }))
end

local function site(scan, x, y)
	for _, c in ipairs(scan.list) do if c.x == x and c.y == y then return c end end
end

local function lush(w, cx, cy)
	for dy = -3, 3 do for dx = -3, 3 do w:set(cx + dx, cy + dy, { food = 3, prod = 2, terrain = "grass" }) end end
	w:set(cx, cy, { river = true })
end

test("a resource in ring 1 beats the same resource in ring 2", function()
	local function hereScan(wx, wy)
		local w = freshWorld()
		lush(w, 10, 7)
		w:set(wx, wy, { resource = "Wheat" })
		return SettleScan_Scan(settler(w, 10, 7), true).here
	end
	local a, b = hereScan(11, 7), hereScan(12, 7)		-- ring 1 / ring 2 of (10,7)
	istrue(a ~= nil and b ~= nil, "no here candidate")
	istrue(a.static > b.static, "ring 1 " .. a.static .. " vs ring 2 " .. b.static)
	contains(table.concat(a.reasons, "|"), "ring 1: wheat")
	contains(table.concat(b.reasons, "|"), "ring 2: wheat")
	contains(a.detail, "Ring 1, the city's first tiles: Wheat (bonus)")
end)

test("owned resources do not count and are named, ring 3 only in the detail", function()
	local w = freshWorld()
	lush(w, 10, 7)
	w:set(11, 7, { resource = "Silk", rclass = "luxury", owner = 2 })
	w:set(12, 7, { resource = "Iron", rclass = "strategic" })
	w:set(13, 7, { resource = "Wine", rclass = "luxury" })
	local scan = SettleScan_Scan(settler(w, 10, 7), true)
	local c = scan.here
	istrue(c ~= nil, "site missing")
	local reasons = table.concat(c.reasons, "|")
	istrue(not string.find(reasons, "silk", 1, true), "taken silk counted: " .. reasons)
	istrue(not string.find(reasons, "wine", 1, true), "ring 3 in the reasons: " .. reasons)
	contains(reasons, "ring 2: iron")
	contains(c.detail, "Ring 3: Wine (luxury)")
	contains(c.detail, "Silk (luxury, taken by")
	contains(c.detail, "ring 1: ")
end)

test("Ring1Resources reads only the free neighbours", function()
	local w = freshWorld()
	w:set(6, 6, { resource = "Wheat" })
	w:set(7, 6, { resource = "Silk", rclass = "luxury", owner = 1 })
	w:set(9, 9, { resource = "Iron", rclass = "strategic" })
	local names = SettleScan_Ring1Resources(Map.GetPlot(6, 7))
	eq(#names, 1)
	eq(names[1], "wheat")
end)
