-- Scenario: excavate. STATUS: verified 2026-10-31 (pt-modern-t212, also fixture excavate-ready which already has the archaeologist on its site)
-- Fixture: pt-modern-t212 (Natural History civic known, Antiquity Sites at 49,25 / 49,27 inside our borders; fixture excavate-ready = this + a
--   Gathering-Storm Archaeologist standing on 49,27).
-- Gives player 0 an Archaeologist on the first revealed RESOURCE_ANTIQUITY_SITE plot we own (idempotent: reuses one that stands on a site).
-- Then (keys): the unit is selected by `civctl lua InGameAccess` (UI.SelectUnit), Tab (unit actions), Down to "Excavate Artifact", Enter ->
--   "Excavate Artifact" and, ~1 s later, "Notification: Artifact Extracted". The engine opens NO popup by itself (the site's artifact is
--   resolved when the turn ends), but the unit stays GetNextExtractingArchaeologist(), so the real popup is opened with the game's own event:
--     civctl lua InGame 'LuaEvents.NotificationPanel_OpenArtifactPanel()'      -> context FakePopups/ChooseArtifact
--   "Your Archaeologist X has discovered an ancient battlefield littered with items from A and B ... CHOOSE which nation's artifact": two buttons
--   (Button1 = acting player, Button2 = target player); their handlers send the game's own PlayerOperations.CHOOSE_ARTIFACT_PLAYER.
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
