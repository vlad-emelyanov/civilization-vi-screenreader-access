-- TreeNav.lua: era / item navigation, target request read-back and search of the tech / civics tree, on a fake adapter
stub("engine")
Keys.VK_TAB = 9
Keys.J = 74
Keys.F = 70
Keys.Q = 81
Keys.T = 84
Keys.VK_F13 = 124		-- controller X, LT, RT (Gamepad.lua)
Keys.VK_F16 = 127
Keys.VK_F17 = 128
include("TreeNav")

local function entries()
	return {
		{ key = "POTTERY", name = "Pottery", era = 0, eraName = "Ancient Era", column = 1, row = 0 },
		{ key = "ARCHERY", name = "Archery", era = 0, eraName = "Ancient Era", column = 2, row = 1 },
		{ key = "BRONZE", name = "Bronze Working", era = 0, eraName = "Ancient Era", column = 3, row = 0 },
		{ key = "IRON", name = "Iron Working", era = 1, eraName = "Classical Era", column = 1, row = 0 },
		{ key = "MATH", name = "Mathematics", era = 1, eraName = "Classical Era", column = 2, row = 0 },
	}
end

local INFO = {
	POTTERY = { name = "Pottery", status = "researched" },
	ARCHERY = { name = "Archery", status = "current", turns = 5, currentWord = "currently researching" },
	BRONZE = { name = "Bronze Working", status = "available", turns = 4, boosted = true },
	IRON = { name = "Iron Working", status = "blocked", turns = 9, needs = { "Bronze Working" } },
	MATH = { name = "Mathematics", status = "blocked", turns = 8, needs = { "Archery" } },
}

local function newNav(extra)
	local s = { shown = true, closed = false, requests = {}, queueResult = { keys = {}, names = {}, turns = 0 }, committed = nil, ok = true }
	local a = {
		name = "Tech tree", closedText = "Tech tree closed", toggleKey = Keys.T,
		isShown = function() return s.shown end,
		entries = entries,
		item = function(key) return INFO[key] end,
		detail = function(key) return "Details of " .. key end,
		current = function() return "ARCHERY" end,
		currentLine = function() return "Researching Archery, 5 turns" end,
		request = function(key, append)
			table.insert(s.requests, key .. (append and "+" or ""))
			if s.ok then return true end
			return false, "Pottery is already researched"
		end,
		queue = function() return s.queueResult end,
		search = function(text) if text == "fulltext" then return "MATH" end return nil end,
		beginSearch = function(onCommit) s.commit = onCommit end,
		close = function() s.closed = true end,
	}
	for k, v in pairs(extra or {}) do a[k] = v end
	s.nav = TreeNav_Create(a)
	return s
end

local function press(s, key, spec)
	ClearPrinted()
	spec = spec or {}
	spec.key = key
	spec.up = nil
	local consumedDown = s.nav.HandleInput(Input(spec))
	spec.up = true
	local consumedUp = s.nav.HandleInput(Input(spec))
	return consumedDown and consumedUp
end

test("Open: current research, its era, first item of the era", function()
	local s = newNav()
	ClearPrinted()
	s.nav.Open()
	listeq(Spoken(), { "Tech tree. Researching Archery, 5 turns. Ancient Era, 1 of 2 eras. Pottery, researched, 1 of 3" })
end)

test("Up/Down move within the era and wrap, Home/End", function()
	local s = newNav()
	s.nav.Open()
	press(s, Keys.VK_DOWN)
	listeq(Spoken(), { "Archery, currently researching, 5 turns, 2 of 3" })
	press(s, Keys.VK_DOWN)
	listeq(Spoken(), { "Bronze Working, available, 4 turns, boosted, 3 of 3" })
	press(s, Keys.VK_DOWN)
	listeq(Spoken(), { "Pottery, researched, 1 of 3" })
	press(s, Keys.VK_UP)
	listeq(Spoken(), { "Bronze Working, available, 4 turns, boosted, 3 of 3" })
	press(s, Keys.VK_HOME)
	listeq(Spoken(), { "Pottery, researched, 1 of 3" })
	press(s, Keys.VK_END)
	listeq(Spoken(), { "Bronze Working, available, 4 turns, boosted, 3 of 3" })
end)

