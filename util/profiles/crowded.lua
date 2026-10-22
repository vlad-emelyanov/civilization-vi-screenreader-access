-- Profile "crowded": contact, diplomacy, envoys, quests, war: Tiny map, many city-states.
-- Run in the AdvancedSetup state (civctl newgame crowded). Fixes leader and both seeds so the start is reproducible.
local function setenum(pid, val) local p=g_GameParameters.Parameters[pid]; if not p then print("WARN no parameter "..pid); return end; for _,v in ipairs(p.Values) do if v.Value==val then g_GameParameters:SetParameterValue(p, v); return end end; print("WARN no value "..val.." for "..pid) end
local function setnum(pid, n) local p=g_GameParameters.Parameters[pid]; if not p then print("WARN no parameter "..pid); return end; g_GameParameters:SetParameterValue(p, n) end
setenum("GameSpeeds","GAMESPEED_ONLINE"); setenum("GameStartEra","ERA_ANCIENT"); setenum("MapSize","MAPSIZE_TINY"); setenum("GameDifficulty","DIFFICULTY_PRINCE")
-- Tiny allows at most 10 city-states (MapSizes.xml MaxCityStates); a larger value is dropped to 0 when the game is created.
local csp=g_GameParameters.Parameters["CityStateCount"]; local want=10
if csp and csp.Values and csp.Values.MaximumValue and want>csp.Values.MaximumValue then print("WARN CityStateCount max is "..csp.Values.MaximumValue); want=csp.Values.MaximumValue end
setnum("CityStateCount",want); setnum("Realism",2)
setnum("GameRandomSeed",22222); setnum("MapRandomSeed",33333)
local pp=GetPlayerParameters(0); local lp=pp.Parameters.PlayerLeader; for _,v in ipairs(lp.Values) do if v.Value=="LEADER_TRAJAN" then pp:SetParameterValue(lp, v) end end
print("profile crowded applied, CityStateCount "..tostring(g_GameParameters.Parameters["CityStateCount"].Value))
