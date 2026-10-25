-- Scenario: corps-army. STATUS: verified 2026-10-24 on air-ready
-- Fixture: air-ready (turn 221, Rome; Aquileia 62,34). Any late game with an owned flat land area near a city works.
-- Grants Nationalism + Mobilization (corps / armies) and puts three Musketmen on three mutually adjacent free owned land plots near Aquileia.
-- Then press: select a Musketman, Tab -> Form Corps (Shift+F: X to the neighbour, Enter); then Form Army with the third.
-- Notes: Culture:SetCivic(index, true) grants a civic; Units:Create does not check the tech. Print lines name the plots.
local me = Players[0]
for _, civ in ipairs({ "CIVIC_NATIONALISM", "CIVIC_MOBILIZATION" }) do
	local info = GameInfo.Civics[civ]
	if not info then error("scenario corps-army: no " .. civ) end
	me:GetCulture():SetCivic(info.Index, true)
	print("scenario corps-army: civic " .. civ .. " granted")
end
local cities = {}
for _, c in me:GetCities():Members() do table.insert(cities, c) end
local function free(p)
	return p and not p:IsWater() and not p:IsImpassable() and not p:IsMountain() and p:GetUnitCount() == 0 and not p:IsCity()
		and p:GetOwner() == 0 and p:GetFeatureType() == -1
end
local function neighbors(p)
	local t = {}
	for dir = 0, 5 do
		local q = Map.GetAdjacentPlot(p:GetX(), p:GetY(), dir)
		if free(q) then table.insert(t, q) end
	end
	return t
end
for _, c in ipairs(cities) do
	for dx = -3, 3 do
		for dy = -3, 3 do
			local p = Map.GetPlot(c:GetX() + dx, c:GetY() + dy)
			if free(p) then
				for _, q in ipairs(neighbors(p)) do
					for _, r in ipairs(neighbors(q)) do
						if Map.GetPlotDistance(r:GetX(), r:GetY(), p:GetX(), p:GetY()) == 1 then
							for _, pl in ipairs({ p, q, r }) do
								me:GetUnits():Create(GameInfo.Units["UNIT_MUSKETMAN"].Index, pl:GetX(), pl:GetY())
								print("scenario corps-army: Musketman at " .. pl:GetX() .. "," .. pl:GetY())
							end
							return
						end
					end
				end
			end
		end
	end
end
error("scenario corps-army: no three mutually adjacent free owned plots")