test("Left/Right/Tab/Control+Tab switch eras", function()
	local s = newNav()
	s.nav.Open()
	press(s, Keys.VK_RIGHT)
	listeq(Spoken(), { "Classical Era, 2 of 2 eras. Iron Working, 9 turns, needs Bronze Working, 1 of 2" })
	press(s, Keys.VK_RIGHT)
	listeq(Spoken(), { "Last era" })
	press(s, Keys.VK_LEFT)
	listeq(Spoken(), { "Ancient Era, 1 of 2 eras. Pottery, researched, 1 of 3" })
	press(s, Keys.VK_LEFT)
	listeq(Spoken(), { "First era" })
	press(s, Keys.VK_TAB)
	listeq(Spoken(), { "Classical Era, 2 of 2 eras. Iron Working, 9 turns, needs Bronze Working, 1 of 2" })
	press(s, Keys.VK_TAB, { ctrl = true })
	listeq(Spoken(), { "Ancient Era, 1 of 2 eras. Pottery, researched, 1 of 3" })
end)

test("Space reads the details", function()
	local s = newNav()
	s.nav.Open()
	press(s, Keys.VK_SPACE)
	listeq(Spoken(), { "Details of POTTERY" })
end)

test("J jumps to the current research, with its era", function()
	local s = newNav()
	s.nav.Open()
	press(s, Keys.VK_RIGHT)
	press(s, Keys.J)
	listeq(Spoken(), { "Current: Ancient Era, 1 of 2 eras. Archery, currently researching, 5 turns, 2 of 3" })
end)

test("J with nothing being researched", function()
	local s = newNav({ current = function() return nil end })
	s.nav.Open()
	press(s, Keys.J)
	listeq(Spoken(), { "Not researching anything" })
end)

test("Enter: request, then the queue is read back after it settled", function()
	local s = newNav()
	s.nav.Open()
	press(s, Keys.VK_RIGHT)		-- Iron Working
	ClearPrinted()
	s.queueResult = { keys = { "BRONZE", "IRON" }, names = { "Bronze Working", "Iron Working" }, turns = 13 }
	press(s, Keys.VK_RETURN)
	listeq(s.requests, { "IRON" })
	listeq(Spoken(), {})				-- nothing yet: waits for the queue event
	s.nav.QueueChanged()
	s.nav.Update(0.1)
	listeq(Spoken(), {})
	s.nav.Update(0.3)
	listeq(Spoken(), { "Target: Iron Working, path: Bronze Working, Iron Working, 13 turns" })
	ClearPrinted()
	s.nav.Update(2)
	listeq(Spoken(), {})				-- spoken once
end)

test("Enter without a queue event still reads back after the timeout", function()
	local s = newNav()
	s.nav.Open()
	press(s, Keys.VK_DOWN)		-- Archery
	s.queueResult = { keys = { "ARCHERY" }, names = { "Archery" }, turns = 5 }
	ClearPrinted()
	press(s, Keys.VK_RETURN)
	s.nav.Update(1.0)
	listeq(Spoken(), {})
	s.nav.Update(1.0)
	listeq(Spoken(), { "Target: Archery, 5 turns" })
end)

test("Enter when the queue does not end in the target says so", function()
	local s = newNav()
	s.nav.Open()
	press(s, Keys.VK_RIGHT)
	s.queueResult = { keys = { "ARCHERY" }, names = { "Archery" }, turns = 5 }
	ClearPrinted()
	press(s, Keys.VK_RETURN)
	s.nav.Update(2)
	listeq(Spoken(), { "Could not set Iron Working as the target" })
end)

