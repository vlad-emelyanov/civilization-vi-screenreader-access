-- PlotDescription.lua: direction and distance words
stub("engine")
local world = stub("world").new{ width = 20, height = 12 }
world:install()
include("PlotDescription")

local function dir(x1, y1, x2, y2) return PlotDescription_GetDirectionWord(x1, y1, x2, y2) end

test("same plot has no direction", function()
	eq(dir(3, 3, 3, 3), nil)
end)

test("east and west", function()
	eq(dir(5, 4, 8, 4), "east")
	eq(dir(5, 4, 2, 4), "west")
end)

test("neighbours on odd/even rows", function()
	-- (5,4) even row: its north-east neighbour is (5,5), north-west (4,5), south-east (5,3), south-west (4,3)
	eq(dir(5, 4, 5, 5), "north-east")
	eq(dir(5, 4, 4, 5), "north-west")
	eq(dir(5, 4, 5, 3), "south-east")
	eq(dir(5, 4, 4, 3), "south-west")
	-- (5,5) odd row: north-east is (6,6), north-west (5,6), south-east (6,4), south-west (5,4)
	eq(dir(5, 5, 6, 6), "north-east")
	eq(dir(5, 5, 5, 6), "north-west")
	eq(dir(5, 5, 6, 4), "south-east")
	eq(dir(5, 5, 5, 4), "south-west")
end)

test("far targets pick the nearest octant", function()
	eq(dir(5, 4, 5, 10), "north")
	eq(dir(5, 10, 8, 4), "south-east")
	eq(dir(10, 5, 17, 5), "east")
end)

test("wrapping maps take the shorter way round", function()
	world.wrap = true
	eq(dir(1, 4, 18, 4), "west")
	eq(dir(18, 4, 1, 4), "east")
	world.wrap = false
	eq(dir(1, 4, 18, 4), "east")
end)

test("relative words: distance and plural", function()
	local from = Map.GetPlot(5, 4)
	eq(PlotDescription_GetRelative(from, Map.GetPlot(5, 4)), nil)
	eq(PlotDescription_GetRelative(from, Map.GetPlot(6, 4)), "1 tile east")
	eq(PlotDescription_GetRelative(from, Map.GetPlot(8, 4)), "3 tiles east")
	eq(PlotDescription_GetRelative(from, Map.GetPlot(4, 4)), "1 tile west")
	eq(PlotDescription_GetRelative(from, nil), nil)
end)
