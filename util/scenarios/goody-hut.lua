-- Scenario: goody-hut. STATUS: verified 2026-10-24 (pt-modes-t82)
-- Fixture: pt-modes-t82 (any game with a land Scout/unit that has moves; the scout stands at 69,22).
-- Then press: select the scout, Shift+<direction> to the hut tile (printed), M/Enter -> "Arrived ..." then "Tribal village: <reward>".
-- Notes: puts IMPROVEMENT_GOODY_HUT on a free passable land plot adjacent to the first Scout (else any unit with moves) via ImprovementBuilder.SetImprovementType.
local me = Players[0]
local unit = nil
for _, u in me:GetUnits():Members() do
	if GameInfo.Units[u:GetType()].UnitType == "UNIT_SCOUT" then unit = u break end
end
if not unit then
	for _, u in me:GetUnits():Members() do
		if u:GetMovesRemaining() > 0 and GameInfo.Units[u:GetType()].Domain == "DOMAIN_LAND" then unit = u break end
	end
end
if not unit then error("scenario goody-hut: no land unit with moves") end
local hut = GameInfo.Improvements["IMPROVEMENT_GOODY_HUT"].Index
for dir = 0, 5 do
	local p = Map.GetAdjacentPlot(unit:GetX(), unit:GetY(), dir)
	if p and not p:IsWater() and not p:IsImpassable() and not p:IsCity() and p:GetUnitCount() == 0
		and p:GetImprovementType() == -1 and p:GetOwner() == -1 then
		ImprovementBuilder.SetImprovementType(p, hut, -1)
		print("scenario goody-hut: hut at " .. p:GetX() .. "," .. p:GetY() .. " next to unit " .. unit:GetID() .. " at " .. unit:GetX() .. "," .. unit:GetY() .. " direction " .. dir)
		return
	end
end
error("scenario goody-hut: no free unowned passable plot next to the unit")
