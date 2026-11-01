-- UnexploredScan.lua: the nearest frontier plot in each of six directions
stub("engine")
local world = stub("world").new{ width = 40, height = 30 }
world:install()
include("UnexploredScan")

local vis = PlayersVisibility[0]
local RX, RY = 20, 14

-- everything farther than `radius` from the reference is unexplored
local function hideBeyond(radius)
	for y = 0, 29 do for x = 0, 39 do
		world:set(x, y, { hidden = Map.GetPlotDistance(RX, RY, x, y) > radius, terrain = "grass", mountain = false, impassable = false })
	end end
end

local function bySector(list)
	local t = {}
	for _, e in ipairs(list) do t[e.sector] = e end
	return t
end

test("sectors: six 60 degree directions", function()
	eq(UnexploredScan.Sector(20, 14, 26, 14), "east")
	eq(UnexploredScan.Sector(20, 14, 14, 14), "west")
	eq(UnexploredScan.Sector(20, 14, 23, 20), "north-east")
	eq(UnexploredScan.Sector(20, 14, 17, 20), "north-west")
	eq(UnexploredScan.Sector(20, 14, 23, 8), "south-east")
	eq(UnexploredScan.Sector(20, 14, 17, 8), "south-west")
	eq(UnexploredScan.Sector(20, 14, 20, 14), nil)
end)

test("text", function()
	eq(UnexploredScan.Text("north-east", 7), "Unexplored north-east, nearest edge 7 tiles")
	eq(UnexploredScan.Text("west", 1), "Unexplored west, nearest edge 1 tile")
end)

test("a known disc: one nearest edge in each of the six directions, all at the radius", function()
	hideBeyond(6)
	local list = UnexploredScan.Find(RX, RY, vis, false)
	eq(#list, 6)
	for _, e in ipairs(list) do
		eq(e.distance, 6)
		eq(UnexploredScan.Sector(RX, RY, e.x, e.y), e.sector)
		assert(UnexploredScan.IsFrontier(Map.GetPlot(e.x, e.y), vis, false))
	end
	-- equal distance: north-east first, north-west last
	eq(list[1].sector, "north-east")
	eq(list[6].sector, "north-west")
end)

test("sorted nearest first, a sector with nothing is left out", function()
	hideBeyond(9)
	-- reveal everything to the west: no frontier there (except the map edge, which is not unexplored)
	for y = 0, 29 do for x = 0, 19 do world:set(x, y, { hidden = false }) end end
	-- a nearer unexplored pocket north-east of the reference
	world:set(23, 17, { hidden = true })
	local list = UnexploredScan.Find(RX, RY, vis, false)
	local t = bySector(list)
	assert(t["north-east"] and t["north-east"].distance < 6, "pocket is the nearest north-east edge")
	assert(t["west"] == nil, "west is explored")
	for i = 2, #list do assert(list[i - 1].distance <= list[i].distance) end
end)

test("everything revealed: nothing", function()
	hideBeyond(100)
	eq(#UnexploredScan.Find(RX, RY, vis, false), 0)
end)

test("land: water, mountains and impassable plots are no frontier; the next land plot is", function()
	hideBeyond(6)
	-- the whole ring of radius 5 east is water, radius 4 is mountain: the nearest east edge must be on plain land elsewhere
	for y = 0, 29 do for x = 0, 39 do
		local d = Map.GetPlotDistance(RX, RY, x, y)
		if d >= 5 and d <= 6 and UnexploredScan.Sector(RX, RY, x, y) == "east" then world:set(x, y, { terrain = "water" }) end
	end end
	local land = bySector(UnexploredScan.Find(RX, RY, vis, false))
	assert(land["east"] == nil or land["east"].distance < 5 or land["east"].distance > 6)
	local sea = bySector(UnexploredScan.Find(RX, RY, vis, true))
	assert(sea["east"] ~= nil, "a ship finds the water frontier east")
	eq(sea["east"].distance, 6)
	assert(Map.GetPlot(sea["east"].x, sea["east"].y):IsWater())
	-- mountains
	hideBeyond(6)
	for y = 0, 29 do for x = 0, 39 do
		if Map.GetPlotDistance(RX, RY, x, y) == 6 then world:set(x, y, { mountain = true }) end
	end end
	for _, e in ipairs(UnexploredScan.Find(RX, RY, vis, false)) do
		assert(not Map.GetPlot(e.x, e.y):IsMountain())
	end
	eq(#UnexploredScan.Find(RX, RY, vis, false), 0, "only mountains on the edge: the plot inside (distance 5) has no unrevealed neighbour")
end)

test("the search stops early: an explored ring around the reference needs few plots", function()
	hideBeyond(4)
	local calls = 0
	local real = Map.GetPlot
	Map.GetPlot = function(x, y) calls = calls + 1; return real(x, y) end
	UnexploredScan.Find(RX, RY, vis, false)
	Map.GetPlot = real
	assert(calls < 1500, "scanned " .. calls .. " plots")
end)

test("a wrapping map: the nearest edge across the seam", function()
	local w2 = stub("world").new{ width = 20, height = 20, wrap = true }
	w2:install()
	for y = 0, 19 do for x = 0, 19 do w2:set(x, y, { hidden = (x >= 8 and x <= 12) }) end end
	local list = UnexploredScan.Find(2, 10, PlayersVisibility[0], false)
	local t = bySector(list)
	-- west of x = 2 wraps round to the unexplored band at x 8 to 12 (x = 13 is the frontier, 9 tiles from x = 2 going west)
	assert(t["west"] ~= nil)
	eq(t["west"].x, 13)
	eq(t["west"].distance, 9)
	world:install()
end)
