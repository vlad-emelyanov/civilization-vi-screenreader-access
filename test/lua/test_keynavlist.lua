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
	listeq(Spoken(), { "Buildings: Gamma, 3 of 3" })
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
