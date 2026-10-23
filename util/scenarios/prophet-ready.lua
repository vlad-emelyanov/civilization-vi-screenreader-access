-- Scenario: prophet-ready. STATUS: verified on medieval-t100 (2026-10-22; that game has a pantheon but no Holy Site, the scenario places one)
-- Fixture: medieval-t100 (turn 99, AI-played Rome) IF its civ has a pantheon, a completed Holy Site and religions are left. The script
--   checks all three and stops with an error saying which is missing (then use another fixture or build the Holy Site first).
-- Then: select the Great Prophet (it stands on the Holy Site): InGameAccess state, `lua InGameAccess` with
--   `for _,u in Players[0]:GetUnits():Members() do if GameInfo.Units[u:GetType()].UnitType=="UNIT_GREAT_PROPHET" then UI.SelectUnit(u) break end end`,
--   Tab lists its actions, pick "Found Religion" (the game's own unit operation). The game then raises the choose-religion blocker; Next Action
--   or the notification opens the religion screen -> "Found a religion: choose a religion, N available. ...".
-- Notes: engine-legit only: a Great Prophet unit is created ON a completed Holy Site with Units:Create (same call as the settler recipe in
--   docs/engine-notes.md); no Great-People points, no popup events, no RequestPlayerOperation. Faith for a missing pantheon is NOT faked: a
--   pantheon must be chosen through the pantheon chooser first (the script tells you). Idempotent: an existing Great Prophet is reused.
local me = Players[0]
local religion = me:GetReligion()
local game = Game.GetReligion()

if religion:GetReligionTypeCreated() >= 0 then
	error("scenario prophet-ready: this civ already founded a religion (type " .. tostring(religion:GetReligionTypeCreated()) .. "); use the overview instead")
end

local left = 0
for row in GameInfo.Religions() do
	if row.Pantheon == false and not game:HasBeenFounded(row.Index) then left = left + 1 end
end
if left == 0 then error("scenario prophet-ready: every religion is already founded; use a fixture from earlier in the game (early-t60)") end

if religion:GetPantheon() < 0 then
	error("scenario prophet-ready: no pantheon yet (faith " .. tostring(religion:GetFaithBalance()) .. ", needs " .. tostring(game:GetMinimumFaithNextPantheon()) ..
		"); choose one through the pantheon chooser (it blocks the turn once the faith is there), then run this again")
end

local prophetIndex = GameInfo.Units["UNIT_GREAT_PROPHET"].Index
for _, u in me:GetUnits():Members() do
	if u:GetType() == prophetIndex then
		print("scenario prophet-ready: a Great Prophet already exists at " .. u:GetX() .. "," .. u:GetY() .. "; " .. left .. " religions left")
		return
	end
end

local holySite = GameInfo.Districts["DISTRICT_HOLY_SITE"].Index
local x, y = nil, nil
for _, d in me:GetDistricts():Members() do
	if d ~= nil and d:IsComplete() and d:GetType() == holySite then
		x, y = d:GetX(), d:GetY()
		break
	end
end
if x == nil then
	-- No Holy Site: place a finished one with the tuner call (CreateIncompleteDistrict with 100 percent construction completes it) on the first free,
	-- owned, featureless, non-mountain land plot within 2 tiles of the capital.
	local capital = me:GetCities():GetCapitalCity()
	local queue = capital:GetBuildQueue()
	for dx = -2, 2 do
		for dy = -2, 2 do
			local plot = Map.GetPlot(capital:GetX() + dx, capital:GetY() + dy)
			if x == nil and plot ~= nil and not plot:IsWater() and plot:GetDistrictType() == -1 and plot:GetOwner() == 0
					and not plot:IsMountain() and plot:GetFeatureType() == -1 then
				pcall(function() queue:CreateIncompleteDistrict(holySite, plot:GetIndex(), 100) end)
				if plot:GetDistrictType() ~= -1 then x, y = plot:GetX(), plot:GetY() end
			end
		end
	end
	if x == nil then error("scenario prophet-ready: no completed Holy Site and none could be placed near the capital") end
	print("scenario prophet-ready: placed a Holy Site at " .. x .. "," .. y)
end

me:GetUnits():Create(prophetIndex, x, y)
print("scenario prophet-ready: Great Prophet created on the Holy Site at " .. x .. "," .. y .. ", " .. left .. " religions left, pantheon " ..
	tostring(religion:GetPantheon()))
