-- Profile "modes": game modes (Barbarian Clans + Tech/Civic Shuffle, the owned modes; docs/game-content.md): Medieval start.
-- Run in the AdvancedSetup state (civctl newgame modes). Fixes leader and both seeds so the start is reproducible.
local function setenum(pid, val) local p=g_GameParameters.Parameters[pid]; if not p then print("WARN no parameter "..pid); return end; for _,v in ipairs(p.Values) do if v.Value==val then g_GameParameters:SetParameterValue(p, v); return end end; print("WARN no value "..val.." for "..pid) end
local function setnum(pid, n) local p=g_GameParameters.Parameters[pid]; if not p then print("WARN no parameter "..pid); return end; g_GameParameters:SetParameterValue(p, n) end
setenum("GameSpeeds","GAMESPEED_ONLINE"); setenum("GameStartEra","ERA_MEDIEVAL"); setenum("MapSize","MAPSIZE_SMALL"); setenum("GameDifficulty","DIFFICULTY_PRINCE")
setnum("CityStateCount",8); setnum("Realism",2)
setnum("GameRandomSeed",88888); setnum("MapRandomSeed",99999)
-- Game modes: only when the parameter exists (depends on the installed content).
for _,m in ipairs({"GameMode_BarbarianClans","GameMode_Tree_Randomizer"}) do local sp=g_GameParameters.Parameters[m]; if sp then g_GameParameters:SetParameterValue(sp, true) else print("WARN "..m.." not available") end end
local pp=GetPlayerParameters(0); local lp=pp.Parameters.PlayerLeader; for _,v in ipairs(lp.Values) do if v.Value=="LEADER_TRAJAN" then pp:SetParameterValue(lp, v) end end
print("profile modes applied")
