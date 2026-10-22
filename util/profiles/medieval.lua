-- Profile "medieval": trade routes, religion, governors, districts: Medieval start (turn 71 on Online speed).
-- Run in the AdvancedSetup state (civctl newgame medieval). Fixes leader and both seeds so the start is reproducible.
local function setenum(pid, val) local p=g_GameParameters.Parameters[pid]; if not p then print("WARN no parameter "..pid); return end; for _,v in ipairs(p.Values) do if v.Value==val then g_GameParameters:SetParameterValue(p, v); return end end; print("WARN no value "..val.." for "..pid) end
local function setnum(pid, n) local p=g_GameParameters.Parameters[pid]; if not p then print("WARN no parameter "..pid); return end; g_GameParameters:SetParameterValue(p, n) end
setenum("GameSpeeds","GAMESPEED_ONLINE"); setenum("GameStartEra","ERA_MEDIEVAL"); setenum("MapSize","MAPSIZE_SMALL"); setenum("GameDifficulty","DIFFICULTY_PRINCE")
setnum("CityStateCount",8); setnum("Realism",4)
setnum("GameRandomSeed",12345); setnum("MapRandomSeed",67890)
local pp=GetPlayerParameters(0); local lp=pp.Parameters.PlayerLeader; for _,v in ipairs(lp.Values) do if v.Value=="LEADER_TRAJAN" then pp:SetParameterValue(lp, v) end end
print("profile medieval applied")
