-- Scenario: nuke-ready. STATUS: verified 2026-10-24 on air-ready
-- Fixture: air-ready (turn 221, Rome; Bomber in Lugdunum 55,32 with an Aerodrome). Needs a Bomber of ours.
-- Gives player 0 one Nuclear Device (WMDs:ChangeWeaponCount) and TECH_NUCLEAR_FISSION; spawns a Bomber in Lugdunum if there is none.
-- Then press: select the Bomber, Tab -> the Nuclear strike item(s); choose one -> target mode; Enter on a target opens the game's
-- "Are you sure" launch popup via a real mouse click (#KEYNAV_CLICK). NEVER confirm the launch in a test.
-- Notes: GetWMDs():ChangeWeaponCount(WMD index, n) is a data-only change (no project needed).
local me = Players[0]
me:GetTechs():SetTech(GameInfo.Technologies["TECH_NUCLEAR_FISSION"].Index, true)
local idx = GameInfo.WMDs["WMD_NUCLEAR_DEVICE"].Index
me:GetWMDs():ChangeWeaponCount(idx, 1)
print("scenario nuke-ready: nuclear devices now " .. me:GetWMDs():GetWeaponCount(idx))
local city
for _, c in me:GetCities():Members() do
	if Locale.Lookup(c:GetName()) == "Lugdunum" then city = c end
end
if not city then error("scenario nuke-ready: no city Lugdunum") end
local n = 0
for _, u in me:GetUnits():Members() do
	if GameInfo.Units[u:GetType()].UnitType == "UNIT_BOMBER" then n = n + 1 end
end
if n == 0 then
	me:GetUnits():Create(GameInfo.Units["UNIT_BOMBER"].Index, city:GetX(), city:GetY())
	print("scenario nuke-ready: Bomber spawned in Lugdunum")
else
	print("scenario nuke-ready: " .. n .. " Bomber(s) already there")
end
