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

-- The Tab menu starts with the browser X opens (HubSettle.BrowserFor); a unit without one gets only its actions
local function openMenuFor(browser)
	local saved = { le = LuaEvents, ui = UI, players = Players, targets = HubTargets, settle = HubSettle }
	local opened = { browser = 0 }
	LuaEvents = { SRA_RequestUnitActions = function() HubMenus.OnUnitActionsReceived(1, { { id = 1, tag = 1, name = "Fortify", disabled = false, reason = "", detail = "" } }) end,
		SRA_RunUnitAction = function() end }
	local unit = { GetOwner = function() return 0 end, GetName = function() return "Settler" end, GetID = function() return 1 end }
	UI = setmetatable({ GetHeadSelectedUnit = function() return unit end, GetHeadSelectedCity = function() return nil end, GetInterfaceMode = function() return 0 end }, { __index = saved.ui })
	Players = Players or {}
	if Players[0] == nil then Players[0] = {} end
	HubTargets = { CanOpenMode = function() return true end }
	HubSettle = { BrowserFor = function() if browser then return { text = "Browse settle spots", open = function() opened.browser = opened.browser + 1 end } end end }
	local savedFormation = PlotDescription_FormationName
	PlotDescription_FormationName = function(_, name) return name end
	ClearPrinted()
	HubMenus.ToggleUnitMenu()
	local restore = function() PlotDescription_FormationName = savedFormation; LuaEvents, UI, Players, HubTargets, HubSettle = saved.le, saved.ui, saved.players, saved.targets, saved.settle end
	return opened, restore
end

test("a settler's menu starts with Browse settle spots; Space explains; Enter opens the browser", function()
	local opened, restore = openMenuFor(true)
	local said = table.concat(Spoken(), " | ")
	assert(said:find("Browse settle spots", 1, true), said)
	local list = HubCore.m_mode.list
	ClearPrinted()
	list.HandleInput(Input{ key = Keys.VK_SPACE, up = true })
	assert(table.concat(Spoken(), " "):find("Opens the same browser as the X key", 1, true))
	list.HandleInput(Input{ key = Keys.VK_RETURN, up = true })
	eq(opened.browser, 1)
	eq(HubCore.m_mode, nil)
	restore()
end)

test("a unit without a browser gets no browse entry", function()
	local opened, restore = openMenuFor(false)
	local said = table.concat(Spoken(), " | ")
	assert(not said:find("Browse", 1, true), said)
	assert(said:find("Fortify", 1, true), said)
	HubCore.CloseMode(false, false)
	restore()
end)
