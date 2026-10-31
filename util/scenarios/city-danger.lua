-- Scenario: city-danger. STATUS: unverified (written blind, the war API is a guess)
-- Fixture: early-t60 (capital Rome at 60,33). Any game with a capital of player 0 and a second living major civilization works.
-- Then: HubEnemies.SpeakCityDanger(false) (or the next turn start) -> "<city> in danger: 3 units of <civ> within 3 tiles, city strength N, ...
--   Control+I for the city". A second call says nothing; one more unit placed afterwards speaks again.
-- Notes: makes the first other major civilization meet us and declares war (tries the known diplomacy calls with pcall and prints which one
--   worked; the verifier fixes this part if none does), then creates 3 Swordsmen of it 2-3 tiles from the capital (GetUnits():Create works).
local me = Players[0]
local capital = me:GetCities():GetCapitalCity()
if not capital then error("scenario city-danger: player 0 has no capital (load a fixture with a city)") end
local other
for _, id in ipairs(PlayerManager.GetAliveMajorIDs()) do
	if id ~= 0 then other = id; break end
end
if not other then error("scenario city-danger: no other major civilization") end
pcall(function() me:GetDiplomacy():SetHasMet(other) end)
pcall(function() Players[other]:GetDiplomacy():SetHasMet(0) end)
local tried = {
	function() Players[other]:GetDiplomacy():DeclareWar(0) end,
	function() me:GetDiplomacy():DeclareWar(other) end,
	function() DiplomacyManager.DeclareWar(other, 0) end,
	function() Players[other]:GetDiplomacy():SetAtWar(0) end,
}
for i, fn in ipairs(tried) do
	local ok = pcall(fn)
	if ok and me:GetDiplomacy():IsAtWarWith(other) then print("scenario city-danger: war declared with candidate " .. i); break end
end
if not me:GetDiplomacy():IsAtWarWith(other) then error("scenario city-danger: could not declare war with player " .. other .. " (fix the candidates above)") end
local cx, cy = capital:GetX(), capital:GetY()
local made = 0
for dy = -3, 3 do
	for dx = -3, 3 do
		local plot = Map.GetPlot(cx + dx, cy + dy)
		if made < 3 and plot and not plot:IsWater() and not plot:IsImpassable() and plot:GetUnitCount() == 0 and not plot:IsCity()
				and Map.GetPlotDistance(cx, cy, plot:GetX(), plot:GetY()) >= 2 and Map.GetPlotDistance(cx, cy, plot:GetX(), plot:GetY()) <= 3 then
			Players[other]:GetUnits():Create(GameInfo.Units["UNIT_SWORDSMAN"].Index, plot:GetX(), plot:GetY())
			made = made + 1
		end
	end
end
print("scenario city-danger: player " .. other .. " at war with us, " .. made .. " Swordsmen near " .. cx .. "," .. cy)
