-- Fixture facts: compact state of the loaded game for agents that cannot run it (util/fixtureinfo.py runs this in the InGame
-- tuner state and appends the output as a `facts:` block to test/fixtures/<name>.txt; `civctl fixture-info <name>`).
-- STATUS: UNVERIFIED (written offline). Every section is wrapped in pcall: an API that does not exist prints "(n/a: ...)" and the
-- rest still runs, so run it once, look for n/a lines and fix the call. One `key: value` line per print, local player only.
local pid = Game.GetLocalPlayer()
if pid == nil or pid < 0 then pid = 0 end
local p = Players[pid]

local function sec(name, f)
  local ok, r = pcall(f)
  if ok then
    if r ~= nil and r ~= "" then print(name .. ": " .. tostring(r)) end
  else
    print(name .. ": (n/a: " .. tostring(r):sub(1, 70) .. ")")
  end
end

local function short(typeName, prefix)
  typeName = tostring(typeName)
  if prefix and typeName:sub(1, #prefix) == prefix then return typeName:sub(#prefix + 1) end
  return typeName
end

local function join(t, sep) return table.concat(t, sep or ", ") end

local function civName(id)
  local c = PlayerConfigurations[id]
  if not c then return "?" end
  return short(c:GetCivilizationTypeName() or c:GetLeaderTypeName(), "CIVILIZATION_")
end

sec("turn", function() return Game.GetCurrentGameTurn() .. (p:IsTurnActive() and " (your turn)" or " (not active)") end)
sec("civ", function()
  local c = PlayerConfigurations[pid]
  return short(c:GetCivilizationTypeName(), "CIVILIZATION_") .. " / " .. short(c:GetLeaderTypeName(), "LEADER_")
end)
sec("era", function() return short(GameInfo.Eras[p:GetEras():GetEra()].EraType, "ERA_") end)
sec("government", function() return short(GameInfo.Governments[p:GetCulture():GetCurrentGovernment()].GovernmentType, "GOVERNMENT_") end)
sec("research", function()
  local t = p:GetTechs():GetResearchingTech()
  local c = p:GetCulture():GetProgressingCivic()
  local r = {}
  r[#r + 1] = "tech " .. ((t and t >= 0) and short(GameInfo.Technologies[t].TechnologyType, "TECH_") or "none")
  r[#r + 1] = "civic " .. ((c and c >= 0) and short(GameInfo.Civics[c].CivicType, "CIVIC_") or "none")
  return join(r)
end)
sec("gold", function()
  local t = p:GetTreasury()
  return string.format("%d (%+.1f/turn)", t:GetGoldBalance(), t:GetGoldYield() - t:GetTotalMaintenance())
end)
sec("faith", function() return string.format("%d (%+.1f/turn)", p:GetReligion():GetFaithBalance(), p:GetReligion():GetFaithYield()) end)
sec("diplomatic favor", function() return p:GetDiplomacy():GetFavor() end)

sec("cities", function()
  local rows = {}
  for _, c in p:GetCities():Members() do
    local d, b = {}, {}
    pcall(function()
      for _, dist in c:GetDistricts():Members() do
        local dt = short(GameInfo.Districts[dist:GetType()].DistrictType, "DISTRICT_")
        if dt ~= "CITY_CENTER" then d[#d + 1] = dt end
      end
    end)
    pcall(function()
      for row in GameInfo.Buildings() do
        if c:GetBuildings():HasBuilding(row.Index) then b[#b + 1] = short(row.BuildingType, "BUILDING_") end
      end
    end)
    local prod = ""
    pcall(function() local q = c:GetBuildQueue():CurrentlyBuilding(); if q and q ~= "" then prod = " building " .. short(q, "BUILDING_") end end)
    rows[#rows + 1] = string.format("%s pop %d; districts [%s]; buildings [%s]%s", Locale.Lookup(c:GetName()), c:GetPopulation(), join(d, " "), join(b, " "), prod)
  end
  return #rows == 0 and "none" or ("\n  - " .. table.concat(rows, "\n  - "))
end)

sec("units", function()
  local by, order = {}, {}
  for _, u in p:GetUnits():Members() do
    local t = short(GameInfo.Units[u:GetType()].UnitType, "UNIT_")
    local mv = 0
    local ok, m = pcall(function() return u:GetMovesRemaining() end)
    if not ok then ok, m = pcall(function() return u:GetMovementMovesRemaining() end) end
    if ok and m and m > 0 then mv = 1 end
    if not by[t] then by[t] = { n = 0, moving = 0 }; order[#order + 1] = t end
    by[t].n = by[t].n + 1
    by[t].moving = by[t].moving + mv
  end
  table.sort(order)
  local r = {}
  for _, t in ipairs(order) do r[#r + 1] = string.format("%s x%d (%d with moves)", t, by[t].n, by[t].moving) end
  return #r == 0 and "none" or join(r)
end)

sec("trade routes", function()
  local tr = p:GetTrade()
  return string.format("%d of %d slots used", tr:GetNumOutgoingRoutes(), tr:GetOutgoingRouteCapacity())
end)

sec("met civs", function()
  local r = {}
  for _, id in ipairs(PlayerManager.GetAliveMajorIDs()) do
    if id ~= pid and p:GetDiplomacy():HasMet(id) then r[#r + 1] = civName(id) end
  end
  return #r == 0 and "none" or join(r)
end)
sec("city-states met", function()
  local r = {}
  local give = 0
  pcall(function() give = p:GetInfluence():GetTokensToGive() end)
  for _, id in ipairs(PlayerManager.GetAliveMinorIDs()) do
    if p:GetDiplomacy():HasMet(id) then r[#r + 1] = civName(id) end
  end
  return string.format("%d met (%s); envoy tokens to give: %d", #r, join(r), give)
end)

sec("great people points", function()
  local gp = Game.GetGreatPeople()
  local r = {}
  for row in GameInfo.GreatPersonClasses() do
    local ok, pts = pcall(function() return gp:GetPointsTotal(row.Index, pid) end)
    if ok and pts and pts > 0 then r[#r + 1] = short(row.GreatPersonClassType, "GREAT_PERSON_CLASS_") .. " " .. pts end
  end
  return #r == 0 and "none" or join(r)
end)

sec("religion", function()
  local rel = p:GetReligion()
  local r = {}
  local pan = rel:GetPantheon()
  r[#r + 1] = "pantheon " .. ((pan and pan >= 0) and short(GameInfo.Beliefs[pan].BeliefType, "BELIEF_") or "none")
  local created = rel:GetReligionTypeCreated()
  r[#r + 1] = "founded " .. ((created and created >= 0) and short(GameInfo.Religions[created].ReligionType, "RELIGION_") or "no")
  return join(r)
end)

sec("spies", function()
  local e = p:GetEspionage()
  local n = 0
  local ok, list = pcall(function() return e:GetSpies() end)
  if ok and list then n = #list else n = e:GetNumSpies() end
  return n
end)

sec("governors", function()
  local g = p:GetGovernors()
  local r = {}
  r[#r + 1] = string.format("points %d spent %d", g:GetGovernorPoints(), g:GetGovernorPointsSpent())
  local have = {}
  for row in GameInfo.Governors() do
    local ok, has = pcall(function() return g:HasGovernor(row.Hash) end)
    if ok and has then have[#have + 1] = short(row.GovernorType, "GOVERNOR_") end
  end
  r[#r + 1] = "appointed [" .. join(have, " ") .. "]"
  return join(r)
end)

sec("blockers", function()
  local b = NotificationManager.GetFirstEndTurnBlocking(pid)
  if b == EndTurnBlockingTypes.NO_ENDTURN_BLOCKING then return "none" end
  for k, v in pairs(EndTurnBlockingTypes) do if v == b then return k end end
  return tostring(b)
end)
