-- GreatPeopleText.lua: great people popup texts
stub("engine")
include("GreatPeopleText")

local function person()
	return {
		className = "Great Scientist", name = "Hypatia", eraName = "Ancient", points = 120, cost = 480, perTurn = 3,
		leaderName = "Phoenicia", leaderPoints = 300, abilities = { "Boosts a library", "Charges 2" },
		standings = { { name = "Rome", points = 120, perTurn = 3, isPlayer = true }, { name = "Phoenicia", points = 300, perTurn = 5 } },
		gold = { shown = true, cost = 640, can = false, have = 520 }, faith = { shown = true, cost = 320, can = true, have = 400 },
	}
end

test("number formatting", function()
	eq(GreatPeopleText_Num(120), "120")
	eq(GreatPeopleText_Num(2.5), "2.5")
	eq(GreatPeopleText_Num(2.04), "2")
	eq(GreatPeopleText_Num(nil), "0")
end)

test("item: class + name, progress, gold price", function()
	eq(GreatPeopleText_Item(person()), "Great Scientist Hypatia, 120 of 480 points, 640 gold")
	local p = person(); p.gold.can = true
	eq(GreatPeopleText_Item(p), "Great Scientist Hypatia, 120 of 480 points, 640 gold, can buy")
	p.gold.shown = false
	eq(GreatPeopleText_Item(p), "Great Scientist Hypatia, 120 of 480 points")
end)

test("item recruitable and none left", function()
	local p = person(); p.canRecruit = true; p.canReject = true
	eq(GreatPeopleText_Item(p):match(", you can recruit now or pass$"), ", you can recruit now or pass")
	eq(GreatPeopleText_Item({ className = "Great Admiral", none = true }), "Great Admiral: none left, all claimed")
end)

test("era name is not doubled", function()
	eq(GreatPeopleText_Era("Atomic Era"), "Atomic Era")
	eq(GreatPeopleText_Era("Ancient"), "Ancient era")
	eq(GreatPeopleText_Era(""), nil)
end)

test("detail has rate, leader, patronage, era, abilities and standings", function()
	eq(GreatPeopleText_Detail(person()), "Great Scientist Hypatia. You earn 3 points per turn. Phoenicia leads with 300. 640 gold, can't afford, need 120 more gold. 320 faith, affordable. Ancient era. Boosts a library. Charges 2. Points: Rome (you) 120 of 480, 3 per turn; Phoenicia 300 of 480, 5 per turn")
end)

test("actions: patronize with reasons", function()
	local a = GreatPeopleText_Actions(person())
	eq(#a, 3)
	eq(a[1].run, "gold"); eq(a[1].enabled, false)
	eq(a[1].text, "Patronize with gold, 640, unavailable: can't afford, need 120 more gold")
	eq(a[1].reason, "Can't afford, need 120 more gold")
	eq(a[2].run, "faith"); eq(a[2].enabled, true); eq(a[2].text, "Patronize with faith, 320")
	eq(a[3].text, "Back")
end)

test("actions: recruit and pass first", function()
	local p = person(); p.canRecruit = true; p.recruitCost = 480; p.canReject = true; p.rejectCost = 60
	p.gold.shown = false; p.faith.shown = false
	local a = GreatPeopleText_Actions(p)
	eq(a[1].text, "Recruit Hypatia, costs 480 points")
	eq(a[2].text, "Pass on Hypatia, costs 60 points")
	eq(#a, 3)
	eq(GreatPeopleText_ActionsTitle(p), "Actions for Hypatia")
end)

test("patronage reasons: off, congress, earn conditions", function()
	local p = person()
	p.gold.off = true
	eq(GreatPeopleText_PatronageReason(p, p.gold, "gold"), "Patronage with gold is turned off")
	p.gold.off = nil; p.readOnly = true
	eq(GreatPeopleText_PatronageReason(p, p.gold, "gold"), "Not possible during the World Congress")
	p.readOnly = false; p.gold.have = 700; p.earnConditions = "Needs a Library"
	eq(GreatPeopleText_PatronageReason(p, p.gold, "gold"), "Can't earn this person: Needs a Library")
end)

test("past items and opening", function()
	local p = { name = "Hypatia", className = "Great Scientist", claimant = "Rome", date = "3500 BC", eraName = "Ancient", abilities = { "Boosts" } }
	eq(GreatPeopleText_PastItem(p), "Hypatia, Great Scientist, recruited by Rome, 3500 BC")
	eq(GreatPeopleText_PastDetail(p), "Hypatia, Great Scientist, recruited by Rome, 3500 BC. Ancient era. Boosts")
	eq(GreatPeopleText_Opening(false, 9, "X", 1, 9), "Great People, 9 available. X, 1 of 9")
	eq(GreatPeopleText_Opening(true, 1, "Y", 1, 1), "Previously recruited, 1 person. Y, 1 of 1")
	eq(GreatPeopleText_Opening(true, 0), "Previously recruited, 0 people")
end)
