-- Scenario: excavate. STATUS: verified 2026-10-31 (pt-modern-t212). Prefer the fixture excavate-ready: it holds a REAL archaeologist.
-- WARNING: a unit made here by GetUnits():Create has NO home city/museum (GetArchaeology():GetHomeCityID() == -1). Excavate Artifact then raises only
--   "Artifact Extracted"; the artifact is dropped (no "Choose Artifact" notification or end-turn blocker, no popup, no great work). A real
--   Archaeologist is bought in a city with an Archaeological Museum (Antium in pt-modern-t212; InGame state: CityManager.RequestCommand(city,
--   CityCommandTypes.PURCHASE, {PARAM_UNIT_TYPE = hash, PARAM_MILITARY_FORMATION_TYPE = STANDARD_MILITARY_FORMATION, PARAM_YIELD_TYPE = GOLD}),
--   one turn later UnitManager.RequestOperation(unit, MOVE_TO, {X, Y}) to the site). This script only serves to test the "no museum" case.
-- Fixture: pt-modern-t212 (Natural History civic known, Antiquity Sites at 49,25 / 49,27 inside our borders).
-- Gives player 0 an Archaeologist on the first revealed RESOURCE_ANTIQUITY_SITE plot we own (idempotent: reuses one that stands on a site).
-- Then (keys): select the unit (`civctl lua InGameAccess` UI.SelectUnit), Tab, Down to "Excavate Artifact", Enter -> "Excavate Artifact"; with a REAL unit
--   "Notification: Choose Artifact, Artifact Extracted" follow at once, and the popup (context FakePopups/ChooseArtifact) opens from Enter on that notification in
--   the Control+N list or on End Turn Enter (blocker ENDTURN_BLOCKING_ARTIFACT, after the civic/production blockers): two buttons (Button1 = acting player,
--   Button2 = target player), their handlers send PlayerOperations.CHOOSE_ARTIFACT_PLAYER, then the great work showcase.
-- Notes: GetUnits():Create only on a plot we own (nil on foreign land). Never save the game over a fixture afterwards. A stray Enter ends the turn.
local me = Players[0]
local siteType = GameInfo.Resources["RESOURCE_ANTIQUITY_SITE"].Index
local arch = GameInfo.Units["UNIT_ARCHAEOLOGIST"]
if not arch then error("scenario excavate: UNIT_ARCHAEOLOGIST not found") end
local sites = {}
for i = 0, Map.GetPlotCount() - 1 do
	local plot = Map.GetPlotByIndex(i)
	if plot:GetResourceType() == siteType and plot:GetOwner() == 0 and PlayersVisibility[0]:IsRevealed(plot:GetX(), plot:GetY()) then
		table.insert(sites, plot)
	end
end
if #sites == 0 then error("scenario excavate: no revealed Antiquity Site inside our borders (load pt-modern-t212)") end
for _, unit in me:GetUnits():Members() do
	if unit:GetType() == arch.Index then
		for _, plot in ipairs(sites) do
			if plot:GetX() == unit:GetX() and plot:GetY() == unit:GetY() then print("scenario excavate: an archaeologist already stands on a site"); return end
		end
	end
end
local plot = sites[1]
local unit = me:GetUnits():Create(arch.Index, plot:GetX(), plot:GetY())
print("scenario excavate: Archaeologist " .. tostring(unit and unit:GetID()) .. " on the site at " .. plot:GetX() .. "," .. plot:GetY())
