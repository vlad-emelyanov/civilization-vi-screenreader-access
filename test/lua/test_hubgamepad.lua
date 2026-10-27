-- HubGamepad.HandleInput in a target mode: X scans for foreign units, LB / RB open the places list, the left stick click moves the target to the capital
stub("engine")
for i = 13, 24 do Keys["VK_F" .. i] = 100 + i end
LuaEvents = setmetatable({}, { __index = function() return function() end end })
include("Gamepad")

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
HubSettle = { ScanKey = function() table.insert(calls, "scan") end }
HubPlaces = { TogglePlaces = function() table.insert(calls, "places") end }
HubCursor = { SelectAtCursor = function() table.insert(calls, "select") end }
HubPad = { RingNext = function() table.insert(calls, "ring") end, RingPrev = function() table.insert(calls, "ring") end }
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
