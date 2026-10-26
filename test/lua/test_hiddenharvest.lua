-- ScreenReader.lua: placement texts must not name a resource the player has not discovered
local Strings = stub("engine")
local world = stub("world").new{ width = 6, height = 6 }
world:install()
include("ScreenReader")
Strings.LOC_DISTRICT_ZONE_WILL_HARVEST_RESOURCE = "Will harvest the {1_Resource} on this tile."
Strings.LOC_DISTRICT_ZONE_WILL_REMOVE_FEATURE = "Will remove the {1_Feature} on this tile."

local visible = true
Players[0].GetResources = function() return { IsResourceVisible = function() return visible end } end
world:set(1, 1, { resource = "Oil", rclass = "strategic" })
local plot = Map.GetPlot(1, 1)
local text = "Place the district here?[NEWLINE][NEWLINE]Will remove the Woods on this tile.[NEWLINE]Will harvest the Oil on this tile."

test("a visible resource keeps its sentence", function()
	visible = true
	eq(SRPlotResourceHidden(plot), false)
	eq(SRStripHiddenHarvest(plot, text), text)
end)

test("an undiscovered resource: its sentence is removed, the others stay", function()
	visible = false
	eq(SRPlotResourceHidden(plot), true)
	eq(SRHiddenHarvestSentence(plot), "Will harvest the Oil on this tile.")
	eq(SRStripHiddenHarvest(plot, text), "Place the district here?[NEWLINE][NEWLINE]Will remove the Woods on this tile.")
	eq(SRStripHiddenHarvest(plot, "Will harvest the Oil on this tile."), "")
end)

test("a plot without a resource is untouched", function()
	visible = false
	local other = Map.GetPlot(2, 2)
	eq(SRPlotResourceHidden(other), false)
	eq(SRStripHiddenHarvest(other, text), text)
end)
