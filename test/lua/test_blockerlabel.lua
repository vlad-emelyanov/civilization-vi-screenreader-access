-- HubAnnounce.BlockerFromLabel: only a real action-panel blocker text is spoken after "Turn not ended".
-- The pure function is extracted here from the source (HubAnnounce itself needs the whole hub stub, see test_hubmodules.lua).
local f = assert(io.open("ScreenReaderAccess/Assets/UI/Accessibility/HubAnnounce.lua", "rb"))
local src = f:read("*a")
f:close()
src = src:gsub("\r\n", "\n")
local body = src:match("(function HubAnnounce%.BlockerFromLabel.-\nend)\n")
assert(body, "BlockerFromLabel not found")
HubAnnounce = {}
assert(loadstring((body:gsub("(%w+):(%w+)", "%1")), "BlockerFromLabel"))()
local fn = HubAnnounce.BlockerFromLabel

test("BlockerFromLabel: only a real blocker text is returned", function()
	local ignored = { "please wait", "next turn", "waiting for other players" }
	eq(fn("UNIT NEEDS ORDERS", ignored), "Unit needs orders", "blocker")
	eq(fn("Please wait", ignored), "", "please wait")
	eq(fn("NEXT TURN", ignored), "", "next turn")
	eq(fn("Waiting for other players", ignored), "", "waiting for players")
	eq(fn("", ignored), "", "empty")
	eq(fn(nil, ignored), "", "nil")
end)

-- N names the thing Enter takes you to (HubAnnounce.BlockerWithThing, pure)
local body2 = src:match("(function HubAnnounce%.BlockerWithThing.-\nend)\n")
assert(body2, "BlockerWithThing not found")
assert(loadstring((body2:gsub("(%w+):(%w+)", "%1")), "BlockerWithThing"))()
local thing = HubAnnounce.BlockerWithThing
local body4 = src:match("(function HubAnnounce%.ReadyUnitsText.-\nend)\n")
assert(body4, "ReadyUnitsText not found")
assert(loadstring((body4:gsub("(%w+):(%w+)", "%1")), "ReadyUnitsText"))()

test("ReadyUnitsText: named only when exactly one", function()
	eq(HubAnnounce.ReadyUnitsText("Unit needs orders", 1, "Archer, in Rome"), "Unit needs orders: Archer, in Rome. Enter selects it", "one")
	eq(HubAnnounce.ReadyUnitsText("Unit needs orders", 3, nil), "3 units need orders. Enter selects the next one", "several")
	eq(HubAnnounce.ReadyUnitsText("Unit needs orders", 0, nil), "Unit needs orders", "none")
end)

test("BlockerWithThing: unit, position and hint", function()
	eq(thing("Unit needs orders", "Archer, 2 tiles east of Rome", "Enter selects it"),
		"Unit needs orders: Archer, 2 tiles east of Rome. Enter selects it", "unit")
	eq(thing("Choose production", "Rome and 1 more city", nil), "Choose production: Rome and 1 more city", "no hint")
	eq(thing("Unit needs orders", nil, "x"), "Unit needs orders", "no thing")
	eq(thing("Unit needs orders", "", "x"), "Unit needs orders", "empty thing")
end)

-- Tab belongs to the open region (Hub.UnitActionsKey in InGameAccess.lua)
local f2 = assert(io.open("ScreenReaderAccess/UI/Additions/InGameAccess.lua", "rb"))
local hubsrc = f2:read("*a"):gsub("\r\n", "\n")
f2:close()
local body3 = hubsrc:match("(function Hub%.UnitActionsKey.-\nend)\n")
assert(body3, "UnitActionsKey not found")
Hub = {}
HubCore = {}
OutputMessageToScreenReader = function() end
local opened, tabbed = 0, 0
HubMenus = { ToggleUnitMenu = function() opened = opened + 1 end }
assert(loadstring((body3:gsub("(%w+):(%w+)", "%1")), "UnitActionsKey"))()

test("Tab: regions get it, the unit menu opens only from the plain map", function()
	opened, tabbed = 0, 0
	HubCore.m_mode = nil
	Hub.UnitActionsKey()
	eq(opened, 1, "plain map opens the unit menu")
	HubCore.m_mode = { name = "cityreport", list = { tabAction = function() tabbed = tabbed + 1 end } }
	Hub.UnitActionsKey()
	eq(opened, 1, "city report: no unit menu")
	eq(tabbed, 1, "city report: its own Tab")
	HubCore.m_mode = { name = "notifications", list = {} }
	Hub.UnitActionsKey()
	eq(opened, 1, "region without Tab: ignored")
	HubCore.m_mode = { name = "menu", list = {} }
	Hub.UnitActionsKey()
	eq(opened, 2, "the unit menu itself toggles")
end)
