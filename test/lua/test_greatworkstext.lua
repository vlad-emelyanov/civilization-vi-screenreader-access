-- GreatWorksText.lua: wording of the Great Works screen lines
stub("engine")
include("GreatWorksText")
include("ScreenReader")

-- the module returns [KEY:..] tokens; compare the keyboard wording (the console app expands them at speech time)
local eqRaw = eq
local function eq(actual, expected) if type(actual) == "string" then actual = actual:gsub("%[KEY:([^%]|]+)|?[^%]]*%]", "%1") end eqRaw(actual, expected) end

local odyssey = { name = "The Odyssey", creator = "Homer", typeName = "Writing",
	yields = { { label = "culture", value = 2 }, { label = "tourism", value = 2 }, { label = "faith", value = 0 } } }

test("slot words", function()
	eq(GreatWorksText_SlotWord("GREATWORKSLOT_ART"), "art")
	eq(GreatWorksText_SlotWord("GREATWORKSLOT_FOO_BAR"), "foo bar")
	eq(GreatWorksText_SlotWord(nil), "great work")
end)

test("work line skips zero yields", function()
	eq(GreatWorksText_Work(odyssey), "'The Odyssey' by Homer, writing, plus 2 culture, plus 2 tourism")
	eq(GreatWorksText_Work({ name = "Relic", yields = {} }), "'Relic'")
end)

test("theming status", function()
	eq(GreatWorksText_Theming(nil), nil)
	eq(GreatWorksText_Theming({ themed = true, numThemed = 3, numSlots = 3 }), "theming bonus active")
	eq(GreatWorksText_Theming({ themed = false, numThemed = 2, numSlots = 3 }), "2 of 3 for theming bonus")
	eq(GreatWorksText_Theming({ themed = false, numThemed = 0, numSlots = 1 }), nil)
	eq(GreatWorksText_Header("Rome", "Museum", { themed = false, numThemed = 2, numSlots = 3 }), "Rome, Museum, 2 of 3 for theming bonus")
	eq(GreatWorksText_Header("Rome", "Amphitheater", nil), "Rome, Amphitheater")
end)

test("slot lines", function()
	eq(GreatWorksText_Slot("art", 2, 3, nil), "art slot 2, empty")
	eq(GreatWorksText_Slot("writing", 1, 1, nil), "writing slot, empty")
	eq(GreatWorksText_Slot("writing", 1, 1, odyssey), "'The Odyssey' by Homer, writing, plus 2 culture, plus 2 tourism")
	eq(GreatWorksText_Slot("writing", 2, 3, odyssey), "slot 2 of 3, 'The Odyssey' by Homer, writing, plus 2 culture, plus 2 tourism")
end)

test("destinations", function()
	eq(GreatWorksText_Destination("art", 2, 3, nil), "art slot 2, empty")
	eq(GreatWorksText_Destination("art", 1, 3, "Hamlet"), "slot 1 of 3, holds 'Hamlet', would swap")
	eq(GreatWorksText_Destination("art", 1, 1, "Hamlet"), "art slot, holds 'Hamlet', would swap")
end)

test("summary and moving", function()
	eq(GreatWorksText_Summary(5, 3, 12), "Great Works: 5 works, 3 empty slots, tourism plus 12")
	eq(GreatWorksText_Summary(1, 1, 0), "Great Works: 1 work, 1 empty slot")
	eq(GreatWorksText_Pickup("The Odyssey", 4), "Picked up The Odyssey. 4 slots available. Enter to place, Escape to cancel")
	eq(GreatWorksText_Moved("The Odyssey", "Florence", "Amphitheater"), "Moved The Odyssey to Florence, Amphitheater")
	eq(GreatWorksText_Moved("The Odyssey", "Florence", "Amphitheater", "Hamlet"),
		"Swapped The Odyssey with Hamlet, The Odyssey is now in Florence, Amphitheater")
end)

test("showcase", function()
	eq(GreatWorksText_Showcase({ name = "The Odyssey", lines = { "Created by Homer.", "Ancient Era Writing" }, quote = "Sing, Muse" }),
		"New great work: The Odyssey. Created by Homer. Ancient Era Writing. Sing, Muse. Enter to view your great works, Escape to close")
	eq(GreatWorksText_Showcase({ name = "Mona Lisa", lines = {}, gallery = true, position = 2, count = 5 }),
		"Great work: Mona Lisa. 2 of 5. Left and Right for the next work. Escape to close")
end)

test("key hints are SRKey tokens", function()
	eqRaw(GreatWorksText_Pickup("The Odyssey", 4), "Picked up The Odyssey. 4 slots available. [KEY:Enter] to place, [KEY:Escape] to cancel")
end)
