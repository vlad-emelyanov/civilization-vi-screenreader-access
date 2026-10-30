-- CombatText.lua: attack preview wording (strengths, modifier lines).
stub("engine")
include("CombatText")

test("strength phrase", function()
	eq(CombatText_StrengthPhrase("Strength", 20, 17), "Strength 20 against 17")
	eq(CombatText_StrengthPhrase("Ranged strength", 25, 0), "Ranged strength 25 against no defense")
	eq(CombatText_StrengthPhrase("Strength", nil, 3), nil)
end)

test("totals never go below zero", function()
	eq(CombatText_Total(10, -15), 0)
	eq(CombatText_Total(20, 3), 23)
end)

test("signed numbers are spoken", function()
	eq(CombatText_ModifierLine("+2 Flanking"), "plus 2 Flanking")
	eq(CombatText_ModifierLine("-3 Across a river"), "minus 3 Across a river")
	eq(CombatText_ModifierLine("Fortified"), "Fortified")
end)

test("modifier sides", function()
	eq(CombatText_Modifiers({"+2 Flanking", "-3 River"}, {"+3 Hills", "+2 Fortified"}),
		"Your modifiers: plus 2 Flanking, minus 3 River. Their modifiers: plus 3 Hills, plus 2 Fortified")
	eq(CombatText_Modifiers({}, {"+3 Hills"}), "Their modifiers: plus 3 Hills. No modifiers for you")
	eq(CombatText_Modifiers({"+1 X"}, {}), "Your modifiers: plus 1 X. No modifiers for them")
	eq(CombatText_Modifiers({}, {}), "No modifiers on either side")
end)

test("the target line follows the target", function()
	eq(CombatText_InfoFollowsTarget("valid target, Strength 20 against 17"), true)
	eq(CombatText_InfoFollowsTarget("attack, 1 turn, Strength 20 against 17"), true)
	eq(CombatText_InfoFollowsTarget("would declare war on Rome, attack, 1 turn"), true)
	eq(CombatText_InfoFollowsTarget("no target"), false)
	eq(CombatText_InfoFollowsTarget("unreachable"), false)
	eq(CombatText_InfoFollowsTarget(nil), false)
end)

test("opening line leads with the target, the hints go last", function()
	eq(CombatText_OpeningLine("Ranged attack", "Rome, Rome city, 2 tiles east, valid target, Ranged strength 20 against 17", "X next target, Enter attacks, Escape cancels"),
		"Ranged attack: Rome, Rome city, 2 tiles east, valid target, Ranged strength 20 against 17. X next target, Enter attacks, Escape cancels")
	eq(CombatText_OpeningLine("Ranged attack", nil, "X next target"), "Ranged attack. X next target")
end)

test("position in the target list", function()
	eq(CombatText_PositionInList(1, 1), nil)
	eq(CombatText_PositionInList(2, 4), "2 of 4")
	eq(CombatText_PositionInList(4, 4), "4 of 4, X wraps to the first")
end)