test("Enter on a refused node speaks the reason and waits for nothing", function()
	local s = newNav()
	s.nav.Open()
	s.ok = false
	ClearPrinted()
	press(s, Keys.VK_RETURN)
	listeq(Spoken(), { "Pottery is already researched" })
	ClearPrinted()
	s.nav.Update(5)
	listeq(Spoken(), {})
end)

test("Shift+Enter appends", function()
	local s = newNav()
	s.nav.Open()
	press(s, Keys.VK_END)		-- Bronze Working
	s.queueResult = { keys = { "ARCHERY", "BRONZE" }, names = { "Archery", "Bronze Working" }, turns = 9 }
	ClearPrinted()
	press(s, Keys.VK_RETURN, { shift = true })
	listeq(s.requests, { "BRONZE+" })
	s.nav.Update(2)
	listeq(Spoken(), { "Added to queue: Bronze Working, path: Archery, Bronze Working, 9 turns" })
end)

test("controller X queues like Shift+Enter, LT is J, RT is Q", function()
	local s = newNav()
	s.nav.Open()
	press(s, Keys.VK_END)		-- Bronze Working
	s.queueResult = { keys = { "ARCHERY", "BRONZE" }, names = { "Archery", "Bronze Working" }, turns = 9 }
	ClearPrinted()
	press(s, Keys.VK_F13)
	listeq(s.requests, { "BRONZE+" })
	s.nav.Update(2)
	listeq(Spoken(), { "Added to queue: Bronze Working, path: Archery, Bronze Working, 9 turns" })
	press(s, Keys.VK_F17)
	listeq(Spoken(), { "Queue: Archery, Bronze Working, 9 turns" })
	press(s, Keys.VK_F16)
	eq(#Spoken() > 0, true)
end)

test("right stick (Control+F13, F16, F17) does not queue, jump or read the queue", function()
	local s = newNav()
	s.nav.Open()
	press(s, Keys.VK_END)
	ClearPrinted()
	press(s, Keys.VK_F13, { ctrl = true })
	press(s, Keys.VK_F16, { ctrl = true })
	press(s, Keys.VK_F17, { ctrl = true })
	listeq(s.requests, {})
	listeq(Spoken(), {})
end)

test("Q reads the queue", function()
	local s = newNav()
	s.nav.Open()
	press(s, Keys.Q)
	listeq(Spoken(), { "The queue is empty" })
	s.queueResult = { keys = { "ARCHERY", "BRONZE" }, names = { "Archery", "Bronze Working" }, turns = 9 }
	press(s, Keys.Q)
	listeq(Spoken(), { "Queue: Archery, Bronze Working, 9 turns" })
end)

test("F: search jumps to the first match after the edit settled", function()
	local s = newNav()
	s.nav.Open()
	press(s, Keys.F)
	istrue(s.commit ~= nil, "search started")
	ClearPrinted()
	s.commit("iron")
	listeq(Spoken(), {})
	s.nav.Update(0.1)
	listeq(Spoken(), {})
	s.nav.Update(0.3)
	listeq(Spoken(), { "Found: Classical Era, 2 of 2 eras. Iron Working, 9 turns, needs Bronze Working, 1 of 2" })
end)

test("F: full-text fallback and no match", function()
	local s = newNav()
	s.nav.Open()
	press(s, Keys.F)
	s.commit("fulltext")
	s.nav.Update(0.5)
	listeq(Spoken(), { "Found: Classical Era, 2 of 2 eras. Mathematics, 8 turns, needs Archery, 2 of 2" })
	press(s, Keys.F)
	s.commit("nothing like it")
	s.nav.Update(0.5)
	listeq(Spoken(), { "No match for nothing like it" })
end)

test("Escape and the toggle key close; every key is consumed while shown", function()
	local s = newNav()
	s.nav.Open()
	eq(press(s, Keys.VK_ESCAPE), true)
	eq(s.closed, true)
	listeq(Spoken(), { "Tech tree closed" })
	s.closed = false
	eq(press(s, Keys.T), true)
	eq(s.closed, true)
	eq(press(s, 200), true)		-- an unknown key is swallowed silently
	listeq(Spoken(), {})
end)

test("Not shown: keys are left alone", function()
	local s = newNav()
	s.shown = false
	eq(s.nav.HandleInput(Input{ key = Keys.VK_DOWN }), false)
end)

test("The focus survives a rebuilt tree and recovers when its node vanished", function()
	local items = entries()
	local s = newNav({ entries = function() return items end })
	s.nav.Open()
	press(s, Keys.VK_DOWN)		-- Archery
	table.insert(items, { key = "NEW", name = "Newtech", era = 0, eraName = "Ancient Era", column = 0, row = 0 })
	press(s, Keys.VK_DOWN)
	listeq(Spoken(), { "Bronze Working, available, 4 turns, boosted, 4 of 4" })
end)

local FAR_PRE = { IRON = { "BRONZE" }, MATH = { "ARCHERY" }, BRONZE = {}, ARCHERY = {}, POTTERY = {} }

test("Enter on a blocked node: path count, turns and what the game started on", function()
	local s = newNav({ prereqs = function(k) return FAR_PRE[k] end, itemWord = "tech" })
	s.nav.Open()
	press(s, Keys.VK_RIGHT)		-- Iron Working (blocked, 9 turns) needs Bronze Working (available, 4 turns)
	s.queueResult = { keys = { "BRONZE", "IRON" }, names = { "Bronze Working", "Iron Working" }, turns = 13, each = { 4, 9 } }
	ClearPrinted()
	press(s, Keys.VK_RETURN)
	s.nav.QueueChanged()
	s.nav.Update(0.3)
	listeq(Spoken(), { "Iron Working set as the target: 2 techs on the way, about 13 turns. Next: Bronze Working, 4 turns, replaces Archery." })
end)

test("Shift+Enter on a blocked node queues the path", function()
	local s = newNav({ prereqs = function(k) return FAR_PRE[k] end, itemWord = "tech" })
	s.nav.Open()
	press(s, Keys.VK_RIGHT)
	s.queueResult = { keys = { "ARCHERY", "BRONZE", "IRON" }, names = { "Archery", "Bronze Working", "Iron Working" }, turns = 18, each = { 5, 4, 9 } }
	ClearPrinted()
	press(s, Keys.VK_RETURN, { shift = true })
	s.nav.Update(2)
	listeq(Spoken(), { "Queued Iron Working: 2 techs, about 13 turns." })
end)

test("Enter on an available node keeps the plain wording", function()
	local s = newNav({ prereqs = function(k) return FAR_PRE[k] end, itemWord = "tech" })
	s.nav.Open()
	press(s, Keys.VK_END)		-- Bronze Working, available
	s.queueResult = { keys = { "BRONZE" }, names = { "Bronze Working" }, turns = 4, each = { 4 } }
	ClearPrinted()
	press(s, Keys.VK_RETURN)
	s.nav.Update(2)
	listeq(Spoken(), { "Target: Bronze Working, 4 turns" })
end)

test("Open and J add the target when the queue goes beyond the current research", function()
	local s = newNav()
	s.queueResult = { keys = { "ARCHERY", "BRONZE", "IRON" }, names = { "Archery", "Bronze Working", "Iron Working" }, turns = 18 }
	ClearPrinted()
	s.nav.Open()
	listeq(Spoken(), { "Tech tree. Researching Archery, 5 turns. Target: Iron Working, about 18 turns. Ancient Era, 1 of 2 eras. Pottery, researched, 1 of 3" })
	press(s, Keys.J)
	listeq(Spoken(), { "Current: Ancient Era, 1 of 2 eras. Archery, currently researching, 5 turns, 2 of 3. Target: Iron Working, about 18 turns" })
	s.queueResult = { keys = { "ARCHERY" }, names = { "Archery" }, turns = 5 }
	press(s, Keys.J)
	listeq(Spoken(), { "Current: Ancient Era, 1 of 2 eras. Archery, currently researching, 5 turns, 2 of 3" })
end)
