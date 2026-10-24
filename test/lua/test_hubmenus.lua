-- HubMenus: Repair is spoken once (event path and fallback timer share a claim)
stub("engine")
local world = stub("world").new{ width = 30, height = 20 }
world:install()
include("ScreenReader")
include("KeyboardNavigation")
include("KeyNavList")
include("PlotDescription")
include("HubCore")
include("HubMenus")

test("repair claim: first speaker wins, a later order speaks again", function()
	HubMenus.m_repairSpoken = {}
	eq(HubMenus.ClaimRepairSpeech(7, 10.0), true)
	eq(HubMenus.ClaimRepairSpeech(7, 10.6), false)
	eq(HubMenus.ClaimRepairSpeech(8, 10.6), true)
	eq(HubMenus.ClaimRepairSpeech(7, 12.5), true)
end)

test("repair text", function()
	eq(HubMenus.RepairText("Iron Mine"), "Repairing Iron Mine, done next turn")
	eq(HubMenus.RepairText(""), "Repairing, done next turn")
end)
