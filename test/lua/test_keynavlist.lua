-- KeyNavList.lua: focus tracking by key, wrapping, sections, activation
stub("engine")
include("KeyNavList")

local function newList(items, extra)
	local state = { items = items, active = true, activated = nil, closed = false }
	local cfg = {
		build = function() return state.items end,
		isActive = function() return state.active end,
		onActivate = function(item) state.activated = item.key end,
		onClose = function() state.closed = true end,
	}
	for k, v in pairs(extra or {}) do cfg[k] = v end
	state.list = KeyNavList_Create(cfg)
	return state
end

local function abc()
	return {
		{ key = "a", text = "Alpha" }, { key = "b", text = "Beta", detail = "More about beta" }, { key = "c", text = "Gamma" },
	}
end

local function press(list, key, up)
	ClearPrinted()
	return list.HandleInput(Input{ key = key, up = up })
end

test("Open announces the title, the count and the first item", function()
	local s = newList(abc())
	ClearPrinted()
	s.list.Open("Choose")
	listeq(Spoken(), { "Choose, 3 options", "Alpha, 1 of 3" })
end)

test("Open: the title interrupts (ring presses cut the previous list), the first item does not cut the title", function()
	local s = newList(abc())
	ClearPrinted()
	s.list.Open("Choose")
	eq(Printed[1], "#SCREENREADER - Choose, 3 options")
	eq(Printed[2], "#SCREENREADER[NOINTERRUPT] - Alpha, 1 of 3")
end)

test("pad hint: once on open, only when the first item has a detail, opt-out", function()
	local s = newList({ { key = "b", text = "Beta", detail = "More" }, { key = "c", text = "Gamma", detail = "x" }, { key = "d", text = "Delta" } })
	ClearPrinted()
	s.list.Open("T")
	listeq(SpokenRaw(), { "T, 3 options", "Beta, 1 of 3[PAD:, Y for details]" })
	listeq(Spoken(), { "T, 3 options", "Beta, 1 of 3" })
	press(s.list, Keys.VK_DOWN)
	listeq(SpokenRaw(), { "Gamma, 2 of 3" })
	local n = newList(abc())
	ClearPrinted()
	n.list.Open("T")
	listeq(SpokenRaw(), { "T, 3 options", "Alpha, 1 of 3" })
	local o = newList({ { key = "b", text = "Beta", detail = function() return "More" end } }, { noDetailHint = true })
	ClearPrinted()
	o.list.Open("T")
	listeq(SpokenRaw(), { "T, 1 option", "Beta, 1 of 1" })
	local f = newList({ { key = "b", text = "Beta", detail = function() return "More" end } })
	ClearPrinted()
	f.list.Open("T")
	listeq(SpokenRaw(), { "T, 1 option", "Beta, 1 of 1[PAD:, Y for details]" })
end)

test("Open with no items", function()
	local s = newList({})
	ClearPrinted()
	s.list.Open("Choose")
	listeq(Spoken(), { "Choose, nothing available" })
end)

test("Down/Up move and wrap", function()
	local s = newList(abc())
	s.list.Open("T")
	eq(press(s.list, Keys.VK_DOWN), true)
	listeq(Spoken(), { "Beta, 2 of 3" })
	press(s.list, Keys.VK_DOWN)
	press(s.list, Keys.VK_DOWN)
	listeq(Spoken(), { "Alpha, 1 of 3" })		-- wrapped
	press(s.list, Keys.VK_UP)
	listeq(Spoken(), { "Gamma, 3 of 3" })
	press(s.list, Keys.VK_HOME)
	listeq(Spoken(), { "Alpha, 1 of 3" })
	press(s.list, Keys.VK_END)
	listeq(Spoken(), { "Gamma, 3 of 3" })
end)

test("focus follows the key when the list changes", function()
	local s = newList(abc())
	s.list.Open("T")
	press(s.list, Keys.VK_DOWN)		-- on Beta
	s.items = { { key = "x", text = "New" }, { key = "a", text = "Alpha" }, { key = "b", text = "Beta" }, { key = "c", text = "Gamma" } }
	press(s.list, Keys.VK_DOWN)
	listeq(Spoken(), { "Gamma, 4 of 4" })
end)

