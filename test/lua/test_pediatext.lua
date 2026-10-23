-- PediaText.lua: wording of the Civilopedia speech
stub("engine")
include("PediaText")

test("clean drops bullets, icons and newlines", function()
	eq(PediaText_Clean("[ICON_BULLET]Armed unit[NEWLINE]Second"), "Armed unit. Second")
	eq(PediaText_Clean(nil), "")
end)

test("stat line", function()
	eq(PediaText_StatLine("Melee Strength", 20), "Melee Strength 20")
	eq(PediaText_StatLine("Base Cost:", "40 Production"), "Base Cost 40 Production")
	eq(PediaText_StatLine("", 3), "3")
end)

test("link line and counts", function()
	eq(PediaText_LinkLine("Spearman"), "Link: Spearman")
	eq(PediaText_Count(1, "line", "lines"), "1 line")
	eq(PediaText_Count(12, "line", "lines"), "12 lines")
end)

test("openings", function()
	eq(PediaText_Opening("Concepts", 1, 18), "Civilopedia. Concepts, 1 of 18 sections")
	eq(PediaText_Section("Units", 7, 18), "Units, 7 of 18 sections")
	eq(PediaText_PageOpening("Warrior", { { text = "Melee Strength 20" }, { text = "Cost" } }), "Warrior page, 2 lines. Melee Strength 20")
	eq(PediaText_PageOpening("Warrior", {}), "Warrior page, no text")
end)

test("join from a line adds stops", function()
	local lines = { { text = "Traits" }, { text = "Link: Spearman" }, { text = "Fast unit." } }
	eq(PediaText_JoinFrom(lines, 2), "Link: Spearman. Fast unit.")
	eq(PediaText_JoinFrom(lines, 1), "Traits. Link: Spearman. Fast unit.")
end)

test("entries carry group names as sections", function()
	local pages = { { PageId = "A", TabName = "Alpha", PageGroupId = "G1" }, { PageId = "B", TabName = "Beta" } }
	local items = PediaText_Entries("UNITS", pages, function(p) return "Ancient era" end)
	eq(#items, 2)
	eq(items[1].key, "UNITS::A")
	eq(items[1].text, "Alpha")
	eq(items[1].section, "Ancient era")
	eq(items[2].section, nil)
end)

test("search items dedupe and name the section", function()
	local items = PediaText_SearchItems({ { key = "UNITS|U1", name = "Warrior" }, { key = "UNITS|U1", name = "Warrior" }, { key = "CONCEPTS|C1", name = "War" } },
		function(id) return id == "UNITS" and "Units" or nil end, 10)
	eq(#items, 2)
	eq(items[1].text, "Warrior, Units")
	eq(items[1].pageId, "U1")
	eq(items[2].text, "War")
end)
