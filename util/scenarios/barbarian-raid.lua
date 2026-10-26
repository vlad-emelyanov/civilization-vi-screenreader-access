-- Scenario: barbarian-raid. STATUS: unverified (written blind 2026-10-26)
-- Fixture: early-t60 (capital Rome at 60,33; barbarians on). Any game with a capital of player 0 and a barbarian player works.
-- Then: End the turn (or the next turn start) -> "Raid: 3 barbarians near <city>: Horseman N tiles <dir>, 2 Warriors N tiles <dir>.
--   <city> defense N. Your nearest soldiers: ..." ; our Builder stands next to the horseman -> "Builder near <city> in danger:
--   Barbarian Horseman 1 tile <dir>. Move it into <city>". J: first category "Threats", M sends a soldier.
-- Notes: spawns a barbarian Horseman at distance 3 and two Warriors at distance 4 from the capital (same side), and a Builder of ours
--   next to the horseman. Uses only GetUnits():Create (known to work, see enemy-at-capital); the builder part is skipped with a print
--   when the create fails or no plot is free.
local me = Players[0]
local capital = me:GetCities():GetCapitalCity()
if not capital then error("scenario barbarian-raid: player 0 has no capital (load a fixture with a city)") end
local barb
for i = 0, 63 do
	local p = Players[i]
	if p and p:IsBarbarian() then barb = p; break end
end
if not barb then error("scenario barbarian-raid: no barbarian player (barbarians disabled in this game)") end
local cx, cy = capital:GetX(), capital:GetY()
local function free(plot)
	return plot and not plot:IsWater() and not plot:IsImpassable() and plot:GetUnitCount() == 0 and not plot:IsCity()
end
local function ring(d)
	local list = {}
	for dy = -d, d do
		for dx = -d, d do
			local plot = Map.GetPlot(cx + dx, cy + dy)
			if free(plot) and Map.GetPlotDistance(cx, cy, plot:GetX(), plot:GetY()) == d then table.insert(list, plot) end
		end
	end
	return list
end
local near, far = ring(3), ring(4)
if #near < 1 or #far < 2 then error("scenario barbarian-raid: not enough free land plots 3-4 tiles from the capital") end
local horse = near[1]
barb:GetUnits():Create(GameInfo.Units["UNIT_HORSEMAN"].Index, horse:GetX(), horse:GetY())
-- the two warriors: the free plots at distance 4 closest to the horseman
table.sort(far, function(a, b)
	return Map.GetPlotDistance(a:GetX(), a:GetY(), horse:GetX(), horse:GetY()) < Map.GetPlotDistance(b:GetX(), b:GetY(), horse:GetX(), horse:GetY())
end)
for i = 1, 2 do
	barb:GetUnits():Create(GameInfo.Units["UNIT_WARRIOR"].Index, far[i]:GetX(), far[i]:GetY())
end
print("scenario barbarian-raid: horseman at " .. horse:GetX() .. "," .. horse:GetY() .. ", warriors at " .. far[1]:GetX() .. "," .. far[1]:GetY() .. " and " .. far[2]:GetX() .. "," .. far[2]:GetY() .. ", capital at " .. cx .. "," .. cy)
-- a builder of ours next to the horseman (not on a city plot)
for dir = 0, 5 do
	local plot = Map.GetAdjacentPlot(horse:GetX(), horse:GetY(), dir)
	if free(plot) and Map.GetPlotDistance(cx, cy, plot:GetX(), plot:GetY()) >= 2 then
		local ok, err = pcall(function() me:GetUnits():Create(GameInfo.Units["UNIT_BUILDER"].Index, plot:GetX(), plot:GetY()) end)
		print("scenario barbarian-raid: builder of ours at " .. plot:GetX() .. "," .. plot:GetY() .. (ok and "" or (" FAILED: " .. tostring(err))))
		return
	end
end
print("scenario barbarian-raid: no free plot for the builder next to the horseman (raid line only)")
