-- CombatText.lua: attack preview wording (strengths, modifier lines).
stub("engine")
include("CombatText")

test("strength phrase", function()
	eq(CombatText_StrengthPhrase("Strength", 20, 17), "Strength 20 against 17")
	eq(CombatText_StrengthPhrase("Ranged strength", 25, 0), "Ranged strength 25")
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
