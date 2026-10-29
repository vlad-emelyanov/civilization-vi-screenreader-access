-- Cursor tile speech order (strategic/luxury resource, position, description) and the foreign city in the position text
stub("engine")
local world = stub("world").new{ width = 20, height = 12 }
world:install()
include("PlotDescription")
include("ScreenReader")
include("HubCore")
include("HubAnnounce")

-- the stub's GameInfo.Yields is a table; GetShort iterates it as a function
GameInfo.Yields = setmetatable({}, { __call = function()
	local rows, i = { { Index = 0, Name = "Food" }, { Index = 1, Name = "Production" } }, 0
	return function() i = i + 1; return rows[i] end
end })
Game.GetLocalPlayer = function() return 0 end
GameInfo.Terrains = setmetatable({}, { __index = function() return { TerrainType = "TERRAIN_GRASS", Name = "Grassland" } end })
-- the stub plot lacks a few methods GetShort asks for
local getPlot = Map.GetPlot
Map.GetPlot = function(x, y)
	local plot = getPlot(x, y)
	if plot ~= nil and plot.GetWonderType == nil then
		plot.GetWonderType = function() return -1 end
		plot.IsRoute = function() return false end
	end
	return plot
end

test("strategic resource leads, then the position, then the terrain", function()
	world:set(5, 5, { resource = "Iron", rclass = "strategic" })
	local plot = Map.GetPlot(5, 5)
	local text = PlotDescription_GetShort(plot, { leadResource = true, position = "3 tiles north-east" })
	istrue(text:find("^Iron, 3 tiles north%-east, Grassland"), text)
	istrue(text:find("2 Food 1 Production$"), text)
	istrue(not text:find("Grassland, Iron"), text)
end)

test("luxury resource leads too", function()
	world:set(6, 5, { resource = "Silk", rclass = "luxury" })
	local text = PlotDescription_GetShort(Map.GetPlot(6, 5), { leadResource = true, position = "1 tile west" })
	istrue(text:find("^Silk, 1 tile west, Grassland"), text)
end)

test("bonus resource stays after the terrain, the position still comes first", function()
	world:set(7, 5, { resource = "Wheat", rclass = "bonus" })
	local text = PlotDescription_GetShort(Map.GetPlot(7, 5), { leadResource = true, position = "2 tiles east" })
	istrue(text:find("^2 tiles east, Grassland, Wheat"), text)
end)

test("without the options the order is unchanged", function()
	local text = PlotDescription_GetShort(Map.GetPlot(5, 5), {})
	istrue(text:find("^Grassland, Iron"), text)
end)

test("a plot without resource: position then terrain", function()
	local text = PlotDescription_GetShort(Map.GetPlot(9, 9), { leadResource = true, position = "4 tiles south" })
	istrue(text:find("^4 tiles south, Grassland"), text)
end)

test("position wording: own city only", function()
	local plot = Map.GetPlot(8, 4)
	local own = { name = "Aquileia", x = 5, y = 4, distance = 3 }
	eq(HubAnnounce.PositionWording(plot, own, nil), "3 tiles east of Aquileia")
	own.distance = 0; own.x, own.y = 8, 4
	eq(HubAnnounce.PositionWording(plot, own, nil), "in Aquileia")
end)

test("position wording: a closer foreign city comes first with its owner", function()
	local plot = Map.GetPlot(8, 4)
	local own = { name = "Aquileia", x = 4, y = 4, distance = 4 }
	local foreign = { name = "Seoul", x = 9, y = 4, distance = 1, civ = "Korea" }
	eq(HubAnnounce.PositionWording(plot, own, foreign), "1 tile west of Seoul (Korea), 4 tiles east of Aquileia")
end)

test("position wording: a foreign city that is not closer is left out", function()
	local plot = Map.GetPlot(8, 4)
	local own = { name = "Aquileia", x = 6, y = 4, distance = 2 }
	eq(HubAnnounce.PositionWording(plot, own, { name = "Seoul", x = 10, y = 4, distance = 2, civ = "Korea" }), "2 tiles east of Aquileia")
end)

test("position wording: inside a foreign city, city-state name not doubled, no own city", function()
	local plot = Map.GetPlot(8, 4)
	eq(HubAnnounce.PositionWording(plot, { name = "Aquileia", x = 3, y = 4, distance = 5 }, { name = "Seoul", x = 8, y = 4, distance = 0, civ = "Korea" }), "in Seoul (Korea)")
	eq(HubAnnounce.PositionWording(plot, nil, { name = "Kabul", x = 10, y = 4, distance = 2, civ = "Kabul" }), "2 tiles west of Kabul")
end)
