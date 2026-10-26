-- Scenario: barbarian-builder. STATUS: unverified (written blind 2026-10-26)
-- Fixture: early-t60 (capital Rome at 60,33; barbarians on). Any game with a capital of player 0 and a barbarian player works.
-- Then press: J, Control+Tab (the last category) -> "Civilians to capture, ... Barbarian Builder, <place>"; M -> the military units that can capture it.
-- Notes: spawns a barbarian Builder on a free passable land plot 2 to 3 tiles from the capital (inside the city's view, so it is visible).
--   Uses only GetUnits():Create (known to work, see enemy-at-capital).
local me = Players[0]
local capital = me:GetCities():GetCapitalCity()
if not capital then error("scenario barbarian-builder: player 0 has no capital (load a fixture with a city)") end
local barb
for i = 0, 63 do
	local p = Players[i]
	if p and p:IsBarbarian() then barb = p; break end
end
if not barb then error("scenario barbarian-builder: no barbarian player (barbarians disabled in this game)") end
local cx, cy = capital:GetX(), capital:GetY()
for dy = -3, 3 do
	for dx = -3, 3 do
		local plot = Map.GetPlot(cx + dx, cy + dy)
		if plot and Map.GetPlotDistance(cx, cy, plot:GetX(), plot:GetY()) >= 2 and not plot:IsWater() and not plot:IsImpassable()
			and plot:GetUnitCount() == 0 and not plot:IsCity() and plot:GetOwner() ~= -1 then
			barb:GetUnits():Create(GameInfo.Units["UNIT_BUILDER"].Index, plot:GetX(), plot:GetY())
			print("scenario barbarian-builder: barbarian builder at " .. plot:GetX() .. "," .. plot:GetY() .. ", capital at " .. cx .. "," .. cy)
			return
		end
	end
end
error("scenario barbarian-builder: no free land plot 2-3 tiles from the capital")
