-- LensText.lua: lens on/off speech, legends and the per-plot lens value
stub("engine")
local world = stub("world").new{ width = 20, height = 14 }
world:set(3, 3, { terrain = "water" })
world:set(5, 5, { river = true })
world:set(8, 8, { terrain = "water" })		-- coast for (8,9)
world:city(0, 12, 6, "Rome")
world:install()
include("SettleScan")
include("LensText")

InterfaceModeTypes = { VIEW_MODAL_LENS = 7, SELECTION = 1 }
local mode = 1
UI.GetInterfaceMode = function() return mode end
GameCapabilities = { HasCapability = function() return true end }
GameInfo.AppealHousingChanges = function()
	local rows = { { MinimumValue = 4, Description = "Breathtaking" }, { MinimumValue = 2, Description = "Charming" }, { MinimumValue = -10, Description = "Average" } }
	local i = 0
	return function() i = i + 1; return rows[i] end
end
local function withPlot(x, y, extra)
	local o = Map.GetPlot(x, y)
	for k, v in pairs(extra) do o[k] = v end
	return o
end

test("toggle on speaks the name, the legend and the hint", function()
	mode = 7
	local t = LensText_Toggled("LensSettler", true)
	contains(t, "Settler lens on")
	contains(t, "LOC_HUD_UNIT_PANEL_TOOLTIP_FRESH_WATER")
	contains(t, "Move the cursor")
	eq(LensText_ActiveLens(), "Settler")
end)

test("switching lens while in lens mode says on for the new one", function()
	contains(LensText_Toggled("LensAppeal", true), "Appeal lens on")
	eq(LensText_ActiveLens(), "Appeal")
end)

test("toggle off speaks off and forgets the lens", function()
	mode = 1
	eq(LensText_Toggled("LensAppeal", false), "Appeal lens off")
	eq(LensText_ActiveLens(), nil)
end)

test("a key the game ignored is silent", function()
	eq(LensText_Toggled("LensReligion", false), nil)
end)

test("lenses without per-tile values have no hint", function()
	mode = 7
	local t = LensText_Toggled("LensPolitical", true)
	contains(t, "Political lens on")
	istrue(not string.find(t, "Move the cursor"))
	mode = 1
	LensText_Toggled("LensPolitical", false)
end)

test("lens mode left by other means forgets the lens", function()
	mode = 7
	LensText_Toggled("LensContinent", true)
	mode = 1
	eq(LensText_ActiveLens(), nil)
end)

test("settler lens values", function()
	eq(LensText_PlotText("Settler", Map.GetPlot(5, 5), false), "can settle, fresh water")
	eq(LensText_PlotText("Settler", Map.GetPlot(8, 9), false), "can settle, coastal")
	eq(LensText_PlotText("Settler", Map.GetPlot(15, 12), false), "can settle, no water")
	contains(LensText_PlotText("Settler", Map.GetPlot(13, 6), false), "too close to Rome")
	eq(LensText_PlotText("Settler", Map.GetPlot(3, 3), false), nil)
	eq(LensText_PlotText("Settler", Map.GetPlot(5, 5), true), nil)		-- a settler is selected: the cursor text says it
end)

test("appeal lens value", function()
	local p = withPlot(6, 6, { GetAppeal = function() return 4 end })
	eq(LensText_PlotText("Appeal", p, false), "appeal: Breathtaking 4")
	p = withPlot(7, 6, { GetAppeal = function() return -3 end })
	eq(LensText_PlotText("Appeal", p, false), "appeal: Average -3")
	eq(LensText_PlotText("Appeal", Map.GetPlot(3, 3), false), nil)
end)

test("continent lens value", function()
	GameInfo.Continents = { [2] = { Description = "LOC_CONTINENT_ZEALANDIA" } }
	local p = withPlot(6, 7, { GetContinentType = function() return 2 end })
	eq(LensText_PlotText("Continent", p, false), "continent LOC_CONTINENT_ZEALANDIA")
end)

test("religion lens value", function()
	GameInfo.Religions = { [3] = { Pantheon = false } }
	local followers = 6
	Game.GetReligion = function() return { GetName = function() return "Buddhism" end } end
	Cities = { GetPlotPurchaseCity = function() return {
		GetReligion = function() return {
			GetMajorityReligion = function() return 3 end,
			GetReligionsInCity = function() return { { Religion = 3, Followers = followers } } end } end } end }
	local p = withPlot(9, 9, { GetOwner = function() return 0 end })
	eq(LensText_PlotText("Religion", p, false), "Buddhism, 6 followers")
	followers = 1
	eq(LensText_PlotText("Religion", p, false), "Buddhism, 1 follower")
	Cities.GetPlotPurchaseCity = function() return { GetReligion = function() return {
		GetMajorityReligion = function() return -1 end, GetReligionsInCity = function() return {} end } end } end
	eq(LensText_PlotText("Religion", p, false), "no religion")
end)

test("loyalty lens value (own cities only)", function()
	local identity = { GetLoyalty = function() return 72 end, GetLoyaltyPerTurn = function() return -3 end }
	local city = { GetOwner = function() return 0 end, GetName = function() return "Rome" end, GetCulturalIdentity = function() return identity end }
	Cities.GetPlotPurchaseCity = function() return city end
	local p = withPlot(10, 9, { GetOwner = function() return 0 end })
	eq(LensText_PlotText("Loyalty", p, false), "Rome loyalty 72, minus 3")
	city.GetOwner = function() return 1 end
	eq(LensText_PlotText("Loyalty", p, false), nil)
end)

test("prefix puts the lens value in front and leaves text alone with no lens", function()
	mode = 7
	LensText_Toggled("LensSettler", true)
	eq(LensText_Prefix("grass", Map.GetPlot(15, 12), false), "can settle, no water. grass")
	eq(LensText_Prefix("grass", Map.GetPlot(3, 3), false), "grass")
	mode = 1
	eq(LensText_Prefix("grass", Map.GetPlot(15, 12), false), "grass")
end)
