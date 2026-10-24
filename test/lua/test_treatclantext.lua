-- TreatClanText.lua: wording of the Treat With Clan popup
stub("engine")
include("TreatClanText")

test("opening: header, subheader, count, first line", function()
	eq(TreatClanText_Opening("Treat With Badger Claw Clan", "Melee Open. City-State Conversion: 20+ Turns", 3, "Hire: 1 unit"),
		"Treat With Badger Claw Clan. Melee Open. City-State Conversion: 20+ Turns. 3 options. Hire: 1 unit")
	eq(TreatClanText_Opening("Treat With X Clan", "", 1, nil), "Treat With X Clan. 1 option")
	eq(TreatClanText_Opening("", nil, 2, nil), "Treat with a clan. 2 options")
end)

test("target line with cost and affordability", function()
	eq(TreatClanText_Target("Rome - Trajan", 120, 200), "Target: Rome - Trajan, cost 120 gold")
	eq(TreatClanText_Target("Rome - Trajan", 120, 50), "Target: Rome - Trajan, cost 120 gold, not enough gold")
	eq(TreatClanText_Target("Rome - Trajan", 0, 50), "Target: Rome - Trajan, cost unknown, cannot be incited")
	eq(TreatClanText_Target("Rome - Trajan", nil, 50), "Target: Rome - Trajan, cost unknown, cannot be incited")
end)

test("a plain option is label and description", function()
	local item = TreatClanText_Item{ id = "Hire", label = "Hire", description = "Hire the clan for 5 turns" }
	eq(item.text, "Hire: Hire the clan for 5 turns")
	eq(item.choosable, true)
end)

test("a disabled option says unavailable with the failure reasons and Enter repeats them", function()
	local item = TreatClanText_Item{ id = "Bribe", label = "Bribe", description = "Pay 100 gold. Not enough gold", reasons = "Not enough gold", disabled = true }
	eq(item.text, "Bribe, unavailable: Not enough gold")
	eq(item.reason, "Unavailable: Not enough gold")
	eq(item.choosable, false)
	local bare = TreatClanText_Item{ id = "Bribe", label = "Bribe", description = "Only the description", reasons = "", disabled = true }
	eq(bare.text, "Bribe, unavailable: Only the description")
end)

test("incite: choose a target first, then the cost, then not enough gold", function()
	local base = { id = "Incite", label = "Incite", description = "Incite the clan", incite = { canStart = true } }
	local item = TreatClanText_Item(base)
	eq(item.text, "Incite, choose a target with Left and Right")
	eq(item.choosable, false)
	base.incite.target = { label = "Rome - Trajan", cost = 120, balance = 200 }
	item = TreatClanText_Item(base)
	eq(item.text, "Incite: Incite the clan. Target: Rome - Trajan, cost 120 gold")
	eq(item.choosable, true)
	base.incite.target.balance = 10
	item = TreatClanText_Item(base)
	eq(item.text, "Incite, unavailable: Target: Rome - Trajan, cost 120 gold, not enough gold")
	eq(item.choosable, false)
	base.incite.target.cost = 0
	eq(TreatClanText_Item(base).choosable, false)
	base.incite = { canStart = false }
	base.disabled = true
	base.reasons = "No target available"
	eq(TreatClanText_Item(base).text, "Incite, unavailable: No target available")
end)

test("results after Enter", function()
	eq(TreatClanText_Result("Hire", "Badger Claw"), "Hired from Badger Claw clan")
	eq(TreatClanText_Result("Bribe", "Badger Claw"), "Bribed Badger Claw clan")
	eq(TreatClanText_Result("Ransom", "Badger Claw"), "Ransom paid to Badger Claw clan")
	eq(TreatClanText_Result("Incite", "Badger Claw", "Rome - Trajan"), "Incited Badger Claw clan against Rome - Trajan")
	eq(TreatClanText_Result("Close", "Badger Claw"), "Closed")
	eq(TreatClanText_Result("Hire", nil), "Hired from the clan")
end)
