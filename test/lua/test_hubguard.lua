-- HubCore double-key guards (Escape after a close, Enter after a list closed by Enter) and the Idle group helpers of HubPlaces
stub("engine")
local world = stub("world").new{ width = 30, height = 20 }
world:install()
include("ScreenReader")
include("HubCore")

local function fresh()
	local g = HubCore.m_guard
	g.open, g.closedAt, g.closedByEnter, g.enterInModeAt = false, -100, false, -100
	g.escWarnedAt, g.enterWarnedAt, g.readyAt = -100, -100, -100
	return g
end

test("lone Escape is not blocked", function()
	local g = fresh()
	eq(HubCore.GuardEscapeBlocks(g, 50), false)
end)

test("Escape within 1.5 s of a close warns once, the next one goes through", function()
	local g = fresh()
	HubCore.GuardNote(g, 10, true)
	HubCore.GuardNote(g, 11, false)
	eq(HubCore.GuardEscapeBlocks(g, 11.4), true, "first")
	eq(HubCore.GuardEscapeBlocks(g, 11.8), false, "second")
	eq(HubCore.GuardEscapeBlocks(g, 12.4), false, "later")
end)

test("Escape after the window passes", function()
	local g = fresh()
	HubCore.GuardNote(g, 10, true)
	HubCore.GuardNote(g, 11, false)
	eq(HubCore.GuardEscapeBlocks(g, 12.6), false)
end)

test("a new close re-arms the Escape warning", function()
	local g = fresh()
	HubCore.GuardNote(g, 10, true); HubCore.GuardNote(g, 11, false)
	eq(HubCore.GuardEscapeBlocks(g, 11.2), true)
	HubCore.GuardNote(g, 20, true); HubCore.GuardNote(g, 21, false)
	eq(HubCore.GuardEscapeBlocks(g, 21.2), true)
end)

test("Enter is only guarded after a list closed by Enter", function()
	local g = fresh()
	HubCore.GuardNote(g, 10, true); HubCore.GuardNote(g, 11, false)		-- closed by Escape
	eq(HubCore.GuardEnterBlocks(g, 11.3), false)
	g.enterInModeAt = 20
	HubCore.GuardNote(g, 20, true); HubCore.GuardNote(g, 20.1, false)
	eq(g.closedByEnter, true)
	eq(HubCore.GuardEnterBlocks(g, 20.5), true, "first Enter warns")
	eq(HubCore.GuardEnterBlocks(g, 21.0), false, "second ends the turn")
end)

test("Enter after the window, or after All done was said, passes", function()
	local g = fresh()
	g.enterInModeAt = 20
	HubCore.GuardNote(g, 20, true); HubCore.GuardNote(g, 20.1, false)
	eq(HubCore.GuardEnterBlocks(g, 22), false, "window over")
	g = fresh()
	g.enterInModeAt = 30
	HubCore.GuardNote(g, 30, true); HubCore.GuardNote(g, 30.1, false)
	g.readyAt = 30.5
	eq(HubCore.GuardEnterBlocks(g, 31), false, "All done said after the close")
end)
