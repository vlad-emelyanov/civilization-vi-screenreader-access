-- RankingsText.lua: wording of the World Rankings lines
stub("engine")
include("RankingsText")

test("ordinals", function()
	eq(RankingsText_Ordinal(1), "first")
	eq(RankingsText_Ordinal(3), "third")
	eq(RankingsText_Ordinal(10), "10th")
	eq(RankingsText_Ordinal(11), "11th")
	eq(RankingsText_Ordinal(12), "12th")
	eq(RankingsText_Ordinal(21), "21st")
end)

test("count and list joins", function()
	eq(RankingsText_Count(1, "point", "points"), "1 point")
	eq(RankingsText_Count(0, "point", "points"), "0 points")
	eq(RankingsText_And({}), "")
	eq(RankingsText_And({ "A" }), "A")
	eq(RankingsText_And({ "A", "B" }), "A and B")
	eq(RankingsText_And({ "A", "B", "C" }), "A, B and C")
	eq(RankingsText_Join({ "a", "", "b" }, ", "), "a, b")
end)

test("clean turns icons into words and newlines into stops", function()
	eq(RankingsText_Clean("[ICON_CheckmarkBlue]Build Spaceport[NEWLINE][ICON_Bolt]Research Rocketry"),
		"done: Build Spaceport. not yet: Research Rocketry")
	eq(RankingsText_Clean(nil), "")
	eq(RankingsText_Clean("[ICON_Science] Science per turn: 12"), "Science per turn: 12")
end)

test("percent", function()
	eq(RankingsText_Percent(1, 4), 25)
	eq(RankingsText_Percent(0, 0), 0)
	eq(RankingsText_Percent(2, 3), 67)
end)

test("score line and label", function()
	eq(RankingsText_ScoreLine(1, "Phoenicia", 412), "1. Phoenicia, 412 points")
	eq(RankingsText_ScoreLine(2, RankingsText_Label("Rome", true), 1), "2. You (Rome), 1 point")
end)

test("overview line says our place unless we lead", function()
	eq(RankingsText_OverviewLine("Science Victory", "Dido leading", 3, false), "Science Victory: Dido leading. You are in third place")
	eq(RankingsText_OverviewLine("Science Victory", "You are leading", 1, true), "Science Victory: You are leading")
	eq(RankingsText_OverviewLine("Science Victory", "Dido leading", nil, false), "Science Victory: Dido leading")
	eq(RankingsText_OverviewLine("Culture Victory", "Victory Not Completable", nil, false), "Culture Victory: Victory Not Completable")
end)

test("overview detail numbers the entries", function()
	eq(RankingsText_OverviewDetail({ { label = "Dido", summary = "Tourism per turn: 3" }, { label = "You (Rome)", summary = "" } }),
		"1. Dido: Tourism per turn: 3. 2. You (Rome)")
end)

test("position of the local entry", function()
	local list = { { id = 4 }, { id = 0 }, { id = 2 } }
	eq(RankingsText_PositionOf(list, function(e) return e.id == 0 end), 2)
	eq(RankingsText_PositionOf(list, function(e) return e.id == 9 end), nil)
end)

test("science", function()
	local stages = { { name = "Earth satellite", progress = 100, total = 100 }, { name = "Moon landing", progress = 40, total = 100 },
		{ name = "Mars colony", progress = 0, total = 300 } }
	eq(RankingsText_Science("Rome", stages, true), "Rome: 1 of 3 milestones done, next: Moon landing 40 percent")
	eq(RankingsText_Science("Rome", stages, false), "Rome: 1 of 3 milestones done, next: Moon landing 40 percent, no spaceport")
	eq(RankingsText_Science("Dido", { { progress = 0, total = 0 } }, true), "Dido: 0 of 1 milestones done, next: milestone 1 0 percent")
	eq(RankingsText_Science("Dido", { { name = "A", progress = 5, total = 5 } }, true), "Dido: 1 of 1 milestones done")
end)

test("culture", function()
	eq(RankingsText_Culture("Dido", 3, 56, 12, 25, nil), "Dido: 3 of 56 visiting tourists needed, 12 domestic tourists, victory in 25 turns")
	eq(RankingsText_Culture("Dido", 3, 56, 1, 0, 1), "Dido: 3 of 56 visiting tourists needed, 1 domestic tourist, 1 of your tourists visits them")
	eq(RankingsText_Culture("Dido", 3, 56, 1, -1, 4), "Dido: 3 of 56 visiting tourists needed, 1 domestic tourist, 4 of your tourists visit them")
end)

test("domination", function()
	eq(RankingsText_Domination("Rome", true, {}), "Rome: holds its original capital, no capitals captured")
	eq(RankingsText_Domination("Rome", false, { "Dido", "Gorgo" }), "Rome: has lost its original capital, captured 2 capitals: Dido and Gorgo")
end)

test("religion", function()
	eq(RankingsText_Religion("Rome", "Judaism", {}, 6), "Rome: founded Judaism, converted 0 of 6 civilizations")
	eq(RankingsText_Religion("Rome", "Judaism", { "Dido", "You" }, 6), "Rome: founded Judaism, converted 2 of 6 civilizations: Dido and You")
end)

test("diplomatic and tab lines", function()
	eq(RankingsText_Diplomatic("Rome", 4, 20), "Rome: 4 of 20 diplomatic victory points")
	eq(RankingsText_Tab("Score", 2, 7), "Score, 2 of 7 tabs")
	eq(RankingsText_Tab("Overall", 1, 1), "Overall, 1 of 1 tab")
end)
