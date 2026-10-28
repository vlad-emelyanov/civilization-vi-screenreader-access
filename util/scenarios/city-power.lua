-- Scenario: city-power. STATUS: unverified (written blind)
-- Fixture: pt-modern-t176 (Rome (51,32) is the capital, has a Campus district + University). Gives Rome a Research Lab (RequiredPower 3,
--   Expansion2_Buildings.xml) so the city needs power it does not get -> "Underpowered". Then: CapitalCity, Control+I, Down x4 ->
--   "Power 0 of 3 needed, underpowered" (right after Loyalty); Space -> status description, "Needed by: ..." and the advice.
-- Notes (verifier checks): CreateIncompleteBuilding(buildingIndex, plotIndex, 100) in GameCore_Tuner (does it complete the building?);
--   Districts:GetDistrict(campusIndex) / :GetPlot(); the text of the entry (RequiredPower may need a turn to be recomputed: try a
--   city report reopen). Never save the game over a fixture afterwards.
local me = Players[0]
local capital = me:GetCities():GetCapitalCity()
if not capital then error("scenario city-power: player 0 has no capital") end
local building = GameInfo.Buildings["BUILDING_RESEARCH_LAB"]
if not building then error("scenario city-power: BUILDING_RESEARCH_LAB missing (Gathering Storm)") end
if capital:GetBuildings():HasBuilding(building.Index) then print("scenario city-power: Research Lab already there"); return end
local campus = GameInfo.Districts["DISTRICT_CAMPUS"]
local district = capital:GetDistricts():GetDistrict(campus.Index)
if not district then error("scenario city-power: the capital has no Campus") end
local plot = Map.GetPlot(district:GetX(), district:GetY())
capital:GetBuildQueue():CreateIncompleteBuilding(building.Index, plot:GetIndex(), 100)
print("scenario city-power: Research Lab placed in " .. Locale.Lookup(capital:GetName()) .. ", has it: " .. tostring(capital:GetBuildings():HasBuilding(building.Index)))
