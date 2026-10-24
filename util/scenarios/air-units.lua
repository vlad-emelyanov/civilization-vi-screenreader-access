-- Scenario: air-units. STATUS: see test/regress/air-units.txt
-- Fixture: pt-late-t221 (turn 221, Rome; complete Aerodrome in Lugdunum 55,32; TECH_ADVANCED_FLIGHT known; at war with the Ottomans, player 4).
-- Spawns for player 0 two Fighters and a Bomber in Lugdunum, one Fighter in Aquileia (rebase target), and two Ottoman
-- Tanks 3-4 tiles from Lugdunum (air attack targets). Print lines name the places.
-- Notes: GetUnits():Create works for air units in a city with an Aerodrome; strategic resource needs are not checked by Create.
local me = Players[0]
local ott = Players[4]
if not me:GetDiplomacy():IsAtWarWith(4) then error("scenario air-units: not at war with player 4") end
local function cityNamed(name)
	for _, c in me:GetCities():Members() do
		if Locale.Lookup(c:GetName()) == name then return c end
	end
	error("scenario air-units: no city " .. name)
end
local lug, aq = cityNamed("Lugdunum"), cityNamed("Aquileia")
local function spawnIn(city, unitType, n)
	for i = 1, n do
		me:GetUnits():Create(GameInfo.Units[unitType].Index, city:GetX(), city:GetY())
	end
	print("scenario air-units: " .. n .. " x " .. unitType .. " in " .. Locale.Lookup(city:GetName()))
end
spawnIn(lug, "UNIT_FIGHTER", 2)
spawnIn(lug, "UNIT_BOMBER", 1)
spawnIn(aq, "UNIT_FIGHTER", 1)
local cx, cy, n = lug:GetX(), lug:GetY(), 0
for d = 3, 4 do
	for x = cx - d, cx + d do
		for y = cy - d, cy + d do
			local p = Map.GetPlot(x, y)
			if p and n < 2 and Map.GetPlotDistance(cx, cy, x, y) == d and not p:IsWater() and not p:IsImpassable() and p:GetUnitCount() == 0 and not p:IsCity() and p:GetOwner() ~= 62 then
				ott:GetUnits():Create(GameInfo.Units["UNIT_MODERN_ARMOR"].Index, x, y)
				n = n + 1
				print("scenario air-units: Ottoman Modern Armor at " .. x .. "," .. y .. " (distance " .. d .. " from Lugdunum)")
			end
		end
	end
end
if n < 2 then error("scenario air-units: no free land plots for the enemy") end
