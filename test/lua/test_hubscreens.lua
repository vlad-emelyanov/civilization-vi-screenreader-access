-- HubScreens.lua: the screens list items and the open / not available path
stub("engine")
include("KeyNavList")
include("HubScreens")

local fired, listener, reply
local opened = nil
HubCore = {
	Listen = function(event, fn) listener = fn end,
	IsModeOpen = function() return opened ~= nil end,
	CloseMode = function() opened = nil end,
	OpenMode = function(name, list, title) opened = name; HubCore.list = list; list.Open(title) end,
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

local function press(list, key)
	ClearPrinted()
	list.HandleInput(Input{ key = key })
	return list.HandleInput(Input{ key = key, up = true })
end

test("Enter on an unavailable screen closes the list and says so (real activation path)", function()
	for _, answer in ipairs({ "notok", "silent" }) do
		reply = (answer == "notok") and false or nil
		opened = nil
		HubScreens.Open()
		eq(opened, "screens")
		for _ = 1, 20 do
			press(HubCore.list, Keys.VK_DOWN)
			if (Spoken()[1] or ""):find("^Climate") then break end
		end
		assert((Spoken()[1] or ""):find("^Climate"), "focus on Climate: " .. tostring(Spoken()[1]))
		fired = nil
		press(HubCore.list, Keys.VK_RETURN)
		eq(fired, "Climate")
		eq(opened, nil, "list closed")
		local found = false
		for _, s in ipairs(Spoken()) do if s == "Climate not available" then found = true end end
		assert(found, "Climate not available spoken: " .. table.concat(Spoken(), " | "))
	end
end)

test("civilopedia opens by its own event", function()
	fired = nil
	eq(HubScreens.OpenScreen(HubScreens.SCREENS[15]), true)
	eq(fired, "pedia")
end)
