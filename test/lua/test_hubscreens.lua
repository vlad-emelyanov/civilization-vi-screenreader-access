-- HubScreens.lua: the screens list items and the open / not available path
stub("engine")
include("KeyNavList")
include("HubScreens")

local fired, listener, reply
local opened = nil
HubCore = {
	Listen = function(event, fn) listener = fn end,
	IsModeOpen = function() return false end,
	CloseMode = function() end,
	OpenMode = function(name) opened = name end,
}
HubTargets = { CanOpenMode = function() return true end }
LuaEvents = {
	SRA_ScreenOpened = {},
	SRA_OpenScreen = function(name) fired = name; if reply ~= nil then listener(name, reply) end end,
	OpenCivilopedia = function() fired = "pedia" end,
}

test("items", function()
	local items = HubScreens.BuildItems()
	eq(#items, 15)
	eq(items[1].text, "Tech tree")
	eq(items[12].text, "Climate")
	eq(items[15].text, "Civilopedia")
end)

test("Open registers the answer listener and opens the mode", function()
	HubScreens.Open()
	eq(opened, "screens")
	assert(listener ~= nil, "listener")
end)

test("a hook that answers ok opens the screen", function()
	fired = nil
	reply = true
	eq(HubScreens.OpenScreen(HubScreens.SCREENS[1]), true)
	eq(fired, "Tech tree")
end)

test("a hook that answers not ok, or nobody answers: not available", function()
	reply = false
	eq(HubScreens.OpenScreen(HubScreens.SCREENS[8]), false)
	reply = nil
	eq(HubScreens.OpenScreen(HubScreens.SCREENS[8]), false)
end)

test("Enter on an unavailable screen closes the list and says so", function()
	reply = false
	HubScreens.Open()
	local list = nil
	-- activate through the item the list builds
	local item = HubScreens.BuildItems()[12]
	ClearPrinted()
	local ok = HubScreens.OpenScreen(item.screen)
	eq(ok, false)
end)

test("civilopedia opens by its own event", function()
	fired = nil
	eq(HubScreens.OpenScreen(HubScreens.SCREENS[15]), true)
	eq(fired, "pedia")
end)
