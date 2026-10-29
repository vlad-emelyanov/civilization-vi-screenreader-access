-- HubGamepad.HandleInput in a target mode: X scans for foreign units, LB / RB open the places list, the left stick click moves the target to the capital
stub("engine")
for i = 13, 24 do Keys["VK_F" .. i] = 100 + i end
LuaEvents = setmetatable({}, { __index = function() return function() end end })
include("Gamepad")

local shownControls = {}
ContextPtr = { LookUpControl = function(_, path) if shownControls[path] then return { IsHidden = function() return false end } end end }
UI.GetHeadSelectedUnit = function() return nil end
local calls = {}
local mode = 7
local refuse = false
HubCore = {
	IsLocalPlayerActive = function() return true end, IsGamePopupOpen = function() return false end, m_mode = nil,
	Safe = function(name, fn) return function(...) return fn(...) end end,
}
HubTargets = {
	GetTargetMode = function() return mode end,
	CanOpenMode = function(allow) table.insert(calls, "can:" .. tostring(allow)); return not refuse end,
	CapitalKey = function() table.insert(calls, "capital") end,
}
local browser = true
HubSettle = { ScanKey = function() table.insert(calls, "scan") end, BrowserFor = function() if browser then return {} end end }
HubPlaces = { TogglePlaces = function() table.insert(calls, "places") end }
local cursorX, cursorY = 3, 4
HubCursor = { GetCursor = function() return cursorX, cursorY end, SelectAtCursor = function() table.insert(calls, "select") end }
include("HubPad")
HubPad.RingNext = function() table.insert(calls, "ring") end
HubPad.RingPrev = function() table.insert(calls, "ring") end
include("HubGamepad")

local function press(button)
	calls = {}
	local entry = Gamepad.Map[button]
	local key = Keys[entry.key]
	local down = HubGamepad.HandleInput({}, KeyEvents.KeyDown, key, entry.control)
	local up = HubGamepad.HandleInput({}, KeyEvents.KeyUp, key, entry.control)
	return down and up
end

