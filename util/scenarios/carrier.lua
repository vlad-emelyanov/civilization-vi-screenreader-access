-- Scenario: carrier. STATUS: verified 2026-10-24 on air-ready
-- Fixture: air-ready (turn 221, Rome; coastal Lugdunum 55,32 with an Aerodrome). Needs a coastal city of ours.
-- Puts an Aircraft Carrier on a water plot next to Lugdunum, makes sure a Fighter is in the city and grants TECH_COMBINED_ARMS.
-- Then press: select the Fighter, Tab (Deploy / Re-Base), Shift+R, move the cursor to the carrier, Enter. Then select the carrier.
-- Notes: Units:Create works for naval units on a water plot; the carrier does not need the tech or resource at Create.
local me = Players[0]
local tech = GameInfo.Technologies["TECH_COMBINED_ARMS"]
me:GetTechs():SetTech(tech.Index, true)
local city
for _, c in me:GetCities():Members() do
	if Locale.Lookup(c:GetName()) == "Lugdunum" then city = c end
end
if not city then error("scenario carrier: no city Lugdunum") end
local cx, cy = city:GetX(), city:GetY()
local water
for dir = 0, 5 do
	local p = Map.GetAdjacentPlot(cx, cy, dir)
	if p and p:IsWater() and not p:IsLake() and p:GetUnitCount() == 0 and not p:IsImpassable() then water = p break end
end
if not water then error("scenario carrier: no free water next to Lugdunum") end
me:GetUnits():Create(GameInfo.Units["UNIT_AIRCRAFT_CARRIER"].Index, water:GetX(), water:GetY())
print("scenario carrier: Aircraft Carrier at " .. water:GetX() .. "," .. water:GetY() .. " next to Lugdunum " .. cx .. "," .. cy)
local n = 0
for _, u in me:GetUnits():Members() do
	if GameInfo.Units[u:GetType()].UnitType == "UNIT_FIGHTER" and u:GetX() == cx and u:GetY() == cy then n = n + 1 end
end
if n == 0 then
	me:GetUnits():Create(GameInfo.Units["UNIT_FIGHTER"].Index, cx, cy)
	print("scenario carrier: Fighter spawned in Lugdunum")
else
	print("scenario carrier: " .. n .. " Fighter(s) already in Lugdunum")
end
