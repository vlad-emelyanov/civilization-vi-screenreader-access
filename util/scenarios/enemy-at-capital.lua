-- Scenario: enemy-at-capital. STATUS: unverified (written offline)
-- Fixture: a game with a founded capital of player 0 (none of the committed fixtures has one; see README: early-city).
-- Then press: X (cursor to nearest foreign unit: "Barbarian Warrior ... spotted"), then W to attack; end the turn to
--   let it attack the city (combat line "Barbarian Warrior attacks ..." expected).
-- Notes: barbarian units are at war with everybody. Uses only GetUnits():Create (known to work for player 0).
local me = Players[0]
local capital = me:GetCities():GetCapitalCity()
if not capital then error("scenario enemy-at-capital: player 0 has no capital (load a fixture with a city)") end
local barb
for i = 0, 63 do
	local p = Players[i]
	if p and p:IsBarbarian() then barb = p; break end
end
if not barb then error("scenario enemy-at-capital: no barbarian player (barbarians disabled in this game)") end
local cx, cy = capital:GetX(), capital:GetY()
for dir = 0, 5 do
	local plot = Map.GetAdjacentPlot(cx, cy, dir)
	if plot and not plot:IsWater() and not plot:IsImpassable() and plot:GetUnitCount() == 0 and not plot:IsCity() then
		barb:GetUnits():Create(GameInfo.Units["UNIT_WARRIOR"].Index, plot:GetX(), plot:GetY())
		print("scenario enemy-at-capital: barbarian warrior at " .. plot:GetX() .. "," .. plot:GetY() .. ", capital at " .. cx .. "," .. cy)
		return
	end
end
error("scenario enemy-at-capital: no free land plot next to the capital")
