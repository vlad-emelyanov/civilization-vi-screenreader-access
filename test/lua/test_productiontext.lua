-- ProductionText.lua: wording of the production panel opening line and the replace note
stub("engine")
include("ProductionText")

test("current production line", function()
	eq(ProductionText_Current("Coal Power Plant", "3 turns"), "Currently building Coal Power Plant, 3 turns")
	eq(ProductionText_Current("Coal Power Plant", nil), "Currently building Coal Power Plant")
end)

test("replace note", function()
	eq(ProductionText_Replaces("Renaissance Walls", "Coal Power Plant", "Renaissance Walls"), "Renaissance Walls, replaces Coal Power Plant")
	eq(ProductionText_Replaces("Walls", nil, "Walls"), "Walls")
	eq(ProductionText_Replaces("Walls", "Walls", "Walls"), "Walls")
end)

test("identity across tabs", function()
	eq(ProductionText_Identity("buy:unit:12"), "unit:12")
	eq(ProductionText_Identity("unit:12"), "unit:12")
	eq(ProductionText_Identity(nil), nil)
end)
