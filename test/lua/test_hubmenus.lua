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

test("action result text names the great person and the effect", function()
	eq(HubMenus.ActionResultText("Retire Timur: Grants 1 promotion level and +25 percent combat experience"), "Timur retired: Grants 1 promotion level and +25 percent combat experience")
	eq(HubMenus.ActionResultText("Activate Mary Leakey: Gives a boost"), "Mary Leakey activated: Gives a boost")
	eq(HubMenus.ActionResultText("Retire Timur"), "Timur retired")
	eq(HubMenus.ActionResultText("Fortify"), "Fortify")
	eq(HubMenus.ActionResultText("Found Religion"), "Found Religion")
end)

test("menu keys stay unique for items with the same tag and name (two WMD strikes)", function()
	local saved_le, saved_ui = LuaEvents, UI
	local list = {
		{ id = 1, tag = 7, name = "WMD Strike", disabled = true, reason = "No available warhead.", detail = "" },
		{ id = 2, tag = 7, name = "WMD Strike", disabled = true, reason = "No available warhead.", detail = "" },
		{ id = 3, tag = 7, name = "WMD Strike", disabled = false, reason = "", detail = "" },
		{ id = 4, tag = 8, name = "Delete", disabled = false, reason = "", detail = "" },
	}
	LuaEvents = { SRA_RequestUnitActions = function() HubMenus.OnUnitActionsReceived(1, list) end }
	UI = setmetatable({ GetHeadSelectedUnit = function() return {} end }, { __index = saved_ui })
	local items = HubMenus.FetchMenuItems(false)
	LuaEvents, UI = saved_le, saved_ui
	eq(#items, 4)
	local seen = {}
	for _, item in ipairs(items) do
		eq(seen[item.key], nil)
		seen[item.key] = true
	end
	eq(items[1].key, "7|WMD Strike")
	eq(items[2].key, "7|WMD Strike#2")
	eq(items[3].key, "7|WMD Strike#3")
end)

test("rebase / deploy result names the target", function()
	eq(HubMenus.TargetPhrase("Rebasing", { city = "Lugdunum" }), "Rebasing to Lugdunum")
	eq(HubMenus.TargetPhrase("Rebasing", { district = "Aerodrome" }), "Rebasing to Aerodrome")
	eq(HubMenus.TargetPhrase("Deploying", nil), "Deploying")
	eq(HubMenus.TargetPhrase("Deploying", {}), "Deploying")
end)

test("SRActionResultText is the shared wording (Tab menu and U key)", function()
	eq(SRActionResultText("Activate Jakob Fugger: Gives gold"), "Jakob Fugger activated: Gives gold")
	eq(SRActionResultText("Found Religion"), "Found Religion")
end)
