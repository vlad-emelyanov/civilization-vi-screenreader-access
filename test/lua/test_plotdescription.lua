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
local clanModeOn = true
GameConfiguration = { GetValue = function(key) return key == "GAMEMODE_BARBARIAN_CLANS" and clanModeOn or nil end }
PlotDescription_ResetClanMode()
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

test("mode off: tribe data in the base game gives no clan words", function()
	Game.GetBarbarianManager = function() return clanManager(0) end
	GameInfo.BarbarianTribes = { [2] = { Name = "Melee Open" } }
	GameInfo.BarbarianTribeNames = { [7] = { TribeDisplayName = "Badger Claw" } }
	clanModeOn = false
	PlotDescription_ResetClanMode()
	local plot = Map.GetPlot(4, 4)
	eq(PlotDescription_GetClan(plot), nil)
	eq(PlotDescription_GetClanPhrase(plot), nil)
	eq(PlotDescription_CanTreatWithClan(plot), false)
	clanModeOn = true
	PlotDescription_ResetClanMode()
	eq(PlotDescription_GetClanPhrase(plot), "Badger Claw clan, Melee Open")
	Game.GetBarbarianManager = nil
end)

test("danger refusal names the enemy", function()
	eq(PlotDescription_DangerReason("Danger", "Barbarian Galley", "1 tile east"), "Danger, Barbarian Galley 1 tile east")
	eq(PlotDescription_DangerReason("Danger", nil, nil), "Danger")
	eq(PlotDescription_DangerReason("no moves left", "Barbarian Galley", "1 tile east"), "no moves left")
	eq(PlotDescription_DangerReason("Danger", "Barbarian Galley", nil), "Danger, Barbarian Galley")
end)

test("military formation names", function()
	MilitaryFormationTypes = { STANDARD_FORMATION = 0, CORPS_FORMATION = 1, ARMY_FORMATION = 2 }
	GameInfo.Units = { [5] = { Domain = "DOMAIN_LAND" }, [6] = { Domain = "DOMAIN_SEA" } }
	local function u(t, f) return { GetMilitaryFormation = function() return f end, GetType = function() return t end } end
	eq(PlotDescription_FormationName(u(5, 0), "Musketman"), "Musketman")
	eq(PlotDescription_FormationName(u(5, 1), "Musketman"), "Musketman corps")
	eq(PlotDescription_FormationName(u(5, 2), "Musketman"), "Musketman army")
	eq(PlotDescription_FormationName(u(6, 1), "Frigate"), "Frigate fleet")
	eq(PlotDescription_FormationName(u(6, 2), "Frigate"), "Frigate armada")
	eq(PlotDescription_FormationName(u(5, 1), "Musketman Corps"), "Musketman Corps")
end)

test("embarked land unit", function()
	GameInfo.Units = { [5] = { Domain = "DOMAIN_LAND" }, [6] = { Domain = "DOMAIN_SEA" } }
	world:set(3, 3, { terrain = "water", lake = true })
	local function u(t, x, y) return { GetType = function() return t end, GetX = function() return x end, GetY = function() return y end } end
	eq(PlotDescription_UnitStateText(u(5, 3, 3)), "embarked")
	eq(PlotDescription_UnitStateText(u(6, 3, 3)), nil)
	eq(PlotDescription_UnitStateText(u(5, 4, 4)), nil)
	local e = u(5, 4, 4); e.IsEmbarked = function() return true end
	eq(PlotDescription_UnitStateText(e), "embarked")
end)
