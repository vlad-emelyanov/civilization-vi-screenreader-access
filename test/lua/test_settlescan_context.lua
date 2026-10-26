-- SettleScan.lua: G6 distances / space context and G8 here-versus-best wording
stub("engine")
include("SettleScan")

local function freshWorld()
	local w = stub("world").new{ width = 24, height = 14 }
	w:install()
	Game.GetCurrentGameTurn = function() return math.random(1, 1e9) end
	return w
end

local function settler(w, x, y)
	return w.fakeUnit(w:unit(0, x, y, { moves = 2 }))
end

test("distances name the nearest own city and a rival city within 10", function()
	local w = freshWorld()
	w:city(0, 4, 7, "Rome")
	w:city(1, 17, 7, "Kyoto")
	local scan = SettleScan_Scan(settler(w, 9, 7), true)
	local here = scan.here
	istrue(here ~= nil, "no here candidate")
	eq(here.context.own.name, "Rome")
	eq(here.context.own.d, 5)
	eq(here.context.rival.name, "Kyoto")
	eq(here.context.rival.d, 8)
	eq(SettleScan_DistanceText(here), ", 5 tiles from Rome, 8 from Kyoto (LOC_CIV_1)")
end)

test("rival beyond 10 tiles is not named; Behind the own city", function()
	local w = freshWorld()
	w:city(0, 3, 7, "Rome")
	w:city(1, 22, 7, "Kyoto")
	local c = SettleScan_Scan(settler(w, 8, 7), true).here
	eq(c.context.rival, nil)
	eq(SettleScan_DistanceText(c), ", 5 tiles from Rome")
	contains(SettleScan_SpaceText(c), "Behind Rome")
end)

test("Between when the rival city is closer than mine", function()
	local w = freshWorld()
	w:city(0, 2, 7, "Rome")
	w:city(1, 14, 7, "Kyoto")
	local c = SettleScan_Scan(settler(w, 9, 7), true).here
	contains(SettleScan_SpaceText(c), "Between Rome and LOC_CIV_1")
end)

test("a minor civ city is not named as a rival", function()
	local w = freshWorld()
	w:city(0, 2, 7, "Rome")
	w:city(2, 14, 7, "Geneva")
	w.minors = { [2] = true }
	local c = SettleScan_Scan(settler(w, 9, 7), true).here
	eq(c.context.rival, nil)
end)

test("defensibility: sides of mountain or water", function()
	local w = freshWorld()
	w:set(8, 7, { mountain = true })
	w:set(10, 7, { terrain = "water" })
	w:set(9, 6, { terrain = "water" })
	local c = SettleScan_Scan(settler(w, 9, 7), true).here
	istrue(c ~= nil, "no here candidate")
	eq(c.context.sides, 3)
	contains(SettleScan_SpaceText(c), "3 of 6 sides mountain or water")
	contains(c.detail, "3 of 6 sides")
end)

-- wording on hand-made scans
local function cand(score, extra)
	local c = { score = score, static = score, reasons = { "river", "coast" }, negatives = {}, turns = 1, relative = "1 tile north", x = 1, y = 1 }
	for k, v in pairs(extra or {}) do c[k] = v end
	return c
end

test("here and best about the same", function()
	local here, best = cand(20), cand(22)
	here.here = true
	local text = SettleScan_Sentence({ here = here, best = best, list = { best, here } }, "B", true)
	eq(text, "Here is good: river, coast. Best nearby is about the same. B founds here")
	eq(SettleScan_Compare({ here = here, best = best }), "same")
end)

test("best clearly better", function()
	local here, best = cand(10), cand(20, { reasons = { "coast", "silk" } })
	here.here = true
	local text = SettleScan_Sentence({ here = here, best = best }, "B", true)
	eq(text, "Best spot is clearly better: 1 tile north, coast, silk, 1 turn. X to browse")
end)

test("in between keeps the old wording; gap at the thresholds", function()
	local here, best = cand(10), cand(15, { recommended = true })
	here.here = true
	eq(SettleScan_Compare({ here = here, best = best }), "between")
	eq(SettleScan_Compare({ here = cand(10), best = cand(13) }), "between")		-- gap 3: not "same"
	eq(SettleScan_Compare({ here = cand(10), best = cand(16) }), "between")		-- gap 6: not "clearly"
	local text = SettleScan_Sentence({ here = here, best = best }, "B", true)
	eq(text, "Can settle here. Best: 1 tile north, 1 turn, river, coast, recommended. X to browse.")
end)

test("here invalid keeps Cannot settle here", function()
	local best = cand(20)
	eq(SettleScan_Sentence({ hereReason = "too close to Rome", best = best }, "B", true),
		"Cannot settle here: too close to Rome. Best: 1 tile north, 1 turn, river, coast. X to browse.")
	eq(SettleScan_Sentence({ hereReason = "", list = {} }, "B", true), "Cannot settle here. No spot found nearby.")
end)

test("here is the best uses the found key", function()
	local here = cand(20)
	here.here = true
	eq(SettleScan_Sentence({ here = here, best = here }, "Enter", false), "Can settle here, this is the best spot nearby: river, coast. Enter to found next turn.")
end)
