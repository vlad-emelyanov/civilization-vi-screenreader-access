-- HubOverview.lua: the pure wording of the area overview (Shift+J)
stub("engine")
HubCore = {}
KeyNavList_Create = function() return {} end
include("HubOverview")

test("join and top terrains", function()
	eq(HubOverview.Join({}), "")
	eq(HubOverview.Join({ "a" }), "a")
	eq(HubOverview.Join({ "a", "b" }), "a and b")
	eq(HubOverview.Join({ "a", "b", "c" }), "a, b and c")
	local top = HubOverview.TopTerrains({ grassland = 5, plains = 5, desert = 2, tundra = 1 }, 2)
	eq(top[1], "grassland"); eq(top[2], "plains"); eq(#top, 2)
end)

test("area text", function()
	eq(HubOverview.AreaText("Rome", {
		revealed = 37, terrains = { grassland = 12, plains = 8, desert = 1 }, hills = 4, mountains = 0,
		feature = { name = "woods", count = 5 }, coast = "on the coast", river = true,
		luxuries = { "Silk", "Wine" }, strategics = { "Iron" }, unexplored = 4 }),
		"Rome: grassland and plains, woods, hills, on the coast and a river; luxuries: Silk, Wine; strategic: Iron; 4 tiles unexplored")
	-- minor feature / few hills are not mentioned
	eq(HubOverview.AreaText("This area", { revealed = 10, terrains = { tundra = 3 }, hills = 1, feature = { name = "marsh", count = 2 }, lake = true }),
		"This area: tundra, a lake")
	eq(HubOverview.AreaText("This area", { revealed = 0, terrains = {} }), "This area: unexplored")
end)

test("extent rounds the offsets", function()
	local e = HubOverview.Extent({ { 0, 0 }, { 2.5, 3 }, { -1, -4 }, { -6, 1 } })
	eq(e.north, 3); eq(e.south, 4); eq(e.east, 3); eq(e.west, 6)
end)

test("continent text", function()
	eq(HubOverview.ContinentText{
		name = "Asia", known = 40, centre = "Rome", extent = { north = 12, south = 6, east = 8, west = 2 },
		cities = { mine = { "Antium", "Rome" }, others = { { civ = "Babylon", names = { "Ur" } } }, minors = { "Geneva" } },
		edges = { "north", "east" } },
		"Asia: 40 tiles known; extends about 12 north, 6 south, 8 east, 2 west of Rome; cities on it: yours Antium and Rome; Babylon: Ur; city-states: Geneva; unexplored edges: north, east")
	local t = HubOverview.ContinentText{ name = "Isle", known = 1, centre = "here", extent = { north = 0, south = 0, east = 0, west = 0 },
		cities = { mine = {}, others = {}, minors = {} }, edges = {} }
	eq(t, "Isle: 1 tile known (a small island); extends about 0 north, 0 south, 0 east, 0 west of here; no cities seen on it; no unexplored edges")
end)

test("sector text", function()
	local function e(dist, props) props.dist = dist; if props.revealed == nil then props.revealed = true end; return props end
	eq(HubOverview.SectorText("North", {}), "North: edge of the map")
	eq(HubOverview.SectorText("North", { e(1, { revealed = false }), e(2, { revealed = false }) }), "North: unexplored")
	local entries = {
		e(1, { kind = "grassland" }), e(2, { kind = "grassland" }), e(3, { kind = "tundra" }),
		e(5, { kind = "plains", owner = "Babylon" }), e(6, { water = true }), e(7, { water = true }), e(8, { water = true }),
		e(7, { kind = "plains", city = "Ur", cityOwner = "Babylon" }), e(8, { revealed = false }),
		e(8, { revealed = false }), e(8, { revealed = false }),
	}
	eq(HubOverview.SectorText("North", entries),
		"North: grassland and plains, Babylon's territory after 5 tiles, ocean from 6 tiles, Ur of Babylon at 7 tiles, partly unexplored")
	-- a city remembered from when it was in view says so
	eq(HubOverview.SectorText("South", { e(2, { kind = "plains", city = "Ur", cityOwner = "Babylon", stale = true }) }),
		"South: plains, Ur of Babylon at 2 tiles (last seen)")
	-- water that is a minority of the far plots is not "ocean from"
	eq(HubOverview.SectorText("East", { e(1, { water = true }), e(2, { kind = "plains" }), e(3, { kind = "plains" }), e(4, { kind = "plains", city = "Rome" }) }),
		"East: plains, your city Rome at 4 tiles")
	eq(HubOverview.SectorText("West", { e(1, { kind = "desert" }), e(2, { revealed = false }), e(3, { revealed = false }) }), "West: desert, mostly unexplored")
end)
