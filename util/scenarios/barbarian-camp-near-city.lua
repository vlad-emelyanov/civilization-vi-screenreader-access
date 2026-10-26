-- Scenario: barbarian-camp-near-city. STATUS: unverified (written blind 2026-10-26)
-- Fixture: early-t60 (capital Rome at 60,33; barbarians on). Any game with a capital of player 0 and a barbarian player works.
-- Then: a barbarian camp (IMPROVEMENT_BARBARIAN_CAMP, owner barbarians) with a barbarian Warrior on it 2 tiles from the capital (in view,
--   so the hub remembers it with its guard) and a second Warrior + Slinger of ours in the capital (an attack party needs two soldiers).
--   J, Tab to Points of interest: "Barbarian Camp, 2 tiles <dir> of <city>, guarded by Warrior"; Space: "Destroying it gives ..."; M: "Attack party, send 2 units: ...".
-- Notes: ImprovementBuilder.SetImprovementType is the call goody-hut uses (verified); the camp's owner argument is the barbarian player id.
--   The camp is placed 2 tiles away (not the engine's 4-tile rule) so that it is in view without moving a unit.
local me = Players[0]
local capital = me:GetCities():GetCapitalCity()
if not capital then error("scenario barbarian-camp-near-city: player 0 has no capital (load a fixture with a city)") end
local barb
for i = 0, 63 do
	local p = Players[i]
	if p and p:IsBarbarian() then barb = p; break end
end
if not barb then error("scenario barbarian-camp-near-city: no barbarian player (barbarians disabled in this game)") end
local camp = GameInfo.Improvements["IMPROVEMENT_BARBARIAN_CAMP"]
local warrior = GameInfo.Units["UNIT_WARRIOR"]
if not camp or not warrior then error("scenario barbarian-camp-near-city: camp improvement or warrior unit missing") end
local cx, cy = capital:GetX(), capital:GetY()
local target
for dy = -2, 2 do
	for dx = -2, 2 do
		local plot = Map.GetPlot(cx + dx, cy + dy)
		if not target and plot and Map.GetPlotDistance(cx, cy, plot:GetX(), plot:GetY()) == 2 and not plot:IsWater() and not plot:IsImpassable()
			and plot:GetUnitCount() == 0 and not plot:IsCity() and plot:GetImprovementType() == -1 then
			target = plot
		end
	end
end
if not target then error("scenario barbarian-camp-near-city: no free land plot 2 tiles from the capital") end
ImprovementBuilder.SetImprovementType(target, camp.Index, barb:GetID())
barb:GetUnits():Create(warrior.Index, target:GetX(), target:GetY())
me:GetUnits():Create(warrior.Index, cx, cy)
local slinger = GameInfo.Units["UNIT_SLINGER"]
if slinger then me:GetUnits():Create(slinger.Index, cx, cy) end
print("scenario barbarian-camp-near-city: camp + barbarian Warrior at " .. target:GetX() .. "," .. target:GetY() .. ", capital at " .. cx .. "," .. cy .. ", own Warrior" .. (slinger and " and Slinger" or "") .. " in the capital")
