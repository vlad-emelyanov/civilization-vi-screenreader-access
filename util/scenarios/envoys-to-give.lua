-- Scenario: envoys-to-give. STATUS: verified 2026-10-22
-- Fixture: early-t60 (9 city-states met after this script) or crowded-start. Any game with city-states works.
-- Then press: F2 -> "Send envoys: 3 to give. Hong Kong, Industrial, you have 2 envoys, no suzerain, next bonus at 3, 1 of 9";
--   Enter / Right adds an envoy, C confirms; Escape closes. Meeting them queues advisor popups: close them with Enter first.
-- Notes: meets every city-state first (both sides). City-states are found via PlayerConfigurations level, Players[i]:IsMinor()
--   does not exist. Sets the tokens to give to exactly 3 (idempotent).
local me = Players[0]
local met = 0
for i = 0, 63 do
	local p = Players[i]
	local cfg = PlayerConfigurations[i]
	if p and cfg and cfg:GetCivilizationLevelTypeName() == "CIVILIZATION_LEVEL_CITY_STATE" and p:IsAlive() then
		me:GetDiplomacy():SetHasMet(i)
		p:GetDiplomacy():SetHasMet(0)
		met = met + 1
	end
end
local infl = me:GetInfluence()
infl:ChangeTokensToGive(3 - infl:GetTokensToGive())
print("scenario envoys-to-give: met " .. met .. " city-states, tokens to give now " .. tostring(infl:GetTokensToGive()))
