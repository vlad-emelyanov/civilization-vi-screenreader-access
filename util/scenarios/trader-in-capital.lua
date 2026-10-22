-- Scenario: trader-in-capital. STATUS: unverified
-- Fixture: medieval-t100 (the player has a capital and other cities/city-states to trade with). Any game with a capital of player 0 works.
-- Then press: select the trader (lua InGameAccess: UI.SelectUnit); the game opens its trade route chooser by itself for a selected
--   trader with moves -> "Trade route from <capital>: N destinations. <best route>, 1 of N". Down/Up/Home/End move, Space reads the
--   route, Enter asks "Start trade route to X?", Enter again starts it, Escape = "Trade route cancelled".
-- Notes: only GetUnits():Create (known to work). Idempotent: a trader already standing in the capital is reused.
local me = Players[0]
local capital = me:GetCities():GetCapitalCity()
if not capital then error("scenario trader-in-capital: player 0 has no capital (load a fixture with a city)") end
local traderInfo = GameInfo.Units["UNIT_TRADER"]
if not traderInfo then error("scenario trader-in-capital: UNIT_TRADER not found in GameInfo.Units") end
local cx, cy = capital:GetX(), capital:GetY()
-- Route capacity is often 1/1 with the fixture's own trader busy on its route (then Make Trade Route is "unavailable"): remove
-- traders that are not in the capital so that the spawned one has a free slot.
local doomed = {}
for _, unit in me:GetUnits():Members() do
	if unit:GetType() == traderInfo.Index and not (unit:GetX() == cx and unit:GetY() == cy) then table.insert(doomed, unit) end
end
for _, unit in ipairs(doomed) do me:GetUnits():Destroy(unit) end
for _, unit in me:GetUnits():Members() do
	if unit:GetType() == traderInfo.Index and unit:GetX() == cx and unit:GetY() == cy then
		UnitManager.RestoreMovement(unit)
		print("scenario trader-in-capital: a trader is already in the capital at " .. cx .. "," .. cy)
		return
	end
end
local newUnit = me:GetUnits():Create(traderInfo.Index, cx, cy)
if newUnit then UnitManager.RestoreMovement(newUnit) end	-- a fresh unit has 0 moves, and a trader without moves does not open the chooser
print("scenario trader-in-capital: trader created in the capital at " .. cx .. "," .. cy)
