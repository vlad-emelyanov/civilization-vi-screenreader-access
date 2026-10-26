-- BlindSpots.lua: camp wording, clustering of out-of-sight and unexplored plots near our cities
stub("engine")
local world = stub("world").new{ width = 40, height = 30 }
world:install()
include("PlotDescription")
include("BlindSpots")

test("guard list", function()
	eq(BlindSpots.GuardList({ "Spearman" }), "Spearman")
	eq(BlindSpots.GuardList({ "Spearman", "Archer" }), "Spearman and Archer")
	eq(BlindSpots.GuardList({ "Spearman", "Spearman", "Archer" }), "2 Spearman and Archer")
	eq(BlindSpots.GuardList({ "A", "B", "C" }), "A, B and C")
end)

test("camp text: guards in view, remembered guards in the fog, empty camp, old memory", function()
	eq(BlindSpots.CampText("Barbarian Camp", "7 tiles north-east of Rome", { "Spearman" }, false, 0),
		"Barbarian Camp, 7 tiles north-east of Rome, guarded by Spearman")
	eq(BlindSpots.CampText("Barbarian Camp", "7 tiles north-east of Rome", { "Spearman" }, true, 2),
		"Barbarian Camp, 7 tiles north-east of Rome, guarded by Spearman (last seen 2 turns ago)")
	eq(BlindSpots.CampText("Barbarian Camp", "7 tiles north-east of Rome", { "Spearman" }, true, 1),
		"Barbarian Camp, 7 tiles north-east of Rome, guarded by Spearman (last seen 1 turn ago)")
	eq(BlindSpots.CampText("Barbarian Camp", "here", {}, false, 0), "Barbarian Camp, here, not guarded right now")
	eq(BlindSpots.CampText("Barbarian Camp", "here", {}, true, 0), "Barbarian Camp, here, was not guarded (last seen this turn)")
	eq(BlindSpots.CampText("Barbarian Camp", "here", nil, true, 0), "Barbarian Camp, last seen, here")
	eq(BlindSpots.CampText("Barbarian Camp", "here", nil, false, 0), "Barbarian Camp, here")
end)

test("camp advice and destroyed lines state only a known amount", function()
	eq(BlindSpots.CampAdvice(50), "Destroying it gives about 50 gold and stops raids from it. Fighting near it gives your units experience")
	eq(BlindSpots.CampAdvice(nil), "Destroying it gives gold and stops raids from it. Fighting near it gives your units experience")
	eq(BlindSpots.DestroyedText(50), "Barbarian camp destroyed, 50 gold")
	eq(BlindSpots.DestroyedText(0), "Barbarian camp destroyed")
	eq(BlindSpots.DestroyedText(nil), "Barbarian camp destroyed")
	eq(BlindSpots.DestroyedText(50, 2), "2 barbarian camps destroyed, 50 gold")
end)

test("spot, unexplored and advice wording", function()
	eq(BlindSpots.SpotText(12, "5 tiles north of Antium"), "Blind spot: 12 tiles out of sight, 5 tiles north of Antium")
	eq(BlindSpots.SpotText(1, nil), "Blind spot: 1 tile out of sight")
	eq(BlindSpots.UnexploredText(8, "6 tiles west of Rome"), "8 unexplored tiles, 6 tiles west of Rome")
	local advice = BlindSpots.Advice(4, 7)
	assert(advice:find("Barbarians can appear where no one sees: at least 4 tiles from any city and 7 from another camp", 1, true), advice)
	assert(BlindSpots.Advice(nil, nil):find("^Barbarians can appear where no one sees%. "), BlindSpots.Advice(nil, nil))
end)

-- a city in the middle of a 40 x 30 map, everything in view except what the tests hide
world:city(0, 20, 14, "Rome")
local function setVisible(x1, y1, x2, y2, props)
	for y = y1, y2 do for x = x1, x2 do world:set(x, y, props) end end
end
local function cities() return { { x = 20, y = 14, id = 1 } } end
local vis = PlayersVisibility[0]

