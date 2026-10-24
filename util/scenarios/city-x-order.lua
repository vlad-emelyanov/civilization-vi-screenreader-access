-- Scenario: city-x-order. STATUS: unverified
-- Fixture: bug-ranged-no-reason (Ostia, player 0 city). Any game with a city named Ostia, else the capital.
-- Then: select the city, R ("City ranged attack"; cursor on the adjacent Barbarian Musketman), X -> Barbarian Crossbowman
--   (2 tiles away), never the peaceful foreign Builder 4 tiles away.
-- Notes: spawns with GetUnits():Create (known to work). A Builder of a living major civ at peace stands 4 tiles from the city.
local me = Players[0]
local city
for _, c in me:GetCities():Members() do
	if city == nil or Locale.Lookup(c:GetName()) == "Ostia" then city = c end
end
if not city then error("scenario city-x-order: player 0 has no city") end
local barb, other
for i = 0, 63 do
	local p = Players[i]
	if p and p:IsBarbarian() then barb = p end
	if p and i ~= 0 and p:IsMajor() and p:IsAlive() and not p:IsBarbarian() and not me:GetDiplomacy():IsAtWarWith(i) and other == nil then other = p end
end
if not barb then error("scenario city-x-order: no barbarian player") end
if not other then error("scenario city-x-order: no peaceful major civ") end
local cx, cy = city:GetX(), city:GetY()
local function free(plot)
	return plot and not plot:IsWater() and not plot:IsImpassable() and plot:GetUnitCount() == 0 and not plot:IsCity()
end
local function spawn(owner, unitType, dist, name)
	for x = cx - dist, cx + dist do
		for y = cy - dist, cy + dist do
			local plot = Map.GetPlot(x, y)
			if free(plot) and Map.GetPlotDistance(cx, cy, x, y) == dist then
				owner:GetUnits():Create(GameInfo.Units[unitType].Index, x, y)
				print("scenario city-x-order: " .. name .. " at " .. x .. "," .. y .. ", city at " .. cx .. "," .. cy)
				return
			end
		end
	end
	error("scenario city-x-order: no free land plot at distance " .. dist)
end
spawn(barb, "UNIT_MUSKETMAN", 1, "Barbarian Musketman")
spawn(barb, "UNIT_CROSSBOWMAN", 2, "Barbarian Crossbowman")
spawn(other, "UNIT_BUILDER", 4, "peaceful Builder")
