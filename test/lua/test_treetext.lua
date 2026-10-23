-- TreeText.lua: pure text helpers of the tech / civics tree
stub("engine")
include("TreeText")

test("Turns and Ordinal", function()
	eq(TreeText_Turns(1), "1 turn")
	eq(TreeText_Turns(5), "5 turns")
	eq(TreeText_Ordinal(1), "1st")
	eq(TreeText_Ordinal(2), "2nd")
	eq(TreeText_Ordinal(3), "3rd")
	eq(TreeText_Ordinal(4), "4th")
	eq(TreeText_Ordinal(11), "11th")
	eq(TreeText_Ordinal(12), "12th")
	eq(TreeText_Ordinal(13), "13th")
	eq(TreeText_Ordinal(21), "21st")
	eq(TreeText_Ordinal(112), "112th")
end)

test("List and Era", function()
	eq(TreeText_List({ "A", "B", "C" }), "A, B, C")
	eq(TreeText_List({ "A", "B", "C", "D", "E" }, 3), "A, B, C and 2 more")
	eq(TreeText_Era("Ancient Era", 1, 8), "Ancient Era, 1 of 8 eras")
	eq(TreeText_Era("Only", 1, 1), "Only, 1 of 1 era")
end)

test("Current", function()
	eq(TreeText_Current("Researching", "Not researching anything", "Archery", 5), "Researching Archery, 5 turns")
	eq(TreeText_Current("Researching", "Not researching anything", "Archery", 0), "Researching Archery")
	eq(TreeText_Current("Researching", "Not researching anything", nil, 0), "Not researching anything")
end)

test("Item: researched, available, blocked, current, unrevealed", function()
	eq(TreeText_Item({ name = "Masonry", status = "researched" }), "Masonry, researched")
	eq(TreeText_Item({ name = "Bronze Working", status = "available", turns = 4, boosted = true }), "Bronze Working, available, 4 turns, boosted")
	eq(TreeText_Item({ name = "Bronze Working", status = "available", turns = 1, boosted = false }), "Bronze Working, available, 1 turn")
	eq(TreeText_Item({ name = "Iron Working", status = "blocked", turns = 9, needs = { "Bronze Working" } }), "Iron Working, 9 turns, needs Bronze Working")
	eq(TreeText_Item({ name = "Currency", status = "blocked", turns = 12, needs = { "Writing", "Mining" } }), "Currency, 12 turns, needs Writing and Mining")
	eq(TreeText_Item({ name = "Archery", status = "current", turns = 2, currentWord = "currently researching" }), "Archery, currently researching, 2 turns")
	eq(TreeText_Item({ name = "Code of Laws", status = "current", turns = 6, currentWord = "in progress", queuePos = 1 }), "Code of Laws, in progress, 6 turns")
	eq(TreeText_Item({ name = "Whatever", status = "unrevealed" }), "Not revealed yet")
end)

test("Item: queue position", function()
	eq(TreeText_Item({ name = "Mining", status = "available", turns = 3, queuePos = 2 }), "Mining, available, 3 turns, queued 2nd")
	eq(TreeText_Item({ name = "Iron Working", status = "blocked", turns = 9, needs = { "Bronze Working" }, queuePos = 3 }),
		"Iron Working, 9 turns, needs Bronze Working, queued 3rd")
end)

test("Unlocks grouped by kind in a fixed order", function()
	eq(TreeText_Unlocks({}), "Unlocks nothing")
	eq(TreeText_Unlocks({
		{ kind = "KIND_BUILDING", name = "Barracks" }, { kind = "KIND_UNIT", name = "Archer" },
		{ kind = "KIND_UNIT", name = "Slinger" }, { kind = "KIND_WONDER", name = "Pyramids" },
		{ kind = "KIND_SOMETHING", name = "Odd" }, { kind = "KIND_GOVERNMENT", name = "Chiefdom" },
	}), "Unlocks Governments: Chiefdom. Units: Archer, Slinger. Buildings: Barracks. Wonders: Pyramids. Also: Odd")
end)

