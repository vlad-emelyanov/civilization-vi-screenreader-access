-- KeyNavSetup leader list: "Leader, Civilization" wording and the Space detail (civ ability, leader ability, uniques); NBSP cleaning.
stub("engine")
include("ScreenReader")
include("KeyNavSetup")

test("leader entry names the civilization", function()
	eq(KeyNavSetup_LeaderOptionName("Pericles", { CivilizationName = "Greece" }), "Pericles, Greece")
end)

test("random entries and names that hold the civilization stay as they are", function()
	eq(KeyNavSetup_LeaderOptionName("Random", { CivilizationName = "LOC_RANDOM_CIVILIZATION" }), "Random")
	eq(KeyNavSetup_LeaderOptionName("Random", nil), "Random")
	eq(KeyNavSetup_LeaderOptionName("Eleanor of Aquitaine (England)", { CivilizationName = "England" }), "Eleanor of Aquitaine (England)")
end)

test("detail: one line each, uniques by icon", function()
	local text = KeyNavSetup_LeaderDetail({
		CivilizationName = "Greece",
		CivilizationAbility = { Name = "Plato's Republic", Description = "+1 slot." },
		LeaderAbility = { Name = "Surrounded by Glory", Description = "Culture from districts." },
		Uniques = {
			{ Name = "Hoplite", Description = "Unique ancient melee unit. Strength 25.", Icon = "ICON_UNIT_GREEK_HOPLITE" },
			{ Name = "Acropolis", Description = "Unique district.[NEWLINE]+1 culture.", Icon = "ICON_DISTRICT_ACROPOLIS" },
		},
	})
	eq(text, "Civilization ability: Plato's Republic: +1 slot. Leader ability: Surrounded by Glory: Culture from districts. "
		.. "Unique unit: Hoplite: Unique ancient melee unit. Strength 25. Unique district: Acropolis: Unique district. +1 culture.")
end)

test("detail: nothing for random", function()
	eq(KeyNavSetup_LeaderDetail({ CivilizationName = "LOC_RANDOM_CIVILIZATION" }), nil)
	eq(KeyNavSetup_LeaderDetail(nil), nil)
end)

test("CleanTextForSpeech: no-break space, ellipsis and curly quotes become plain characters", function()
	eq(CleanTextForSpeech("you have come far." .. string.char(194, 160) .. " Now begins"), "you have come far. Now begins")
	eq(CleanTextForSpeech("water" .. string.char(226, 128, 166) .. " to the beasts"), "water... to the beasts")
	eq(CleanTextForSpeech("it" .. string.char(226, 128, 153) .. "s " .. string.char(226, 128, 156) .. "fine" .. string.char(226, 128, 157)), "it's \"fine\"")
end)
