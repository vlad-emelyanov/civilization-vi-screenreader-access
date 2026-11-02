-- Scenario: apostle-attack. STATUS: written for the apostle-attack regress script (theological combat via the Attack key).
-- Fixture: medieval-t100 (Rome, capital 59,31; Ottoman capital 70,24, met, at peace). Idempotent.
-- Sets up: Rome founds Catholicism, Ottoman founds Islam (Game.GetReligion():FoundReligion(player, religion, holyCityID)); Rome gets an Apostle in Rome
--   and a Missionary next to it (religion set with unit:GetReligion():SetReligionType), Ottoman gets an Apostle and a Missionary on
--   the plains/grass tiles 2-3 tiles east/north-east of Rome (visible to Rome through PlayersVisibility). No diplomacy is changed (peace).
-- Keys: select the Apostle (InGameAccess state, see docs/engine-notes.md), W attacks, X next target, Enter confirms.
local ROME, OTT = 0, 4
local rel = Game.GetReligion()
local function found(pid, religionType)
	if Players[pid]:GetReligion():GetReligionTypeCreated() < 0 then
		local cap = Players[pid]:GetCities():GetCapitalCity()
		rel:FoundReligion(pid, religionType, cap:GetID())
	end
	return Players[pid]:GetReligion():GetReligionTypeCreated()
end
local romeRel = found(ROME, GameInfo.Religions["RELIGION_CATHOLICISM"].Index)
local ottRel = found(OTT, GameInfo.Religions["RELIGION_ISLAM"].Index)
local function spawn(pid, unitType, x, y, religion)
	local u = Players[pid]:GetUnits():Create(GameInfo.Units[unitType].Index, x, y)
	-- Create returns the unit in some builds, a table in others: find it again
	local found
	for _, v in Players[pid]:GetUnits():Members() do
		if v:GetX() == x and v:GetY() == y and GameInfo.Units[v:GetType()].UnitType == unitType then found = v end
	end
	if found ~= nil then found:GetReligion():SetReligionType(religion) end
	return found
end
local cap = Players[ROME]:GetCities():GetCapitalCity()
local have = {}
for _, v in Players[ROME]:GetUnits():Members() do have[GameInfo.Units[v:GetType()].UnitType] = true end
if not have["UNIT_APOSTLE"] then spawn(ROME, "UNIT_APOSTLE", cap:GetX(), cap:GetY(), romeRel) end
local function freeNear(cx, cy, minD, maxD, taken)
	for d = minD, maxD do
		for dx = -d, d do for dy = -d, d do
			local p = Map.GetPlot(cx + dx, cy + dy)
			if p ~= nil and not p:IsWater() and not p:IsMountain() and not p:IsImpassable() and Map.GetPlotDistance(cx, cy, p:GetX(), p:GetY()) == d
					and #Units.GetUnitsInPlot(p) == 0 and not taken[p:GetIndex()] then
				taken[p:GetIndex()] = true
				return p
			end
		end end
	end
end
local taken = {}
if not have["UNIT_MISSIONARY"] then
	local mp = freeNear(cap:GetX(), cap:GetY(), 1, 3, taken)
	spawn(ROME, "UNIT_MISSIONARY", mp:GetX(), mp:GetY(), romeRel)
	print("scenario apostle-attack: Rome UNIT_MISSIONARY at " .. mp:GetX() .. "," .. mp:GetY())
end
for i, t in ipairs({ "UNIT_APOSTLE", "UNIT_MISSIONARY" }) do
	local p = freeNear(cap:GetX(), cap:GetY(), 2, 4, taken)
	local u = spawn(OTT, t, p:GetX(), p:GetY(), ottRel)
	PlayersVisibility[ROME]:ChangeVisibilityCount(p:GetIndex(), 1)
	print("scenario apostle-attack: Ottoman " .. t .. " at " .. p:GetX() .. "," .. p:GetY())
end
print("scenario apostle-attack: Rome religion " .. romeRel .. ", Ottoman religion " .. ottRel)
