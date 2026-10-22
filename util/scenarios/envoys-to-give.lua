-- Scenario: envoys-to-give. STATUS: unverified (written offline)
-- Fixture: crowded-start (many city-states). Works on any game with city-states.
-- Then press: F2 -> "Send envoys: 3 to give. <city-state>, <type>, you have no envoys, ..., 1 of N";
--   Enter / Right adds an envoy, C confirms. Control+Y on the top panel should say "3 envoys to give".
-- Notes: meets every city-state first (both sides, as in the civ-test skill) so the screen has something to list.
local me = Players[0]
local met = 0
for i = 0, 63 do
	local p = Players[i]
	if p and p:IsMinor() and p:IsAlive() then
		me:GetDiplomacy():SetHasMet(i)
		p:GetDiplomacy():SetHasMet(0)
		met = met + 1
	end
end
local infl = me:GetInfluence()
infl:ChangeTokensToGive(3)
print("scenario envoys-to-give: met " .. met .. " city-states, tokens to give now " .. tostring(infl:GetTokensToGive()))