test("Detail", function()
	local text = TreeText_Detail({
		name = "Archery", statusText = "Archery, available, 5 turns, boosted", cost = 40, progress = 12, rate = 4.2, rateWord = "science",
		unlocks = { { kind = "KIND_UNIT", name = "Archer" } },
		boost = { word = "Eureka", text = "Kill a unit with a Slinger", done = false },
		prereqs = { "Mining" }, leads = { "Bronze Working", "The Wheel" },
	})
	eq(text, "Archery, available, 5 turns, boosted. Cost 40 science, 12 done. You make 4.2 per turn. Unlocks Units: Archer. " ..
		"Eureka, not done yet: Kill a unit with a Slinger. Requires Mining. Leads to Bronze Working, The Wheel")
end)

test("Detail: researched, no prerequisites, boost done, no yield", function()
	eq(TreeText_Detail({ name = "Pottery", statusText = "Pottery, researched", unlocks = {}, prereqs = {}, leads = {} }),
		"Pottery, researched. Unlocks nothing. No prerequisites")
	local text = TreeText_Detail({ name = "X", statusText = "X, available", cost = 20, rate = 0, rateWord = "culture", unlocks = {},
		boost = { word = "Inspiration", text = "Build a Monument", done = true }, prereqs = { "Y" } })
	contains(text, "You make no culture")
	contains(text, "Inspiration done: Build a Monument")
end)

test("Queue read back", function()
	eq(TreeText_Queue("Target", "Iron Working", { "Bronze Working", "Iron Working" }, 13), "Target: Iron Working, path: Bronze Working, Iron Working, 13 turns")
	eq(TreeText_Queue("Target", "Archery", { "Archery" }, 5), "Target: Archery, 5 turns")
	eq(TreeText_Queue("Added to queue", "Mining", { "Archery", "Mining" }, 0), "Added to queue: Mining, path: Archery, Mining")
end)

test("Group by era in tree order", function()
	local eras = TreeText_Group({
		{ key = "c", name = "Classical B", era = 1, eraName = "Classical Era", column = 2, row = 0 },
		{ key = "a2", name = "Zeta", era = 0, eraName = "Ancient Era", column = 1, row = 1 },
		{ key = "a1", name = "Beta", era = 0, eraName = "Ancient Era", column = 1, row = -1 },
		{ key = "a0", name = "Alpha", era = 0, eraName = "Ancient Era", column = 0, row = 3 },
		{ key = "c0", name = "Classical A", era = 1, eraName = "Classical Era", column = 1, row = 0 },
		{ key = "a3", name = "Aardvark", era = 0, eraName = "Ancient Era", column = 1, row = 1 },
	})
	eq(#eras, 2)
	eq(eras[1].name, "Ancient Era")
	local keys = {}
	for _, e in ipairs(eras[1].items) do keys[#keys + 1] = e.key end
	eq(table.concat(keys, ","), "a0,a1,a3,a2")		-- column, then row, then name
	eq(eras[2].items[1].key, "c0")
end)

test("Match: prefix before substring, case-insensitive", function()
	local entries = {
		{ key = "1", name = "Animal Husbandry" }, { key = "2", name = "Archery" }, { key = "3", name = "Bronze Working" },
		{ key = "4", name = "Iron Working" },
	}
	eq(TreeText_Match(entries, "arch").key, "2")
	eq(TreeText_Match(entries, "  ARCH  ").key, "2")
	eq(TreeText_Match(entries, "working").key, "3")		-- first in order
	eq(TreeText_Match(entries, "ron").key, "3")			-- bronze contains it earlier than iron? "Bronze" has "ron", Iron has "ron"
	eq(TreeText_Match(entries, "iron").key, "4")			-- prefix wins over the earlier substring hit
	eq(TreeText_Match(entries, "zzz"), nil)
	eq(TreeText_Match(entries, ""), nil)
	eq(TreeText_Match(entries, nil), nil)
end)
