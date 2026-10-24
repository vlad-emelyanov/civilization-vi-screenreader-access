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

-- Barbarian Clans mode
local function clanManager(index)
	return {
		GetTribeIndexAtLocation = function(_, x, y) if x == 4 and y == 4 then return index end return -1 end,
		GetTribeNameType = function() return 7 end, GetTribeType = function() return 2 end,
	}
end

test("clan phrase is nil without the mode", function()
	local plot = Map.GetPlot(4, 4)
	Game.GetBarbarianManager = nil
	eq(PlotDescription_GetClan(plot), nil)
	GameInfo.BarbarianTribes = { [2] = { Name = "Melee Open" } }
	GameInfo.BarbarianTribeNames = { [7] = { TribeDisplayName = "Badger Claw" } }
	eq(PlotDescription_GetClanPhrase(plot), nil)			-- no manager
	Game.GetBarbarianManager = function() return {} end
	eq(PlotDescription_GetClanPhrase(plot), nil)			-- manager without the tribe methods
	Game.GetBarbarianManager = function() return clanManager(-1) end
	eq(PlotDescription_GetClanPhrase(plot), nil)			-- no tribe on the plot
	eq(PlotDescription_CanTreatWithClan(plot), false)
end)

test("clan phrase names the clan and its type", function()
	Game.GetBarbarianManager = function() return clanManager(0) end
	local plot = Map.GetPlot(4, 4)
	eq(PlotDescription_GetClanPhrase(plot), "Badger Claw clan, Melee Open")
	local name, kind, tribe = PlotDescription_GetClan(plot)
	eq(name, "Badger Claw"); eq(kind, "Melee Open"); eq(tribe, 0)
	eq(PlotDescription_GetClanPhrase(Map.GetPlot(5, 5)), nil)
	GameInfo.BarbarianTribes = {}
	eq(PlotDescription_GetClanPhrase(plot), "Badger Claw clan")		-- the type row is missing
	GameInfo.BarbarianTribes = { [2] = { Name = "Melee Open" } }
end)

test("treat with the clan needs the plot in view; hidden plots say nothing", function()
	local plot = Map.GetPlot(4, 4)
	eq(PlotDescription_CanTreatWithClan(plot), true)
	world:set(4, 4, { fogged = true })
	eq(PlotDescription_CanTreatWithClan(plot), false)
	eq(PlotDescription_GetClanPhrase(plot), "Badger Claw clan, Melee Open")
	world:set(4, 4, { hidden = true })
	eq(PlotDescription_GetClanPhrase(plot), nil)
	world:set(4, 4, { hidden = false, fogged = false })
	Game.GetBarbarianManager = nil
end)
