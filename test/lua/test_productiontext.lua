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

local function mk(key, section, extra)
	local t = { key = key, text = key, section = section, choosable = true }
	for k, v in pairs(extra or {}) do t[k] = v end
	return t
end
local function keys(list)
	local out = {}
	for _, i in ipairs(list) do table.insert(out, i.key) end
	return table.concat(out, " ")
end

test("arrange: repairs first, unavailable hidden behind a toggle", function()
	local items = {
		mk("d1", "Districts"), mk("d2", "Districts", { choosable = false }), mk("r1", "Districts", { repair = true, choosable = false }),
		mk("u1", "Units"), mk("u2", "Units", { choosable = false }), mk("r2", "Districts", { repair = true }),
	}
	local res, hidden = ProductionText_Arrange(items, false, false)
	eq(keys(res), "r1 r2 d1 u1 toggle:unavailable")
	eq(hidden, 2)
	eq(res[1].section, "Repairs")
	eq(res[5].text, "Show 2 unavailable items")
	eq(res[5].section, "Units")
	eq(res[5].choosable, true)
end)

test("arrange: shown, the hidden items follow the toggle as the section Unavailable in the old order", function()
	local items = { mk("d1", "Districts"), mk("d2", "Districts", { choosable = false }), mk("u2", "Units", { choosable = false }) }
	local res = ProductionText_Arrange(items, true, false)
	eq(keys(res), "d1 toggle:unavailable d2 u2")
	eq(res[2].text, "Hide 2 unavailable items")
	eq(res[2].section, "Unavailable")
	eq(res[2].uncounted, true)
	eq(res[3].section, "Unavailable")
	eq(res[4].section, "Unavailable")
end)

test("arrange: nothing hidden, no toggle; singular wording", function()
	local res, hidden = ProductionText_Arrange({ mk("a", "Units") }, false, false)
	eq(keys(res), "a")
	eq(hidden, 0)
	res = ProductionText_Arrange({ mk("a", "Units"), mk("b", "Units", { choosable = false }) }, false, false)
	eq(res[2].text, "Show 1 unavailable item")
end)

test("arrange: only unavailable items left, the toggle is the whole list", function()
	local res = ProductionText_Arrange({ mk("a", "Units", { choosable = false }) }, false, false)
	eq(keys(res), "toggle:unavailable")
end)

test("arrange: purchase keeps can't afford items, after the affordable ones of each section", function()
	local items = {
		mk("b1", "Buildings", { choosable = false, cantAfford = true }), mk("b2", "Buildings"), mk("b3", "Buildings", { choosable = false }),
		mk("u1", "Units", { choosable = false, cantAfford = true }), mk("u2", "Units"),
	}
	local res = ProductionText_Arrange(items, false, true)
	eq(keys(res), "b2 b1 u2 u1 toggle:unavailable")
	eq(res[5].detail, "Lists the items this city cannot buy now, with the reason")
end)

test("toggle wording", function()
	eq(ProductionText_Toggle(14, false, false).text, "Show 14 unavailable items")
	eq(ProductionText_Toggle(14, false, false).detail, "Lists the items this city cannot build now, with the reason")
	eq(ProductionText_ToggleSaid(14, true), "Showing 14 unavailable items")
	eq(ProductionText_ToggleSaid(1, true), "Showing 1 unavailable item")
	eq(ProductionText_ToggleSaid(14, false), "Unavailable items hidden")
end)

test("stack blocker names the unit of the same class", function()
	local others = { { formation = "FORMATION_CLASS_CIVILIAN", name = "Builder" }, { formation = "FORMATION_CLASS_LAND_COMBAT", name = "Archer" } }
	eq(ProductionText_StackBlocker("FORMATION_CLASS_LAND_COMBAT", "Rome", others), "Archer stands in Rome")
	eq(ProductionText_StackBlocker("FORMATION_CLASS_NAVAL", "Rome", others), nil)
	eq(ProductionText_StackBlocker(nil, "Rome", others), nil)
	eq(ProductionText_StackBlocker("FORMATION_CLASS_CIVILIAN", nil, others), "Builder stands in the city")
end)

test("corps and army rows", function()
	eq(ProductionText_FormationName("Warrior", "Corps"), "Warrior Corps")
	eq(ProductionText_FormationName("Warrior", nil), "Warrior")
	eq(ProductionText_FormationRow("Warrior Corps", "12 turns", 180, 0), "Warrior Corps, 12 turns, 180 production")
	eq(ProductionText_FormationRow("Warrior Corps", nil, 180, 40), "Warrior Corps, 40 of 180 production")
	eq(ProductionText_Identity("buy:unit:12:corps"), "unit:12:corps")
end)

test("queue item text and keys", function()
	eq(ProductionText_QueueItem("Library", true, "5 turns"), "Library, in production, 5 turns")
	eq(ProductionText_QueueItem("Library", true, nil), "Library, in production")
	eq(ProductionText_QueueItem("Library", false, "5 turns"), "Library")
	eq(ProductionText_QueueKey("b1", 2), "queue:b1:2")
end)

test("queue move target and speech", function()
	eq(ProductionText_QueueTarget(1, -1, 3), 0)
	eq(ProductionText_QueueTarget(1, 1, 3), 2)
	local t, why = ProductionText_QueueTarget(0, -1, 3)
	eq(t, nil); eq(why, "Already first")
	t, why = ProductionText_QueueTarget(2, 1, 3)
	eq(t, nil); eq(why, "Already last")
	t, why = ProductionText_QueueTarget(0, 1, 1)
	eq(why, "Already last")
	eq(ProductionText_QueueMoved("Library", 0, 3), "Library moved to 1 of 3")
end)

test("queue removal speech and focus", function()
	eq(ProductionText_QueueRemoved("Library", 2), "Library removed from the queue, 2 left")
	eq(ProductionText_QueueRemoved("Library", 0), "Library removed from the queue. Queue empty, nothing in production")
	eq(ProductionText_QueueFocusAfterRemove(1, 2), 1)
	eq(ProductionText_QueueFocusAfterRemove(2, 2), 1)
	eq(ProductionText_QueueFocusAfterRemove(0, 0), nil)
end)
