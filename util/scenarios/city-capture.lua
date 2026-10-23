-- Scenario: city-capture. STATUS: unverified (written blind, 2026-10-23; every engine call below is guarded with pcall)
-- Fixture: any game with a capital of player 0 and a land plot 2-3 tiles from it (early-t60, medieval-t100).
-- Goal: a city of the Free Cities / barbarian player (or the nearest foreign city) that player 0's unit can take at once.
-- Then: select the unit that is next to the city and walk it into the city (move order, W for attack if the city has defenders);
--   expected: the Raze City popup opens ("City captured ... options: Keep, Raze, ...").
-- If no creation call works the script errors and says what to do by hand (declare war on a neighbour, bring a unit to a
--   weakened city; in the tuner window `Players[0]:GetCities():GetNextCapturedCity()` returns the city once it was taken).
-- Notes: nothing here is on the forbidden list of docs/engine-notes.md; it creates one city and one unit, nothing else.
local me = Players[0]
local capital = me:GetCities():GetCapitalCity()
if not capital then error("scenario city-capture: player 0 has no capital (load a fixture with a city)") end

-- the owner of the new city: the Free Cities player when the game has one, else the barbarians
local owner
for i = 0, 63 do
	local p = Players[i]
	if p and p.IsFreeCities and p:IsFreeCities() then owner = p; break end
end
if not owner then
	for i = 0, 63 do
		local p = Players[i]
		if p and p:IsBarbarian() then owner = p; break end
	end
end
if not owner then error("scenario city-capture: no Free Cities or barbarian player in this game") end

-- a free land plot 3 tiles east/south-east of the capital (walk the ring, take the first that fits)
local cx, cy = capital:GetX(), capital:GetY()
local target
for dx = -3, 3 do
	for dy = -3, 3 do
		local plot = Map.GetPlot(cx + dx, cy + dy)
		if plot and Map.GetPlotDistance(cx, cy, cx + dx, cy + dy) == 3 and not plot:IsWater() and not plot:IsImpassable()
			and not plot:IsCity() and plot:GetUnitCount() == 0 and plot:GetOwner() == -1 then
			target = plot
			break
		end
	end
	if target then break end
end
if not target then error("scenario city-capture: no free land plot 3 tiles from the capital") end

local created = false
local attempts = {
	function() return owner:GetCities():Create(target:GetX(), target:GetY()) end,
	function() return CityManager.CreateCity(owner:GetID(), target:GetX(), target:GetY()) end,
}
for i, attempt in ipairs(attempts) do
	local ok, result = pcall(attempt)
	print("scenario city-capture: attempt " .. i .. " -> " .. tostring(ok) .. " " .. tostring(result))
	if ok and result ~= nil and result ~= false then created = true; break end
	if ok and target:IsCity() then created = true; break end
end
if not created then
	error("scenario city-capture: could not create a city; capture a real one by hand (see the header)")
end

-- an attacker next to it: a strong melee unit for player 0 on the plot between the capital and the new city
local adj
for dir = 0, 5 do
	local plot = Map.GetAdjacentPlot(target:GetX(), target:GetY(), dir)
	if plot and not plot:IsWater() and not plot:IsImpassable() and not plot:IsCity() and plot:GetUnitCount() == 0 then adj = plot; break end
end
if adj then
	local ok, err = pcall(function() return me:GetUnits():Create(GameInfo.Units["UNIT_MAN_AT_ARMS"].Index, adj:GetX(), adj:GetY()) end)
	print("scenario city-capture: attacker at " .. adj:GetX() .. "," .. adj:GetY() .. " -> " .. tostring(ok) .. " " .. tostring(err))
end
print("scenario city-capture: city at " .. target:GetX() .. "," .. target:GetY() .. " owned by player " .. owner:GetID()
	.. "; walk the unit in (declare war first if the game asks)")
