-- HubSettle action tile browser (M6): wording of the entries and the arrival, arming Enter with the action
stub("engine")
Keys.VK_SHIFT, Keys.VK_CONTROL, Keys.VK_ALT = 16, 17, 18
local world = stub("world").new{ width = 30, height = 20 }
world:install()
include("ScreenReader")
include("PlotDescription")
include("HubCore")
include("HubEnemies")

KeyNavList_Create = function() return {} end
local realInclude = include
include = function(name)
	if name == "BuildScan" then return end
	return realInclude(name)
end
BuildScan_Improvements = function() return nil end
HubMenus = {}
HubCursor = {}
HubTargets = {}
local path = ROOT .. "/ScreenReaderAccess/Assets/UI/Accessibility/HubSettle.lua"
local chunk, err = loadstring(sr_read(path), "@" .. path)
assert(chunk, err)
chunk()

local euclid = { verb = "activate", verb3 = "activates", what = "Euclid" }
local archaeologist = { verb = "excavate", verb3 = "excavates", what = "" }

test("action wording", function()
	eq(HubSettle.ActionPhrase(euclid), "activates Euclid")
	eq(HubSettle.ActionPhrase(archaeologist), "excavates")
	eq(HubSettle.ActionInfinitive(euclid), "activate Euclid")
	eq(HubSettle.ArrivalActionText(euclid, true, true), "Enter activates Euclid")
	eq(HubSettle.ArrivalActionText(euclid, false, true), "Activate Euclid next turn: select it and press Enter")
	eq(HubSettle.ArrivalActionText(euclid, true, false), "Select it and press Enter to activate Euclid")
end)

test("tile entries", function()
	eq(HubSettle.ActItemText({ here = true, name = "Rome's Campus" }, euclid), "here, Rome's Campus, Enter activates Euclid")
	eq(HubSettle.ActItemText({ name = "Rome's Campus", relative = "3 tiles north-east", turns = 2 }, euclid),
		"Rome's Campus, 3 tiles north-east, 2 turns")
	eq(HubSettle.ActItemText({ name = "Antiquity Site", relative = "5 tiles west", turns = 1, position = "2 tiles south of Rome" }, archaeologist),
		"Antiquity Site, 5 tiles west, 1 turn, 2 tiles south of Rome")
	eq(HubSettle.ActItemText({ name = "Hills", relative = "9 tiles east" }, euclid), "Hills, 9 tiles east")
end)

test("arrival of a unit sent to act arms Enter with the action", function()
	HubSettle.m_pending = nil
	local plot = Map.GetPlot(4, 4)
	local unit = { GetID = function() return 9 end, GetMovesRemaining = function() return 2 end }
	UI.GetHeadSelectedUnit = function() return unit end
	eq(HubSettle.OnArrived(unit, plot, { build = { type = "ACTION", name = "activate Euclid", act = euclid } }), "Enter activates Euclid")
	assert(HubSettle.m_pending ~= nil and HubSettle.m_pending.act == euclid)
	HubSettle.m_pending = nil
end)
