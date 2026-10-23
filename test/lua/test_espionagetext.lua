-- EspionageText.lua: espionage overview and chooser text
stub("engine")
include("EspionageText")

test("header", function()
	eq(EspionageText_Header{ spies = 2, capacity = 3, idle = 1 }, "Espionage: 2 of 3 spies, 1 awaiting orders")
	eq(EspionageText_Header{ spies = 0, capacity = 1, idle = 0 }, "Espionage: 0 of 1 spy")
	eq(EspionageText_Header{ spies = 1, idle = 0 }, "Espionage: 1 spy, 0 awaiting orders")
end)

test("spy states", function()
	eq(EspionageText_Spy{ name = "Ana", rank = "Recruit", state = "idle", city = "Rome" }, "Spy Ana, Recruit, in Rome, awaiting orders")
	eq(EspionageText_Spy{ name = "Ana", rank = "Agent", state = "mission", city = "Thebes", mission = "Counterspy, Campus", turns = 3 },
		"Spy Ana, Agent, in Thebes, Counterspy, Campus, 3 turns left")
	eq(EspionageText_Spy{ name = "Ana", state = "travel", destination = "Thebes", turns = 1 }, "Spy Ana, travelling to Thebes, 1 turn left")
	eq(EspionageText_Spy{ name = "Ana", rank = "Recruit", state = "captured", capturedBy = "Egypt" }, "Spy Ana, Recruit, captured by Egypt")
end)

test("city and history and enemy spy", function()
	eq(EspionageText_City{ name = "Rome", owner = "yours", capital = true, spies = { "Ana" }, boostTurns = 2, districts = { "Campus", "Holy Site" } },
		"Rome, yours, capital, your spy Ana, gain sources boost, 2 turns left, districts: Campus, Holy Site")
	eq(EspionageText_City{ name = "Thebes", districts = {} }, "Thebes")
	eq(EspionageText_History{ name = "Ana", rank = "Agent", mission = "Steal tech boost", turnsAgo = 3, success = true, description = "Stole Writing." },
		"Ana, Agent, Steal tech boost, 3 turns ago, success. Stole Writing.")
	eq(EspionageText_History{ name = "Ana", mission = "Siphon funds", turnsAgo = 0, success = false, status = "Spy killed" },
		"Ana, Siphon funds, this turn, failure, Spy killed")
	eq(EspionageText_EnemySpy{ name = "Boris", civ = "Egypt", canTrade = true }, "Captured enemy spy Boris, Egypt, Enter to offer a trade")
end)

test("destination and mission", function()
	eq(EspionageText_Destination{ name = "Thebes", owner = "Egypt", turns = 4 }, "Thebes, Egypt, 4 turns")
	eq(EspionageText_Destination{ name = "Cairo", owner = "Egypt", capital = true, turns = 1 }, "Cairo, Egypt, capital, 1 turn")
	eq(EspionageText_Mission{ name = "Steal tech boost", chance = 75, turns = 8 }, "Steal tech boost, 75 percent success, 8 turns")
	eq(EspionageText_Mission{ name = "Sabotage", district = "Industrial Zone", chance = 60, turns = 5 }, "Sabotage, Industrial Zone, 60 percent success, 5 turns")
	eq(EspionageText_Mission{ name = "Counterspy", district = "Campus", turns = 3 }, "Counterspy, Campus, 3 turns")
	eq(EspionageText_Mission{ name = "Siphon", reason = "needs a Commercial Hub" }, "Siphon, unavailable: needs a Commercial Hub")
end)

test("outcomes", function()
	eq(EspionageText_Outcomes{ success = 75, failure = 20, lost = 5 }, "75 percent success, 20 percent failure, 5 percent spy captured or killed")
	eq(EspionageText_Outcomes{ success = 100, failure = 0, lost = 0 }, "100 percent success")
end)
