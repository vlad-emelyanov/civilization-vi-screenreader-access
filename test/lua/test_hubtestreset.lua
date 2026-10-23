-- HubCore.TestResetState (regression harness: is the game back in the state a fresh load gives?)
stub("engine")
include("HubCore")

local gold, units, cities, turnActive = 100, 3, 1, true
local selected, resets, controls = nil, 0, {}
local fakeObject = function(id) return { GetID = function() return id end } end
local objects = { [7] = fakeObject(7), [9] = fakeObject(9) }

Game.GetLocalPlayer = function() return 0 end
Game.GetCurrentGameTurn = function() return 50 end
InterfaceModeTypes = { SELECTION = 1 }
local mode = 1
UI.GetInterfaceMode = function() return mode end
UI.GetHeadSelectedUnit = function() if selected and selected.kind == "u" then return objects[selected.id] end end
UI.GetHeadSelectedCity = function() if selected and selected.kind == "c" then return objects[selected.id] end end
UI.DeselectAll = function() selected = nil end
UI.SelectUnit = function(u) selected = { kind = "u", id = u:GetID() } end
UI.SelectCity = function(c) selected = { kind = "c", id = c:GetID() } end
Players = { [0] = {
	IsTurnActive = function() return turnActive end,
	GetTreasury = function() return { GetGoldBalance = function() return gold + 0.4 end } end,
	GetUnits = function() return { GetCount = function() return units end, FindID = function(_, id) return objects[id] end } end,
	GetCities = function() return { GetCount = function() return cities end, FindID = function(_, id) return objects[id] end } end,
} }
HubCursor = { ResetCursor = function() resets = resets + 1 end }
local function control(hidden, children)
	return { IsHidden = function() return hidden end, GetID = function() return "x" end, GetChildren = function() return children or {} end }
end
ContextPtr = { LookUpControl = function(_, path) return controls[path] end }
HubCore.IsLocalPlayerActive = function() return true end
HubCore.m_ready = true

test("plain map mode is clean and resets the cursor", function()
	local r = HubCore.TestResetState(nil)
	eq(r, "clean t=50;g=100;u=3;c=1|none")
	eq(resets, 1)
end)

test("an open options menu, popup, hub mode, target mode or other turn is dirty", function()
	controls["/InGame/TopOptionsMenu"] = control(false)
	assert(HubCore.TestResetState(nil):find("^dirty open: TopOptionsMenu"))
	controls["/InGame/TopOptionsMenu"] = nil
	controls["/InGame/Civilopedia"] = control(false)
	assert(HubCore.TestResetState(nil):find("^dirty open: Civilopedia"))
	controls["/InGame/Civilopedia"] = nil
	controls["/InGame/Screens"] = control(false, { control(false) })
	assert(HubCore.TestResetState(nil):find("^dirty open: Screens/x"))
	controls["/InGame/Screens"] = nil
	HubCore.m_mode = { name = "menu" }
	eq(HubCore.TestResetState(nil), "dirty hub mode menu")
	HubCore.m_mode = nil
	mode = 5
	assert(HubCore.TestResetState(nil):find("^dirty interface mode 5"))
	mode = 1
	turnActive = false
	eq(HubCore.TestResetState(nil), "dirty not our turn")
	turnActive = true
	local before = resets
	HubCore.m_ready = false
	assert(HubCore.TestResetState(nil):find("^dirty hub not ready"))
	HubCore.m_ready = true
	eq(resets, before, "a dirty answer resets nothing")
end)

test("changed gold, units or turn state is dirty against the baseline", function()
	local base = HubCore.TestResetState(nil):match("^clean (.*)$")
	eq(HubCore.TestResetState(base):sub(1, 5), "clean")
	gold = 90
	assert(HubCore.TestResetState(base):find("^dirty changed: t=50;g=90"))
	gold = 100
	units = 4
	assert(HubCore.TestResetState(base):find("^dirty changed"))
	units = 3
end)

test("the selection is put back to the baseline", function()
	selected = { kind = "u", id = 7 }
	local base = HubCore.TestResetState(nil):match("^clean (.*)$")
	assert(base:find("|u:7$"))
	selected = { kind = "c", id = 9 }
	eq(HubCore.TestResetState(base), "clean " .. base)
	eq(selected.kind .. selected.id, "u7")
	selected = nil
	eq(HubCore.TestResetState(base), "clean " .. base)
	selected = { kind = "u", id = 7 }
	local noneBase = "t=50;g=100;u=3;c=1|none"
	eq(HubCore.TestResetState(noneBase), "clean " .. noneBase)
	eq(selected, nil)
end)
