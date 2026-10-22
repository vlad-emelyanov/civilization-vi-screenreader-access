-- Scenario: builder-by-forest. STATUS: unverified (written offline)
-- Fixture: a game with a founded capital: early-city. Needs a forest within 3 tiles of the capital on an owned plot.
-- Then press: K / Control+K to select the builder, Tab -> actions menu (Harvest/Remove Forest, Build ...), move the
--   cursor onto the forest: the plot text should end with "Builder can build: ..." or "Builder can build nothing here".
-- Notes: spawns a UNIT_BUILDER (GetUnits():Create, known to work) on a free owned land plot adjacent to the forest.
local me = Players[0]
local capital = me:GetCities():GetCapitalCity()
if not capital then error("scenario builder-by-forest: player 0 has no capital (load a fixture with a city)") end
local forest = GameInfo.Features["FEATURE_FOREST"].Index
local cx, cy = capital:GetX(), capital:GetY()
for i = 0, Map.GetPlotCount() - 1 do
	local f = Map.GetPlotByIndex(i)
	if f:GetFeatureType() == forest and f:GetOwner() == 0 and Map.GetPlotDistance(cx, cy, f:GetX(), f:GetY()) <= 3 then
		for dir = 0, 5 do
			local p = Map.GetAdjacentPlot(f:GetX(), f:GetY(), dir)
			if p and p:GetOwner() == 0 and not p:IsWater() and not p:IsImpassable() and not p:IsCity() and p:GetUnitCount() == 0 then
				me:GetUnits():Create(GameInfo.Units["UNIT_BUILDER"].Index, p:GetX(), p:GetY())
				print("scenario builder-by-forest: builder at " .. p:GetX() .. "," .. p:GetY() .. ", forest at " .. f:GetX() .. "," .. f:GetY())
				return
			end
		end
	end
end
error("scenario builder-by-forest: no owned forest with a free owned neighbour within 3 tiles of the capital")
