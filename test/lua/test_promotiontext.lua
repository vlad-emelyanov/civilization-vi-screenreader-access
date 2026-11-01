-- PromotionText.lua: promotion tree texts
stub("engine")
include("PromotionText")

local battlecry = { name = "Battlecry", desc = "+7 combat strength vs melee", tier = 1, state = "available" }

test("item with state", function()
	eq(PromotionText_Item(battlecry), "Battlecry: +7 combat strength vs melee, tier 1, available")
	eq(PromotionText_Item({ name = "Tortoise", desc = "x", state = "have" }), "Tortoise: x, have")
end)

test("locked lists prerequisites with or", function()
	local p = { name = "Square", desc = "d", tier = 2, state = "locked", needs = { "Tortoise", "Charge" } }
	eq(PromotionText_Item(p), "Square: d, tier 2, locked: needs Tortoise or Charge")
	eq(PromotionText_Reason(p), "Square is locked, needs Tortoise or Charge")
	eq(PromotionText_Reason({ name = "S", state = "locked", needs = {} }), "S is locked")
end)

test("reasons", function()
	eq(PromotionText_Reason(battlecry), nil)
	eq(PromotionText_Reason({ name = "A", state = "have" }), "Already have A")
	eq(PromotionText_Reason({ name = "A", state = "unavailable" }), "A can't be taken now")
	eq(PromotionText_Item({ name = "A", desc = "", state = "unavailable" }), "A, not available now")
end)

test("detail and opening", function()
	eq(PromotionText_Detail(battlecry), "Battlecry, tier 1. +7 combat strength vs melee. available")
	eq(PromotionText_Opening("Swordsman", 2, "Battlecry: x, available", 1, 5), "Promote Swordsman: 2 available. Battlecry: x, available, 1 of 5")
	eq(PromotionText_Opening("Swordsman", 0), "Promote Swordsman: 0 available")
	eq(PromotionText_Opening("Swordsman", 2, "Battlecry: x, available", 1, 5, true), "Promote Swordsman: 2 available, promoting uses the unit's moves. Battlecry: x, available, 1 of 5")
	eq(PromotionText_Done("Battlecry"), "Promoted: Battlecry")
end)

test("promotion key on a random-list unit and with a spy list open", function()
	eq(PromotionText_Choices("Spy", { "Cover Story", "Disguise", "Smooth Talker" }, "Tab"), "Promote Spy: choose Cover Story, Disguise or Smooth Talker. Tab opens the list")
	eq(PromotionText_Choices("Spy", { "Disguise" }, "Tab"), "Promote Spy: choose Disguise. Tab opens the list")
	eq(PromotionText_ListOpen(false, "Escape"), "Close the mission list first, Escape closes it")
	eq(PromotionText_ListOpen(true, "Escape"), "Close the destination list first, Escape closes it")
end)
