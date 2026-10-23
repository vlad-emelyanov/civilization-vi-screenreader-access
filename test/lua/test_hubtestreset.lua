-- HubCore.TestResetState (regression harness: is the game back in the state a fresh load gives?)
stub("engine")
include("HubCore")

local gold, units, cities, turnActive = 100, 3, 1, true
local selected, resets, controls = nil, 0, {}
local fakeObject = function(id) return { GetID = function() return id end } end
local objects = { [7] = fakeObject(7), [9] = fakeObject(9) }
local unitX, production, research = 4, 100, 12
local fakeUnit = { GetID = function() return 7 end, GetX = function() return unitX end, GetY = function() return 2 end,
	GetMovesRemaining = function() return 2 end, GetDamage = function() return 0 end, GetActivityType = function() return 0 end }
local fakeCity = { GetID = function() return 9 end, GetBuildQueue = function() return { GetCurrentProductionTypeHash = function() return production end } end }
local function members(obj) return function() return function(_, last) if last == nil then return 1, obj end end, nil, nil end end

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
	GetTechs = function() return { GetResearchingTech = function() return research end } end,
	GetCulture = function() return { GetProgressingCivic = function() return 3 end, GetNumPolicySlots = function() return 1 end, GetSlotPolicy = function() return 5 end } end,
	GetUnits = function() return { Members = members(fakeUnit), GetCount = function() return units end, FindID = function(_, id) return objects[id] end } end,
	GetCities = function() return { Members = members(fakeCity), GetCount = function() return cities end, FindID = function(_, id) return objects[id] end } end,
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
	assert(r:find("^clean t=50;g=100;u=3;c=1;h=%d+|none$"), r)
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

test("TestSnapshotText reports the state even when a screen is open", function()
	selected = { kind = "c", id = 9 }
	controls["/InGame/TopOptionsMenu"] = control(false)
	assert(HubCore.TestSnapshotText():find("^snap t=50;g=100;u=3;c=1;h=%d+|c:9$"))
	controls["/InGame/TopOptionsMenu"] = nil
	selected = nil
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
	local noneBase = HubCore.TestSnapshotText():match("^snap (.*)$"):gsub("|.*$", "|none")
	eq(HubCore.TestResetState(noneBase), "clean " .. noneBase)
	eq(selected, nil)
end)

test("a moved unit, a changed production or research is dirty against the baseline", function()
	selected = nil
	local base = HubCore.TestResetState(nil):match("^clean (.*)$")
	unitX = 5
	assert(HubCore.TestResetState(base):find("^dirty changed"))
	unitX = 4
	production = 101
	assert(HubCore.TestResetState(base):find("^dirty changed"))
	production = 100
	research = 13
	assert(HubCore.TestResetState(base):find("^dirty changed"))
	research = 12
	assert(HubCore.TestResetState(base):find("^clean"))
end)

test("pending hub state is dirty", function()
	HubCore.m_movers[7] = { dest = 1 }
	eq(HubCore.TestResetState(nil), "dirty pending move orders")
	HubCore.m_movers = {}
	HubCore.m_enterWatch = 0.5
	eq(HubCore.TestResetState(nil), "dirty Enter watch pending")
	HubCore.m_enterWatch = -1
	table.insert(HubCore.m_delayed, { time = 1 })
	eq(HubCore.TestResetState(nil), "dirty pending delayed calls")
	HubCore.m_delayed = {}
	HubCore.m_arrivalTimer = 0.8
	eq(HubCore.TestResetState(nil), "dirty pending arrival announcements")
	HubCore.m_arrivalTimer = -1
	table.insert(HubCore.m_arrivals, { text = "x" })
	eq(HubCore.TestResetState(nil), "dirty pending arrival announcements")
	HubCore.m_arrivals = {}
end)

test("an error inside the entry point becomes dirty error", function()
	local saved = Players[0].GetTechs
	Players[0].GetTechs = function() error("boom") end
	assert(HubCore.TestResetState(nil):find("^dirty error: .*boom"))
	assert(HubCore.TestSnapshotText():find("^dirty error: .*boom"))
	Players[0].GetTechs = saved
end)