test("target mode: X scans for foreign units, LT and RT stay silent", function()
	eq(press("X"), true)
	eq(table.concat(calls, ","), "scan")
	eq(press("LT"), true)
	eq(press("RT"), true)
	eq(#calls, 0)
end)

test("target mode: LB and RB open the places list, a refusing CanOpenMode(true) stops it", function()
	eq(press("RB"), true)
	eq(table.concat(calls, ","), "can:true,places")
	eq(press("LB"), true)
	eq(table.concat(calls, ","), "can:true,places")
end)

test("target mode: LB and RB refuse only where CanOpenMode(true) refuses", function()
	refuse = true
	press("RB")
	eq(table.concat(calls, ","), "can:true")
	refuse = false
end)

test("target mode: the left stick click moves the target to the capital", function()
	eq(press("LSClick"), true)
	eq(table.concat(calls, ","), "capital")
end)

test("bare map: X selects at the cursor, LB rings", function()
	mode = nil
	eq(press("X"), true)
	eq(table.concat(calls, ","), "select")
	eq(press("RB"), true)
	eq(table.concat(calls, ","), "can:nil,ring")
	mode = 7
end)

test("a held RT (Shift) acts on KeyUp only when no other key came between", function()
	mode = nil
	Keys.VK_SHIFT, Keys.VK_CONTROL, Keys.VK_ALT = 16, 17, 18
	local hotkeys = {}
	LuaEvents = setmetatable({ SRA_PadHotkey = function(name) table.insert(hotkeys, name) end }, { __index = function() return function() end end })
	local savedUI = UI
	UI = setmetatable({ GetHeadSelectedUnit = function() return {} end }, { __index = savedUI })
	local rt = Keys[Gamepad.Map.RT.key]
	local function ev(msg, key, control) return HubGamepad.HandleInput({}, msg, key, control or false) end
	-- RT down, Shift, Right down/up, RT up: no Move To
	eq(ev(KeyEvents.KeyDown, rt), true)
	ev(KeyEvents.KeyDown, 16)
	ev(KeyEvents.KeyDown, Keys.VK_RIGHT)
	ev(KeyEvents.KeyUp, Keys.VK_RIGHT)
	ev(KeyEvents.KeyUp, 16)
	eq(ev(KeyEvents.KeyUp, rt), true)
	eq(#hotkeys, 0)
	-- RT down, modifier only, RT up: Move To
	ev(KeyEvents.KeyDown, rt)
	ev(KeyEvents.KeyDown, 16)
	ev(KeyEvents.KeyUp, 16)
	eq(ev(KeyEvents.KeyUp, rt), true)
	eq(hotkeys[1], "MoveTo")
	-- RT down, RT up: Move To again; a KeyUp without a KeyDown acts
	ev(KeyEvents.KeyDown, rt)
	ev(KeyEvents.KeyUp, rt)
	eq(#hotkeys, 2)
	ev(KeyEvents.KeyUp, rt)
	eq(#hotkeys, 3)
	UI = savedUI
	mode = 7
end)

test("bare map: X opens the selected unit's browser when the cursor is on it, else selects at the cursor", function()
	mode = nil
	local unit = { GetX = function() return 3 end, GetY = function() return 4 end }
	UI.GetHeadSelectedUnit = function() return unit end
	press("X")
	eq(table.concat(calls, ","), "scan")
	cursorX = 5
	press("X")
	eq(table.concat(calls, ","), "select")
	cursorX = 3
	browser = false
	press("X")
	eq(table.concat(calls, ","), "select")
	UI.GetHeadSelectedUnit = function() return nil end
	browser = true
	press("X")
	eq(table.concat(calls, ","), "select")
end)

test("screen open: LB / RB reach the screen; Menu closes the production panel and opens the game menu", function()
	local said = {}
	OutputMessageToScreenReader = function(t) table.insert(said, t) end
	local shown = { ["/InGame/PartialScreens/ProductionPanel"] = true }
	ContextPtr = { LookUpControl = function(_, path)
		if shown[path] == nil then return nil end
		return { IsHidden = function() return false end }
	end }
	LuaEvents = setmetatable({}, { __index = function(_, name) return function() table.insert(calls, name) end end })
	HubCore.IsGamePopupOpen = function() return true end
	HubCore.OpenScreenIds = function() return { "ProductionPanel" } end
	HubCore.CloseMode = function() table.insert(calls, "closemode") end
	eq(press("Menu"), true)
	eq(table.concat(calls, ","), "CityPanel_ProductionClose,closemode,InGame_OpenInGameOptionsMenu")
	shown = { ["/InGame/CityStates"] = true }
	eq(press("Menu"), true)
	eq(table.concat(calls, ","), "")
	eq(said[1], "Close the screen first, " .. SRKey("Escape") .. " closes it")
	eq(press("LB"), false)		-- LB / RB pass through to a screen that handles them (its sections)
	eq(press("RB"), false)
	eq(#said, 1)
	HubCore.OpenScreenIds = function() return { "ProductionPanel", "SomeUnknownPopup" } end
	eq(press("LB"), true)		-- a screen that does not: the old hint, never silent
	eq(said[2], "Close the screen first, " .. SRKey("Escape") .. " closes it")
	HubCore.OpenScreenIds = function() return {} end
	HubCore.IsGamePopupOpen = function() return false end
end)

test("an open hub list with sections: LB / RB move them, the ring only past the last / first section of a ring list", function()
	mode = nil
	local handled = {}
	local edge = false
	local list = {
		HasTabs = function() return true end,
		AtTabEdge = function() return edge end,
		HandleInput = function(input) table.insert(handled, "list") return true end,
	}
	HubCore.m_mode = { name = "places", list = list }
	eq(press("RB"), true)
	eq(table.concat(handled, ","), "list")		-- KeyUp only
	eq(#calls, 0)
	edge = true
	handled = {}
	eq(press("RB"), true)
	eq(#handled, 0)
	eq(table.concat(calls, ","), "can:nil,ring")		-- on to the next ring list
	HubCore.m_mode = { name = "help", list = list }		-- not a ring list: sections wrap, never the ring
	handled = {}
	press("LB")
	eq(table.concat(handled, ","), "list")
	eq(#calls, 0)
	HubCore.m_mode = { name = "lenses", list = { HasTabs = function() return false end } }		-- no sections: the ring
	press("RB")
	eq(table.concat(calls, ","), "can:nil,ring")
	HubCore.m_mode = nil
	mode = 7
end)

test("PageUp / PageDown: swallowed in controller mode while a screen without a list is open, passed otherwise", function()
	Keys.VK_PRIOR, Keys.VK_NEXT = 33, 34
	HubCore.IsGamePopupOpen = function() return true end
	Gamepad.SetActive(true)
	HubCore.OpenScreenIds = function() return { "SomeUnknownPopup" } end
	eq(HubGamepad.HandleInput({}, KeyEvents.KeyDown, Keys.VK_NEXT, false), true)
	eq(HubGamepad.HandleInput({}, KeyEvents.KeyUp, Keys.VK_PRIOR, false), true)
	HubCore.OpenScreenIds = function() return { "ProductionPanel" } end		-- a KeyNavList screen consumes them itself
	eq(HubGamepad.HandleInput({}, KeyEvents.KeyDown, Keys.VK_NEXT, false), false)
	HubCore.OpenScreenIds = function() return { "ClimateScreen" } end		-- Climate hands PageDown to the game: swallowed
	eq(HubGamepad.HandleInput({}, KeyEvents.KeyDown, Keys.VK_NEXT, false), true)
	Gamepad.SetActive(false)		-- keyboard: PageDown still reaches the game
	HubCore.OpenScreenIds = function() return { "SomeUnknownPopup" } end
	eq(HubGamepad.HandleInput({}, KeyEvents.KeyDown, Keys.VK_NEXT, false), false)
	HubCore.IsGamePopupOpen = function() return false end
end)

test("research chooser open (not a game screen): LB / RB pass to its list, the ring stays closed", function()
	for k in pairs(calls) do calls[k] = nil end
	mode = nil
	HubCore.IsGamePopupOpen = function() return false end
	ContextPtr = { LookUpControl = function(_, path) if path == "/InGame/TopLevelHUD/ResearchChooser" then return { IsHidden = function() return false end } end end }
	eq(press("RB"), false)
	eq(press("LB"), false)
	eq(table.concat(calls, ","), "")
	ContextPtr = { LookUpControl = function() return nil end }
end)

test("leader scene beside the deal view counts as a bumper screen", function()
	eq(HubGamepad.AllIn({ "LeaderScene", "DiplomacyDealView" }, { LeaderScene = true, DiplomacyDealView = true }), true)
end)
