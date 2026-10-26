-- Scenario: barbarian-scout-near-city. STATUS: unverified (written blind 2026-10-26)
-- Fixture: early-t60 (capital Rome at 60,33; barbarians on). Any game with a capital of player 0 and a barbarian player works.
-- Then: the hub sees the scout come into view -> "Alarm: Barbarian Scout has seen <city>, N tiles <dir>. If it gets back to its camp,
--   a raid follows. Kill it: W targets it" (mid-turn, interrupting). W with a soldier targets it. End the turn: the Enemies line says
--   "heading away from <city>" while it is in view, "Barbarian Scout escaped. Expect a raid ..." once it is out of sight, and N then
--   ends with "Raid expected from the ...". J: the first category is "Threats" while the scout is in view.
-- Notes: spawns a barbarian Scout (UNIT_BARBARIAN_SCOUT if the game has it, else UNIT_SCOUT) on a free passable land plot 3 tiles from the
--   capital, preferring one inside our borders. Uses only GetUnits():Create (known to work, see enemy-at-capital).
local me = Players[0]
local capital = me:GetCities():GetCapitalCity()
if not capital then error("scenario barbarian-scout-near-city: player 0 has no capital (load a fixture with a city)") end
local barb
for i = 0, 63 do
	local p = Players[i]
	if p and p:IsBarbarian() then barb = p; break end
end
if not barb then error("scenario barbarian-scout-near-city: no barbarian player (barbarians disabled in this game)") end
local row = GameInfo.Units["UNIT_BARBARIAN_SCOUT"] or GameInfo.Units["UNIT_SCOUT"]
if not row then error("scenario barbarian-scout-near-city: no scout unit type") end
local cx, cy = capital:GetX(), capital:GetY()
local fallback
for dy = -3, 3 do
	for dx = -3, 3 do
		local plot = Map.GetPlot(cx + dx, cy + dy)
		if plot and Map.GetPlotDistance(cx, cy, plot:GetX(), plot:GetY()) == 3 and not plot:IsWater() and not plot:IsImpassable()
			and plot:GetUnitCount() == 0 and not plot:IsCity() then
			if plot:GetOwner() == 0 then
				barb:GetUnits():Create(row.Index, plot:GetX(), plot:GetY())
				print("scenario barbarian-scout-near-city: scout (" .. row.UnitType .. ") at " .. plot:GetX() .. "," .. plot:GetY() .. " in our borders, capital at " .. cx .. "," .. cy)
				return
			end
			fallback = fallback or plot
		end
	end
end
if fallback then
	barb:GetUnits():Create(row.Index, fallback:GetX(), fallback:GetY())
	print("scenario barbarian-scout-near-city: scout (" .. row.UnitType .. ") at " .. fallback:GetX() .. "," .. fallback:GetY() .. " outside our borders, capital at " .. cx .. "," .. cy)
	return
end
error("scenario barbarian-scout-near-city: no free land plot 3 tiles from the capital")