test("no hidden plots: no candidates", function()
	local blind, unexplored = BlindSpots.Candidates(cities(), vis)
	eq(#blind, 0)
	eq(#unexplored, 0)
end)

test("a block of fogged land 5 to 6 tiles north is one blind spot; water, mountains and near plots are not counted", function()
	setVisible(18, 8, 22, 9, { fogged = true })		-- rows 8 and 9: 5 and 6 tiles from row 14
	setVisible(19, 11, 21, 11, { fogged = true })	-- 3 tiles away: too near to count
	world:set(20, 8, { terrain = "water" })
	world:set(21, 8, { mountain = true })
	local blind = BlindSpots.Candidates(cities(), vis)
	eq(#blind, 8)
	local clusters = BlindSpots.Clusters(blind, 4, 10)
	eq(#clusters, 1)
	eq(clusters[1].size, 8)
	-- the middle is one of the members
	assert(clusters[1].y == 8 or clusters[1].y == 9)
	assert(clusters[1].x >= 18 and clusters[1].x <= 22)
end)

test("a cluster smaller than the minimum is dropped", function()
	setVisible(18, 8, 22, 9, { fogged = false })
	setVisible(19, 11, 21, 11, { fogged = false })
	setVisible(30, 14, 31, 15, { fogged = true })		-- 10 tiles east: out of range
	setVisible(26, 14, 27, 14, { fogged = true })		-- 6 and 7 tiles east: 2 plots
	local blind = BlindSpots.Candidates(cities(), vis)
	eq(#blind, 2)
	eq(#BlindSpots.Clusters(blind, 4, 10), 0)
	setVisible(26, 14, 27, 14, { fogged = false })
	setVisible(30, 14, 31, 15, { fogged = false })
end)

test("unexplored plots within 6 tiles are counted without reading the terrain, and split by direction", function()
	setVisible(12, 13, 14, 15, { hidden = true })		-- west, 6 to 8 tiles: only the near part counts
	setVisible(26, 13, 27, 15, { hidden = true })		-- east, 6 and 7 tiles
	world:set(26, 14, { terrain = "water" })
	local _, unexplored = BlindSpots.Candidates(cities(), vis)
	assert(#unexplored >= 4, #unexplored)
	for _, c in ipairs(unexplored) do
		assert(Map.GetPlotDistance(20, 14, c.x, c.y) <= 6)
		assert(c.group:find("^1:"), c.group)
	end
	local clusters = BlindSpots.Clusters(unexplored, 1, 10)
	assert(#clusters >= 2, #clusters)		-- west and east are different clusters
	setVisible(12, 13, 14, 15, { hidden = false })
	setVisible(26, 13, 27, 15, { hidden = false })
end)

test("a big cluster around the city is cut by direction, a small one is not", function()
	-- everything 5 to 8 tiles from Rome out of sight: a ring of ~150 plots
	for y = 0, 29 do for x = 0, 39 do
		local d = Map.GetPlotDistance(20, 14, x, y)
		if d >= 5 and d <= 8 then world:set(x, y, { fogged = true }) end
	end end
	local blind = BlindSpots.Candidates(cities(), vis)
	local whole = BlindSpots.Clusters(blind, 4, 10, 1000)
	eq(#whole, 1)
	local cut = BlindSpots.Clusters(blind, 4, 10)
	eq(#cut, 8)
	for y = 0, 29 do for x = 0, 39 do world:set(x, y, { fogged = false }) end end
end)

test("two separate blocks are two clusters", function()
	setVisible(18, 7, 19, 8, { fogged = true })		-- 6 to 7 tiles north-west / north
	setVisible(24, 8, 25, 9, { fogged = true })		-- north-east
	local blind = BlindSpots.Candidates(cities(), vis)
	local clusters = BlindSpots.Clusters(blind, 4, 10)
	eq(#clusters, 2)
	setVisible(18, 7, 19, 8, { fogged = false })
	setVisible(24, 8, 25, 9, { fogged = false })
end)

test("clusters are largest first and capped", function()
	local cands = {}
	-- 12 separate groups of 4 plots in a row, bigger ones later
	for g = 1, 12 do
		for i = 0, 3 + (g > 10 and 2 or 0) do
			local x, y = 1 + i, 2 * g
			cands[#cands + 1] = { x = x, y = y, index = y * 40 + x, group = "g" .. g }
		end
	end
	local clusters = BlindSpots.Clusters(cands, 4, 10)
	eq(#clusters, 10)
	eq(clusters[1].size, 6)
	eq(clusters[2].size, 6)
	eq(clusters[3].size, 4)
end)
