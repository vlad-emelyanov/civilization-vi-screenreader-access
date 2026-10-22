-- Profile "industrial": late-game screens: Industrial start.
-- Run in the AdvancedSetup state (civctl newgame industrial). Fixes leader and both seeds so the start is reproducible.
local function setenum(pid, val) local p=g_GameParameters.Parameters[pid]; if not p then print("WARN no parameter "..pid); return end; for _,v in ipairs(p.Values) do if v.Value==val then g_GameParameters:SetParameterValue(p, v); return end end; print("WARN no value "..val.." for "..pid) end
local function setnum(pid, n) local p=g_GameParameters.Parameters[pid]; if not p then print("WARN no parameter "..pid); return end; g_GameParameters:SetParameterValue(p, n) end
setenum("GameSpeeds","GAMESPEED_ONLINE"); setenum("GameStartEra","ERA_INDUSTRIAL"); setenum("MapSize","MAPSIZE_SMALL"); setenum("GameDifficulty","DIFFICULTY_PRINCE")
setnum("CityStateCount",8); setnum("Realism",2)
setnum("GameRandomSeed",44444); setnum("MapRandomSeed",55555)
local pp=GetPlayerParameters(0); local lp=pp.Parameters.PlayerLeader; for _,v in ipairs(lp.Values) do if v.Value=="LEADER_TRAJAN" then pp:SetParameterValue(lp, v) end end
print("profile industrial applied")
