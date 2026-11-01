-- KeyNavList.lua: letterJump option (a letter key jumps to the next item starting with it)
stub("engine")
include("KeyNavList")

for code = 65, 90 do Keys[ string.char( code ) ] = code end

local function newList(items, extra)
	local state = { items = items, activated = nil }
	local cfg = {
		build = function() return state.items end,
		isActive = function() return true end,
		onActivate = function(item) state.activated = item.key end,
		letterJump = true,
	}
	for k, v in pairs(extra or {}) do cfg[k] = v end
	state.list = KeyNavList_Create(cfg)
	return state
end

local function policies()
	return {
		{ key = "p1", text = "Agoge: more", jumpText = "Agoge" }, { key = "p2", text = "Bastions: x", jumpText = "Bastions" },
		{ key = "p3", text = "Ancestral: y", jumpText = "Ancestral" }, { key = "p4", text = "Conscription: z", jumpText = "Conscription" },
	}
end

local function tap(list, key, mods)
	ClearPrinted()
	mods = mods or {}
	if not mods.stale then Clock.now = Clock.now + 1 end
	local down = list.HandleInput(Input{ key = key, ctrl = mods.ctrl, shift = mods.shift, alt = mods.alt })
	local up = list.HandleInput(Input{ key = key, up = true, ctrl = mods.ctrl, shift = mods.shift, alt = mods.alt })
	return down, up
end

test("a letter jumps to the next item starting with it, the same letter goes on and wraps", function()
	local s = newList(policies())
	s.list.Open("T"); ClearPrinted()
	local down, up = tap(s.list, Keys.A)
	eq(down, true); eq(up, true)
	listeq(Spoken(), { "Ancestral: y, 3 of 4" })
	tap(s.list, Keys.A)
	listeq(Spoken(), { "Agoge: more, 1 of 4" })
end)

test("no match says so", function()
	local s = newList(policies())
	s.list.Open("T")
	tap(s.list, Keys.Q)
	listeq(Spoken(), { "Nothing starting with Q" })
end)

test("a single match stays on that item and speaks it again", function()
	local s = newList(policies())
	s.list.Open("T")
	tap(s.list, Keys.C)
	listeq(Spoken(), { "Conscription: z, 4 of 4" })
	tap(s.list, Keys.C)
	listeq(Spoken(), { "Conscription: z, 4 of 4" })
end)

test("modifier combinations do not jump", function()
	local s = newList(policies())
	s.list.Open("T")
	eq(tap(s.list, Keys.B, { shift = true }), false)
	eq(#Spoken(), 0)
	eq(tap(s.list, Keys.B, { ctrl = true }), false)
	eq(tap(s.list, Keys.B, { alt = true }), false)
	eq(#Spoken(), 0)
end)

test("extraKeys win over the letter", function()
	local hit = nil
	local s = newList(policies(), { extraKeys = { [Keys.B] = function() hit = "b" end } })
	s.list.Open("T")
	tap(s.list, Keys.B)
	eq(hit, "b")
	eq(#Spoken(), 0)
end)

test("off by default: letters are not consumed and silent", function()
	local s = newList(policies(), { letterJump = false })
	s.list.Open("T")
	local down, up = tap(s.list, Keys.A)
	eq(down, false); eq(up, false)
	eq(#Spoken(), 0)
end)

test("letterJump as a function: only while it answers true; otherwise the letter is not consumed", function()
	local on = false
	local s = newList(policies(), { letterJump = function() return on end })
	s.list.Open("T")
	local down, up = tap(s.list, Keys.A)
	eq(down, false); eq(up, false)
	eq(#Spoken(), 0)
	on = true
	tap(s.list, Keys.A)
	listeq(Spoken(), { "Ancestral: y, 3 of 4" })
end)

test("a letter KeyUp within 0.3 s of Open is ignored", function()
	local s = newList(policies())
	Clock.now = 100
	s.list.Open("T")
	Clock.now = 100.1
	tap(s.list, Keys.A, { stale = true })
	eq(#Spoken(), 0)
	Clock.now = 100.5
	tap(s.list, Keys.A, { stale = true })
	listeq(Spoken(), { "Ancestral: y, 3 of 4" })
end)

test("KeyNavList_LetterTarget: case, leading blanks, wrap", function()
	local items = { { text = "alpha" }, { text = "  Beta" }, { text = "Gamma" } }
	eq(KeyNavList_LetterTarget(items, 0, "B"), 2)
	eq(KeyNavList_LetterTarget(items, 2, "b"), 2)
	eq(KeyNavList_LetterTarget(items, 3, "a"), 1)
	eq(KeyNavList_LetterTarget(items, 1, "z"), nil)
	eq(KeyNavList_LetterTarget({}, 0, "a"), nil)
end)
