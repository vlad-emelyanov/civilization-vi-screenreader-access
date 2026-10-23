-- Scenario: spy-ready. STATUS: verified 2026-10-22 (medieval-t100)
-- Fixture: medieval-t100 (industrial-start has no city). Grants Diplomatic Service (spy/F3 availability) with SetCivic.
-- Also run once, in the PartialScreenHooks state (F3 stays dead without it): civctl lua PartialScreenHooks 'OnCivicCompleted(0, GameInfo.Civics["CIVIC_DIPLOMATIC_SERVICE"].Index, false)'
-- Gives player 0 a spy in the capital (idempotent: reuses one that exists). Then: F3 -> "Espionage: ... Operatives. Spy X, ..., awaiting orders",
--   Enter on the spy -> chooser "Choose destination for X: N cities", Enter, Enter to confirm. Never save the game over a fixture afterwards.
local me = Players[0]
local capital = me:GetCities():GetCapitalCity()
if not capital then error("scenario spy-ready: player 0 has no capital") end
pcall(function() me:GetCulture():SetCivic(GameInfo.Civics["CIVIC_DIPLOMATIC_SERVICE"].Index, true) end)
local info = GameInfo.Units["UNIT_SPY"]
for _, unit in me:GetUnits():Members() do
	if unit:GetType() == info.Index then print("scenario spy-ready: a spy already exists"); return end
end
local spy = me:GetUnits():Create(info.Index, capital:GetX(), capital:GetY())
if spy then UnitManager.RestoreMovement(spy) end
print("scenario spy-ready: spy created in the capital")
