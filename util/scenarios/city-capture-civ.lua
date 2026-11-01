-- Scenario: city-capture-civ. STATUS: verified 2026-11-01 on pt-nobarbs-t166 (Rome; Konya, Ottoman pop 5 at 71,28).
-- Fixture: pt-nobarbs-t166 or any game with a met major civ that owns a small city. Declares war on that civ (DeclareWarOn FORMAL_WAR),
-- puts an Infantry on a land plot next to the city and takes the city center's garrison and outer (walls) hit points to zero.
-- Then press (real path): select the Infantry (UI.SelectUnit from InGameAccess), W, KeyNavCursorToSelection, move the cell cursor onto the city, Enter.
-- Notes: the city is captured by the mod's attack keys, not by the tuner. A unit can be Create()d on an enemy-owned plot at war.
local me = Players[0]
local cap = me:GetCities():GetCapitalCity()
local best, bestPop, bestDist
for id = 1, 61 do
	local p = Players[id]
	if p and p:IsAlive() and p:IsMajor() and me:GetDiplomacy():HasMet(id) then
		for _, c in p:GetCities():Members() do
			local pop = c:GetPopulation()
			local dist = Map.GetPlotDistance(cap:GetX(), cap:GetY(), c:GetX(), c:GetY())
			if dist <= 16 and (not best or pop < bestPop or (pop == bestPop and dist < bestDist)) then best, bestPop, bestDist = c, pop, dist end
		end
	end
end
if not best then error("scenario city-capture-civ: no met major civ city within 16 tiles") end
local owner = best:GetOwner()
me:GetDiplomacy():DeclareWarOn(owner, WarTypes.FORMAL_WAR, true)
local cx, cy = best:GetX(), best:GetY()
local spot
for dir = 0, 5 do
	local plot = Map.GetAdjacentPlot(cx, cy, dir)
	if not spot and plot and not plot:IsWater() and not plot:IsImpassable() and not plot:IsMountain() and plot:GetUnitCount() == 0 then spot = plot end
end
if not spot then error("scenario city-capture-civ: no free land plot next to the city") end
local u = me:GetUnits():Create(GameInfo.Units["UNIT_INFANTRY"].Index, spot:GetX(), spot:GetY())
local d = CityManager.GetDistrictAt(cx, cy)
d:SetDamage(DefenseTypes.DISTRICT_GARRISON, d:GetMaxDamage(DefenseTypes.DISTRICT_GARRISON))
d:SetDamage(DefenseTypes.DISTRICT_OUTER, d:GetMaxDamage(DefenseTypes.DISTRICT_OUTER))
print("scenario city-capture-civ: " .. best:GetName() .. " (player " .. owner .. ", pop " .. bestPop .. ") at " .. cx .. "," .. cy .. "; Infantry " .. tostring(u) .. " at " .. spot:GetX() .. "," .. spot:GetY()
	.. "; at war " .. tostring(me:GetDiplomacy():IsAtWarWith(owner)) .. "; HP left garrison " .. (d:GetMaxDamage(DefenseTypes.DISTRICT_GARRISON) - d:GetDamage(DefenseTypes.DISTRICT_GARRISON)))
