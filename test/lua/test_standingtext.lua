-- StandingText.lua: V list numbers and the Control+R standing line
stub("engine")
include("StandingText")

local function E(name, isYou, s, m, sc, c, g, f)
	return { name = name, isYou = isYou, vals = { score = s, military = m, science = sc, culture = c, gold = g, faith = f } }
end

test("ordinals", function()
	eq(StandingText_Ordinal(1), "1st"); eq(StandingText_Ordinal(2), "2nd"); eq(StandingText_Ordinal(3), "3rd")
	eq(StandingText_Ordinal(4), "4th"); eq(StandingText_Ordinal(11), "11th"); eq(StandingText_Ordinal(22), "22nd")
end)

test("numbers round and skip hidden categories", function()
	eq(StandingText_Numbers({ score = 189.6, military = 150.2, gold = 10 }), "score 190, military 150, gold 10")
	eq(StandingText_Numbers({}), "")
end)

test("list item wording", function()
	local you = E("Rome", true, 190, 150, 12, 8, 10, 3)
	eq(StandingText_ListItem(you, "You, Rome"), "You, Rome: score 190, military 150, science 12, culture 8, gold 10, faith 3")
	local jp = E("Japan", false, 212, 180, 14, 9, 6, 3)
	eq(StandingText_ListItem(jp, "Hojo, Japan, at peace"), "Hojo, Japan, at peace. Score 212, military 180, science 14, culture 9, gold 6, faith 3")
	eq(StandingText_ListItem({ vals = {} }, "Hojo, Japan, at peace"), "Hojo, Japan, at peace")
end)

test("standing line with weakest category", function()
	local es = { E("Rome", true, 190, 150, 12, 8, 10, 3), E("Japan", false, 212, 100, 14, 26, 6, 1), E("Egypt", false, 100, 90, 20, 18, 12, 2), E("Kongo", false, 50, 20, 5, 9, 1, 0) }
	eq(StandingText_Line(es, 1), "Among 4 known civilizations: score 2nd, military 1st, science 3rd, culture 4th, gold 2nd, faith 1st. Weakest: culture, Japan leads with 26 per turn")
end)

test("ties", function()
	local es = { E("Rome", true, 100, 10, 5, 5, 5, 5), E("Japan", false, 100, 10, 5, 5, 5, 5) }
	eq(StandingText_Line(es, 1), "Among 2 known civilizations: score tied 1st, military tied 1st, science tied 1st, culture tied 1st, gold tied 1st, faith tied 1st. You lead or share the lead in every category")
	local es2 = { E("Rome", true, 5, 10, 5, 5, 5, 5), E("Japan", false, 9, 10, 5, 5, 5, 5), E("Egypt", false, 5, 10, 5, 5, 5, 5) }
	eq(StandingText_Line(es2, 1):sub(1, 60), "Among 3 known civilizations: score tied 2nd, military tied 1")
end)

test("single civ and hidden categories", function()
	eq(StandingText_Line({ E("Rome", true, 1, 1, 1, 1, 1, 1) }, 1), "You have met no other civilization yet")
	local a = { name = "Rome", isYou = true, vals = { science = 5 } }
	local b = { name = "Japan", isYou = false, vals = { science = 9 } }
	eq(StandingText_Line({ a, b }, 1), "Among 2 known civilizations: science 2nd. Weakest: science, Japan leads with 9 per turn")
	eq(StandingText_Line({ { name = "R", vals = {} }, { name = "J", vals = {} } }, 1), "This game shows no standings")
end)
