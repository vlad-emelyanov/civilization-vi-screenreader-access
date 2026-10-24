-- Scenario: city-capture. VERIFIED 2026-10-23 on medieval-t100 (fixture bug-city-capture is the result).
-- Creates a Free Cities city (Players[62]:GetCities():Create, no defenders, at war with everyone) 4 tiles from our capital at 57,27 and a
-- Man-At-Arms of ours next to it. Keys: select the unit, W, then `.` (cursor to selection), Shift+Down, Shift+Left, Enter captures the city;
-- the "Raze or Keep City" notification opens the RazeCity popup (Control+N, Enter on it). See test/regress/city-capture.txt.
local free = Players[62]
if not free then error("scenario city-capture: no Free Cities player (62) in this game") end
local capital = Players[0]:GetCities():GetCapitalCity()
if not capital then error("scenario city-capture: player 0 has no capital") end
local cx, cy = capital:GetX(), capital:GetY()
local target
for dx = -6, 6 do
	for dy = -6, 6 do
		local x, y = cx + dx, cy + dy
		local plot = Map.GetPlot(x, y)
		if not target and plot and Map.GetPlotDistance(cx, cy, x, y) >= 4 and not plot:IsWater() and not plot:IsImpassable()
			and plot:GetOwner() == -1 and plot:GetUnitCount() == 0 and free:GetCities():IsValidFoundLocation(x, y) then
			target = plot
		end
	end
end
if not target then error("scenario city-capture: no valid free land plot 4+ tiles from the capital") end
local city = free:GetCities():Create(target:GetX(), target:GetY())
print("scenario city-capture: city at " .. target:GetX() .. "," .. target:GetY() .. " " .. tostring(city))
for dir = 0, 5 do
	local plot = Map.GetAdjacentPlot(target:GetX(), target:GetY(), dir)
	if plot and not plot:IsWater() and not plot:IsImpassable() and not plot:IsCity() and plot:GetUnitCount() == 0 then
		Players[0]:GetUnits():Create(GameInfo.Units["UNIT_MAN_AT_ARMS"].Index, plot:GetX(), plot:GetY())
		print("scenario city-capture: Man-At-Arms at " .. plot:GetX() .. "," .. plot:GetY())
		break
	end
end