test("Enter acts on KeyUp only; both events are consumed", function()
	local s = newList(abc())
	s.list.Open("T")
	eq(press(s.list, Keys.VK_RETURN, false), true)
	eq(s.activated, nil)
	eq(press(s.list, Keys.VK_RETURN, true), true)
	eq(s.activated, "a")
end)

test("a vanished focus item is announced and Enter does nothing", function()
	local s = newList(abc())
	s.list.Open("T")
	press(s.list, Keys.VK_DOWN)		-- Beta
	s.items = { { key = "a", text = "Alpha" } }
	press(s.list, Keys.VK_RETURN, true)
	eq(s.activated, nil)
	listeq(Spoken(), { "Item no longer available", "Alpha, 1 of 1" })
end)

test("unchoosable items say why", function()
	local s = newList({ { key = "a", text = "Alpha", choosable = false, reason = "Not enough gold" } })
	s.list.Open("T")
	press(s.list, Keys.VK_RETURN, true)
	eq(s.activated, nil)
	listeq(Spoken(), { "Not enough gold" })
end)

test("Space reads the detail", function()
	local s = newList(abc())
	s.list.Open("T")
	press(s.list, Keys.VK_DOWN)
	press(s.list, Keys.VK_SPACE, true)
	listeq(Spoken(), { "More about beta" })
	press(s.list, Keys.VK_UP)
	press(s.list, Keys.VK_SPACE, true)
	listeq(Spoken(), { "No further details" })
end)

test("sections are spoken when they change", function()
	local s = newList({
		{ key = "a", text = "Alpha", section = "Units" }, { key = "b", text = "Beta", section = "Units" },
		{ key = "c", text = "Gamma", section = "Buildings" },
	})
	ClearPrinted()
	s.list.Open("T")
	listeq(Spoken(), { "T, 3 options", "Units: Alpha, 1 of 3" })
	press(s.list, Keys.VK_DOWN)
	listeq(Spoken(), { "Beta, 2 of 3" })
	press(s.list, Keys.VK_DOWN)
	listeq(Spoken(), { "Gamma, in Buildings, 3 of 3" })
end)

