-- HubPad.lua: the controller ring (pure RingStep; RingNext / RingPrev on stubbed hub modules)
stub("engine")
include("ScreenReader")
include("HubPad")

test("ring order", function()
	local names = {}
	for _, e in ipairs(HubPad.RING) do table.insert(names, e.name) end
	eq(table.concat(names, ","), "Notifications,Top panel,Lenses,Diplomacy,Screens,Places")
end)

test("RingStep from nil and from a non-member", function()
	eq(HubPad.RingStep(nil, 1), 1)
	eq(HubPad.RingStep(nil, -1), 6)
	eq(HubPad.RingStep("menu", 1), 1)
	eq(HubPad.RingStep("city report", -1), 6)
end)

test("RingStep from a member moves and wraps", function()
	eq(HubPad.RingStep("notifications", 1), 2)
	eq(HubPad.RingStep("notifications", -1), 6)
	eq(HubPad.RingStep("places", 1), 1)
	eq(HubPad.RingStep("places", -1), 5)
	eq(HubPad.RingStep("lenses", 1), 4)
	eq(HubPad.RingStep("civ", -1), 3)
end)

local opened
local canOpen
local refuse = {}
local function stubHub(missing)
	refuse = {}
	opened = nil
	canOpen = true
	HubCore = { m_mode = nil, Safe = function(name, f) return function(...) return f(...) end end }
	HubTargets = { CanOpenMode = function() return canOpen end }
	local function open(name) return function() opened = name; if not refuse[name] then HubCore.m_mode = { name = name } end end end
	HubRegions = { OpenNotifications = open("notifications"), OpenTopPanel = open("top") }
	HubLenses = { Open = open("lenses") }
	HubMenus = { OpenCivMenu = open("civ") }
	HubScreens = { Open = open("screens") }
	HubPlaces = { Open = open("places") }
	if missing then _G[missing] = nil end
end

test("RingNext from the map opens the first, RingPrev the last", function()
	stubHub()
	HubPad.RingNext()
	eq(opened, "notifications")
	stubHub()
	HubPad.RingPrev()
	eq(opened, "places")
end)

test("RingNext from a ring list opens the next", function()
	stubHub()
	HubCore.m_mode = { name = "notifications" }
	HubPad.RingNext()
	eq(opened, "top")
	HubCore.m_mode = { name = "places" }
	HubPad.RingNext()
	eq(opened, "notifications")
	HubCore.m_mode = { name = "top" }
	HubPad.RingPrev()
	eq(opened, "notifications")
end)

test("a refused CanOpenMode opens nothing", function()
	stubHub()
	canOpen = false
	HubPad.RingNext()
	eq(opened, nil)
end)

test("a missing module says not available", function()
	stubHub("HubLenses")
	HubCore.m_mode = { name = "top" }
	ClearPrinted()
	HubPad.RingNext()
	eq(Spoken()[1], "Lenses not available")
	eq(HubCore.m_mode.name, "civ")		-- and goes on to the next one
end)

test("an entry that refuses to open (no civilization met) is skipped", function()
	stubHub()
	refuse.civ = true
	HubCore.m_mode = { name = "lenses" }
	HubPad.RingNext()
	eq(HubCore.m_mode.name, "screens")
	refuse = { screens = true, places = true, notifications = true, top = true, lenses = true, civ = true }
	HubCore.m_mode = nil
	HubPad.RingNext()		-- nothing opens at all: no endless loop
	eq(HubCore.m_mode, nil)
end)

test("IsRingMode", function()
	eq(HubPad.IsRingMode("places"), true)
	eq(HubPad.IsRingMode("notifications"), true)
	eq(HubPad.IsRingMode("help"), false)
	eq(HubPad.IsRingMode(nil), false)
end)

test("BumperAction: sections of a ring list are sub-stops, the ring continues at the edges", function()
	eq(HubPad.BumperAction("lenses", false, false), "ring")			-- no sections: a plain ring stop
	eq(HubPad.BumperAction("places", true, false), "section")
	eq(HubPad.BumperAction("places", true, true), "ring")			-- last / first section: on to the next / previous ring list
	eq(HubPad.BumperAction("help", true, false), "section")
	eq(HubPad.BumperAction("help", true, true), "section")			-- outside the ring the sections wrap
	eq(HubPad.BumperAction(nil, false, false), "ring")
end)
