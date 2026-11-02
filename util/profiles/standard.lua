-- Profile "standard": like nobarbs (same seeds, barbarians off) but with the ruleset Standard Rules (Gathering Storm OFF), the ruleset of the user's multiplayer game.
-- Run in the AdvancedSetup state (civctl newgame standard). Fixes leader and both seeds so the start is reproducible.
local function setenum(pid, val) local p=g_GameParameters.Parameters[pid]; if not p then print("WARN no parameter "..pid); return end; for _,v in ipairs(p.Values) do if v.Value==val then g_GameParameters:SetParameterValue(p, v); return end end; print("WARN no value "..val.." for "..pid) end
local function setnum(pid, n) local p=g_GameParameters.Parameters[pid]; if not p then print("WARN no parameter "..pid); return end; g_GameParameters:SetParameterValue(p, n) end
-- The ruleset goes FIRST: changing it refreshes the parameters.
setenum("Ruleset","RULESET_STANDARD")
setenum("GameSpeeds","GAMESPEED_ONLINE"); setenum("GameStartEra","ERA_ANCIENT"); setenum("MapSize","MAPSIZE_SMALL"); setenum("GameDifficulty","DIFFICULTY_PRINCE")
setnum("CityStateCount",10) -- no Realism (Disaster Intensity) parameter in Standard Rules
setnum("GameRandomSeed",12345); setnum("MapRandomSeed",67890)
-- No barbarians: setup parameter NoBarbarians (ConfigurationId GAME_NO_BARBARIANS, SetupParameters.xml).
do local bp=g_GameParameters.Parameters["NoBarbarians"]; if bp then g_GameParameters:SetParameterValue(bp, true) else print("WARN no parameter NoBarbarians") end end
local pp=GetPlayerParameters(0); local lp=pp.Parameters.PlayerLeader; for _,v in ipairs(lp.Values) do if v.Value=="LEADER_TRAJAN" then pp:SetParameterValue(lp, v) end end
print("profile standard applied")