test("inactive list and keys with modifiers are not consumed", function()
	local s = newList(abc())
	s.list.Open("T")
	s.active = false
	eq(press(s.list, Keys.VK_DOWN), false)
	s.active = true
	eq(ClearPrinted() or s.list.HandleInput(Input{ key = Keys.VK_DOWN, ctrl = true }), false)
	eq(press(s.list, 65), false)
	eq(#Spoken(), 0)
end)

test("Left/Right only when horizontal; Escape only with onClose", function()
	local s = newList(abc())
	s.list.Open("T")
	eq(press(s.list, Keys.VK_RIGHT), false)
	eq(press(s.list, Keys.VK_ESCAPE, true), true)
	eq(s.closed, true)
	local h = newList(abc(), { horizontal = true })
	h.list.Open("T")
	eq(press(h.list, Keys.VK_RIGHT), true)
	listeq(Spoken(), { "Beta, 2 of 3" })
	local noClose = newList(abc(), { onClose = false })
	noClose.list.Open("T")
end)

test("an error in build is logged, not thrown", function()
	local s = newList(abc(), { build = function() error("boom") end })
	ClearPrinted()
	s.list.Open("T")
	listeq(Spoken(), { "T, nothing available" })
	contains(Printed[1], "KeyNavList build error")
end)

test("ShortList", function()
	eq(KeyNavList_ShortList({ "a", "b" }), "a, b")
	eq(KeyNavList_ShortList({ "a", "b", "c", "d", "e", "f" }), "a, b, c, d and 2 more")
	eq(KeyNavList_ShortList({ "a", "b", "c" }, 2), "a, b and 1 more")
end)

test("ctrlKeys: Control+Tab acts at KeyUp and is consumed; Control+Down is not", function()
	local hit = 0
	local s = newList(abc(), { ctrlKeys = { [Keys.VK_TAB] = function() hit = hit + 1 end } })
	ClearPrinted()
	eq(s.list.HandleInput(Input{ key = Keys.VK_TAB, ctrl = true }), true)
	eq(hit, 0)
	eq(s.list.HandleInput(Input{ key = Keys.VK_TAB, ctrl = true, up = true }), true)
	eq(hit, 1)
	eq(s.list.HandleInput(Input{ key = Keys.VK_DOWN, ctrl = true }), false)
end)

test("focusLostSafe: lost focus names the new focus and the next Enter only reads it", function()
	local s = newList(abc(), { focusLostSafe = true })
	s.list.Open("T")
	press(s.list, Keys.VK_DOWN)		-- Beta
	s.items = { { key = "a", text = "Alpha" } }
	press(s.list, Keys.VK_RETURN, true)
	listeq(Spoken(), { "Item no longer available. Now on: Alpha" })
	eq(s.activated, nil)
	press(s.list, Keys.VK_RETURN, true)
	eq(s.activated, nil)
	listeq(Spoken(), { "Alpha. Enter again to choose it" })
	press(s.list, Keys.VK_RETURN, true)
	eq(s.activated, "a")
end)

test("focusLostSafe: an arrow key clears the guard", function()
	local s = newList(abc(), { focusLostSafe = true })
	s.list.Open("T")
	press(s.list, Keys.VK_DOWN)
	s.items = { { key = "a", text = "Alpha" }, { key = "c", text = "Gamma" } }
	press(s.list, Keys.VK_RETURN, true)
	press(s.list, Keys.VK_DOWN)
	press(s.list, Keys.VK_RETURN, true)
	eq(s.activated, "c")
end)

local function pressC(list, key, up)
	ClearPrinted()
	return list.HandleInput(Input{ key = key, up = up, ctrl = true })
end

local function grouped()
	return {
		{ key = "a1", text = "Alpha one", section = "A" }, { key = "a2", text = "Alpha two", section = "A" },
		{ key = "b1", text = "Beta one", section = "B" }, { key = "b2", text = "Beta two", section = "B" }, { key = "b3", text = "Beta three", section = "B" },
		{ key = "c1", text = "Gamma one", section = "C" },
	}
end

test("KeyNavList_GroupTarget: next / previous group start, wrapping", function()
	local items = grouped()
	eq(KeyNavList_GroupTarget(items, 1, 1), 3)
	eq(KeyNavList_GroupTarget(items, 4, 1), 6)
	eq(KeyNavList_GroupTarget(items, 6, 1), 1)		-- wraps
	eq(KeyNavList_GroupTarget(items, 4, -1), 1)
	eq(KeyNavList_GroupTarget(items, 3, -1), 1)
	eq(KeyNavList_GroupTarget(items, 1, -1), 6)		-- wraps
	local t, why = KeyNavList_GroupTarget(abc(), 1, 1)
	eq(t, nil); eq(why, "none")
	t, why = KeyNavList_GroupTarget({ { key = "x", text = "X", section = "S" }, { key = "y", text = "Y", section = "S" } }, 1, 1)
	eq(t, nil); eq(why, "one")
end)

test("PageDown / PageUp jump between groups and speak the group", function()
	local s = newList(grouped())
	s.list.Open("T")
	eq(press(s.list, Keys.VK_NEXT), true)
	listeq(Spoken(), { "B: Beta one, 3 of 6" })
	press(s.list, Keys.VK_NEXT)
	listeq(Spoken(), { "C: Gamma one, 6 of 6" })
	press(s.list, Keys.VK_PRIOR)
	listeq(Spoken(), { "B: Beta one, 3 of 6" })
	eq(press(s.list, Keys.VK_NEXT, true), true)		-- KeyUp consumed silently
	listeq(Spoken(), {})
end)

test("PageDown in a list without groups is consumed and says so", function()
	local s = newList(abc())
	s.list.Open("T")
	eq(press(s.list, Keys.VK_NEXT), true)
	listeq(Spoken(), { "No groups in this list" })
end)

test("sectionCounts: the group name comes with its item count", function()
	local s = newList(grouped(), { sectionCounts = true })
	s.list.Open("T")
	press(s.list, Keys.VK_NEXT)
	listeq(Spoken(), { "B, 3: Beta one, 3 of 6" })
end)

test("entering a group does not repeat its name when the item starts with it", function()
	local s = newList({
		{ key = "a", text = "Alpha one", section = "Alpha" }, { key = "b", text = "Builder, 5 tiles east of Rome", section = "Builder" },
		{ key = "c", text = "Builder, 7 tiles west", section = "Builder" },
	}, { sectionCounts = true })
	s.list.Open("T")
	press(s.list, Keys.VK_NEXT)
	listeq(Spoken(), { "Builder, 2: 5 tiles east of Rome, 2 of 3" })
	press(s.list, Keys.VK_DOWN)		-- inside the group the full text
	listeq(Spoken(), { "Builder, 7 tiles west, 3 of 3" })
end)

test("Down into a new group: the item first, the group (and its count) after it", function()
	local s = newList(grouped(), { sectionCounts = true })
	s.list.Open("T")
	press(s.list, Keys.VK_DOWN)
	listeq(Spoken(), { "Alpha two, 2 of 6" })
	press(s.list, Keys.VK_DOWN)
	listeq(Spoken(), { "Beta one, in B, 3 items, 3 of 6" })
	press(s.list, Keys.VK_END)
	listeq(Spoken(), { "Gamma one, in C, 1 item, 6 of 6" })
end)

test("Down into a self-named group keeps the item whole and adds only the count", function()
	local items = {
		{ key = "a", text = "Alpha one", section = "Alpha" }, { key = "b", text = "Builder, 5 tiles east of Rome", section = "Builder" },
		{ key = "c", text = "Builder, 7 tiles west", section = "Builder" },
	}
	local s = newList(items, { sectionCounts = true })
	s.list.Open("T")
	press(s.list, Keys.VK_DOWN)
	listeq(Spoken(), { "Builder, 5 tiles east of Rome, 2 items, 2 of 3" })
	s = newList(items)
	s.list.Open("T")
	press(s.list, Keys.VK_DOWN)
	listeq(Spoken(), { "Builder, 5 tiles east of Rome, 2 of 3" })
end)

test("controller mode: D-pad up / down move one item, left / right are Left / Right, bumpers are the sections", function()
	local log = {}
	local s = newList(abc(), { extraKeys = { [Keys.VK_TAB] = function() table.insert(log, "next") end },
		ctrlKeys = { [Keys.VK_TAB] = function() table.insert(log, "prev") end } })
	s.list.Open("T")
	press(s.list, Keys.VK_END)		-- keyboard: last
	listeq(Spoken(), { "Gamma, 3 of 3" })
	press(s.list, Keys.VK_F22)		-- controller mode on
	press(s.list, Keys.VK_END)		-- D-pad down: one item (wraps to the first)
	listeq(Spoken(), { "Alpha, 1 of 3" })
	press(s.list, Keys.VK_HOME)		-- D-pad up
	listeq(Spoken(), { "Gamma, 3 of 3" })
	eq(press(s.list, Keys.VK_TAB), false)		-- D-pad right = Right: this list has no horizontal movement
	eq(pressC(s.list, Keys.VK_TAB), false)
	eq(#log, 0)
	press(s.list, Keys.VK_F15); press(s.list, Keys.VK_F15, true)
	listeq(log, { "next" })
	ClearPrinted()
	s.list.HandleInput(Input{ key = Keys.VK_F14, up = true })
	listeq(log, { "next", "prev" })
	s.list.HandleInput(Input{ key = Keys.VK_F23 })		-- keyboard again
	press(s.list, Keys.VK_END)
	listeq(Spoken(), { "Gamma, 3 of 3" })
end)

test("controller mode: D-pad right / left move in a horizontal list", function()
	local s = newList(abc(), { horizontal = true })
	s.list.Open("T")
	press(s.list, Keys.VK_F22)
	press(s.list, Keys.VK_TAB)
	listeq(Spoken(), { "Beta, 2 of 3" })
	pressC(s.list, Keys.VK_TAB)		-- Left
	listeq(Spoken(), { "Alpha, 1 of 3" })
end)

test("controller mode: LB / RB in a list without tabs say so", function()
	local s = newList(abc())
	s.list.Open("T")
	press(s.list, Keys.VK_F22)
	eq(press(s.list, Keys.VK_F15), true)
	listeq(Spoken(), {})
	press(s.list, Keys.VK_F15, true)
	listeq(Spoken(), { "No tabs here" })
	press(s.list, Keys.VK_F14, true)
	listeq(Spoken(), { "No tabs here" })
end)

test("HasTabs and AtTabEdge", function()
	local s = newList(abc())
	eq(s.list.HasTabs(), false)
	local t = newList(abc(), { extraKeys = { [Keys.VK_TAB] = function() end }, tabEdge = function(step) return step > 0 end })
	eq(t.list.HasTabs(), true)
	eq(t.list.AtTabEdge(1), true)
	eq(t.list.AtTabEdge(-1), false)
end)

test("pad wheel: a slot jumps to the item in that direction, once", function()
	local s = newList({ { key = "n", text = "North" }, { key = "e", text = "East" }, { key = "s", text = "South" }, { key = "w", text = "West" } }, { wheel = true })
	s.list.Open("T")
	ClearPrinted()
	eq(s.list.HandleInput(Input{ key = Keys.VK_F19, shift = true }), true)		-- slot 6: right
	listeq(Spoken(), { "East, 2 of 4" })
	ClearPrinted()
	s.list.HandleInput(Input{ key = Keys.VK_F19, shift = true, up = true })
	s.list.HandleInput(Input{ key = Keys.VK_F20, shift = true })				-- slot 7: still East
	listeq(Spoken(), {})
	s.list.HandleInput(Input{ key = Keys.VK_F19, ctrl = true, shift = true })	-- slot 18: left
	listeq(Spoken(), { "West, 4 of 4" })
	ClearPrinted()
	press(s.list, Keys.VK_DOWN)														-- the stick still moves on from there
	listeq(Spoken(), { "North, 1 of 4" })
	ClearPrinted()
	s.list.HandleInput(Input{ key = Keys.VK_F13, ctrl = true, shift = true })	-- slot 12: down
	listeq(Spoken(), { "South, 3 of 4" })
	eq(s.activated, nil)															-- pointing never activates
end)

test("pad wheel: the first wheel key after another key speaks even the focused item; a lingering stick stays silent", function()
	local s = newList({ { key = "n", text = "North" }, { key = "e", text = "East" } }, { wheel = true })
	s.list.Open("T")
	ClearPrinted()
	s.list.HandleInput(Input{ key = Keys.VK_F13, ctrl = true, shift = true })	-- slot 12: down = East
	listeq(Spoken(), { "East, 2 of 2" })
	ClearPrinted()
	s.list.HandleInput(Input{ key = Keys.VK_F14, ctrl = true, shift = true })	-- lingering: still East
	listeq(Spoken(), {})
	press(s.list, Keys.VK_UP)
	press(s.list, Keys.VK_DOWN)													-- focus on East again via Down
	ClearPrinted()
	s.list.HandleInput(Input{ key = Keys.VK_F13, ctrl = true, shift = true })
	listeq(Spoken(), { "East, 2 of 2" })
end)

test("sectionCounts: an uncounted item is not part of its group's count", function()
	local s = newList({
		{ key = "a", text = "Alpha one", section = "A" }, { key = "b", text = "Beta one", section = "B" },
		{ key = "c", text = "Beta two", section = "B" }, { key = "t", text = "Toggle", section = "B", uncounted = true },
	}, { sectionCounts = true })
	s.list.Open("T")
	press(s.list, Keys.VK_NEXT)
	listeq(Spoken(), { "B, 2: Beta one, 2 of 4" })
end)

test("pad wheel: a list without wheel = true says so once per sweep and keeps its focus", function()
	local s = newList(abc())
	s.list.Open("T")
	ClearPrinted()
	eq(s.list.HandleInput(Input{ key = Keys.VK_F19, shift = true }), true)
	s.list.HandleInput(Input{ key = Keys.VK_F19, shift = true, up = true })
	s.list.HandleInput(Input{ key = Keys.VK_SHIFT, shift = true })
	s.list.HandleInput(Input{ key = Keys.VK_F13, ctrl = true, shift = true })
	listeq(Spoken(), { "No wheel in this list" })
	press(s.list, Keys.VK_DOWN)
	listeq(Spoken(), { "Beta, 2 of 3" })		-- still on Alpha before
	ClearPrinted()
	s.list.HandleInput(Input{ key = Keys.VK_F19, shift = true })
	listeq(Spoken(), { "No wheel in this list" })		-- a new sweep after another key
end)
