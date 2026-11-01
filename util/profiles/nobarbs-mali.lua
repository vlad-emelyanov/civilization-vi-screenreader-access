-- Profile "nobarbs-mali": Mali (Mansa Musa), standard speed, standard map, barbarians off, goody huts on, Ancient start, 8 city-states, different seeds from nobarbs.
-- Run in the AdvancedSetup state (civctl newgame nobarbs-mali).
local function setenum(pid, val) local p=g_GameParameters.Parameters[pid]; if not p then print("WARN no parameter "..pid); return end; for _,v in ipairs(p.Values) do if v.Value==val then g_GameParameters:SetParameterValue(p, v); return end end; print("WARN no value "..val.." for "..pid) end
local function setnum(pid, n) local p=g_GameParameters.Parameters[pid]; if not p then print("WARN no parameter "..pid); return end; g_GameParameters:SetParameterValue(p, n) end
setenum("GameSpeeds","GAMESPEED_STANDARD"); setenum("GameStartEra","ERA_ANCIENT"); setenum("MapSize","MAPSIZE_STANDARD"); setenum("GameDifficulty","DIFFICULTY_PRINCE")
setnum("CityStateCount",8); setnum("Realism",4)
setnum("GameRandomSeed",424242); setnum("MapRandomSeed",171717)
do local bp=g_GameParameters.Parameters["NoBarbarians"]; if bp then g_GameParameters:SetParameterValue(bp, true) else print("WARN no parameter NoBarbarians") end end
local pp=GetPlayerParameters(0); local lp=pp.Parameters.PlayerLeader; for _,v in ipairs(lp.Values) do if v.Value=="LEADER_MANSA_MUSA" then pp:SetParameterValue(lp, v) end end
print("profile nobarbs-mali applied")
