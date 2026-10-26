-- Scenario: settler-away. STATUS: unverified
-- Fixture: early-t60 (a Warrior of ours exists). Spawns a Settler on a free owned land plot 2-3 tiles from the Warrior.
-- Then press: select the settler (UI.SelectUnit), J, Tab -> "Your units"; M -> "Send an escort to Settler, N options".
-- Notes: same GetUnits():Create call as builder-by-forest; Map.GetPlotDistance / GetPlotByIndex are known to work.
local me = Players[0]
local warrior
for _, u in me:GetUnits():Members() do
	if GameInfo.Units[u:GetType()].UnitType == "UNIT_WARRIOR" then warrior = u break end
end
if not warrior then error("scenario settler-away: no Warrior of ours (load early-t60)") end
local wx, wy = warrior:GetX(), warrior:GetY()
for i = 0, Map.GetPlotCount() - 1 do
	local p = Map.GetPlotByIndex(i)
	local d = Map.GetPlotDistance(wx, wy, p:GetX(), p:GetY())
	if d >= 2 and d <= 3 and p:GetOwner() == 0 and not p:IsWater() and not p:IsImpassable() and not p:IsCity() and p:GetUnitCount() == 0 then
		me:GetUnits():Create(GameInfo.Units["UNIT_SETTLER"].Index, p:GetX(), p:GetY())
		print("scenario settler-away: settler at " .. p:GetX() .. "," .. p:GetY() .. ", warrior at " .. wx .. "," .. wy)
		return
	end
end
error("scenario settler-away: no free owned land plot 2-3 tiles from the Warrior")
