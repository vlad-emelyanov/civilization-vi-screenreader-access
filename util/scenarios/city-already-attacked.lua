-- Scenario: city-already-attacked. STATUS: verified 2026-10-24
-- Fixture: bug-city-ranged-twice-reason (turn 208; Ostia has already made its ranged attack this turn; Mediolanum has walls and has not).
-- Spawns two Ottoman Musketmen 2 tiles from Ostia (its attack is used up: R must say it already attacked) and one 2 tiles
-- from Mediolanum (R, Enter attacks it; the second R must also say it already attacked, even if the target died).
local me = Players[0]
local ott = Players[4]
local function cityNamed(name)
	for _, c in me:GetCities():Members() do
		if Locale.Lookup(c:GetName()) == name then return c end
	end
	error("scenario city-already-attacked: no city " .. name)
end
local function spawnAt2(city, count)
	local cx, cy, n = city:GetX(), city:GetY(), 0
	for x = cx - 2, cx + 2 do
		for y = cy - 2, cy + 2 do
			local p = Map.GetPlot(x, y)
			if p and n < count and Map.GetPlotDistance(cx, cy, x, y) == 2 and not p:IsWater() and not p:IsImpassable() and p:GetUnitCount() == 0 and not p:IsCity() then
				ott:GetUnits():Create(GameInfo.Units["UNIT_MUSKETMAN"].Index, x, y)
				n = n + 1
				print("scenario city-already-attacked: Musketman at " .. x .. "," .. y .. " near " .. Locale.Lookup(city:GetName()))
			end
		end
	end
	if n < count then error("scenario city-already-attacked: no free land plot 2 tiles from " .. Locale.Lookup(city:GetName())) end
end
spawnAt2(cityNamed("Ostia"), 2)
spawnAt2(cityNamed("Mediolanum"), 1)
