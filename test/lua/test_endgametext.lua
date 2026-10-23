-- EndGameText.lua: wording of the end-game screen
stub("engine")
include("EndGameText")

test("sentence case", function()
	eq(EndGameText_Sentence("DOMINATION VICTORY"), "Domination victory")
	eq(EndGameText_Sentence(""), "")
	eq(EndGameText_Sentence(nil), "")
end)

test("local victory", function()
	eq(EndGameText_Summary({ Head = "VICTORY", TypeHeader = "SCIENCE VICTORY", WinnerName = "Rome", IsWinnerLocalPlayer = true, Blurb = "You reached Mars." }),
		"Victory: Science victory, you, Rome. You reached Mars.")
end)

test("someone else wins", function()
	eq(EndGameText_Summary({ Head = "DEFEAT", TypeHeader = "Culture Victory", WinnerName = "Egypt", IsWinnerLocalPlayer = false, DefeatedName = "Rome" }),
		"Defeat: Culture victory, won by Egypt. Defeated: Rome")
end)

test("plain defeat", function()
	eq(EndGameText_Summary({ Head = "DEFEAT", DefeatedName = "Rome", WinnerName = "" }), "Defeat: Rome")
	eq(#EndGameText_Lines({ Head = "DEFEAT", WinnerName = "" }), 1)
end)

test("rank lines", function()
	eq(EndGameText_RankLine(3, "Napoleon", "350", false), "3. Napoleon, score 350")
	eq(EndGameText_RankLine(1, "Trajan", "812", true), "1. Trajan, score 812, you are here")
end)

test("graph lines sorted by the last value, city-states skipped", function()
	local infos = { { Id = 0, Name = "A" }, { Id = 1, Name = "B" }, { Id = 2, Name = "C", IsMinor = true } }
	local data = { [0] = { [1] = 5, [2] = 10 }, [1] = { [1] = 7, [2] = 20.5 }, [2] = { [1] = 99 } }
	local rows = EndGameText_GraphLines(infos, data, function(i) return i.Name end, false)
	eq(#rows, 2)
	eq(rows[1].text, "B: 20.5")
	eq(rows[2].text, "A: 10")
	eq(#EndGameText_GraphLines(infos, data, function(i) return i.Name end, true), 3)
	eq(#EndGameText_GraphLines(infos, nil, function(i) return i.Name end, true), 0)
end)
