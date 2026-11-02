-- KeyNavSetup wording: value first ("Prince, Difficulty"), section after the content, Left/Right and Space say only what changed.
stub("engine")
include("ScreenReader")
include("KeyNavSetup")

KeyNavEditBox_IsEditing = function() return false end
Network = { BroadcastGameConfig = function() end }
local function Params()
	return { SetParameterValue = function(self, parameter, v) parameter.Value = v end }
end

local diff = { Name = "Difficulty", Value = { Name = "Prince", Value = 2 },
	Values = { { Name = "Settler", Value = 1 }, { Name = "Prince", Value = 2 }, { Name = "King", Value = 3 } } }

local function newNav(item)
	return KeyNavSetup_NewController({
		buildItems = function() return { item } end,
		isActive = function() return true end,
		onBack = function() end,
	})
end

test("value first, field second", function()
	eq(KeyNavSetup_ValueText("Prince", "Difficulty"), "Prince, Difficulty")
end)

test("section comes after the content", function()
	eq(KeyNavSetup_ValueText("Prince", "Difficulty", "Setup"), "Prince, Difficulty, Setup")
	eq(KeyNavSetup_CheckText("Science Victory", true, "Victory Conditions"), "Science Victory: checked, Victory Conditions")
	eq(KeyNavSetup_CheckText("Science Victory", false), "Science Victory: unchecked")
end)

test("an empty value gives no leading comma", function()
	eq(KeyNavSetup_ValueText("", "Difficulty"), "Difficulty")
	eq(KeyNavSetup_ValueText(nil, "Difficulty", "Setup"), "Difficulty, Setup")
end)

test("pulldown: focus is value, field, hint; Left/Right say only the value", function()
	g_GameParameters = Params()
	diff.Value = diff.Values[2]
	local item = KeyNavSetup_PulldownItem(nil, diff, "Difficulty")
	item.key = "d"
	local nav = newNav(item)
	ClearPrinted()
	nav.Focus(item, false)
	listeq(Spoken(), { "Prince, Difficulty, dropdown, Left/Right or Enter to change" })
	ClearPrinted()
	nav.HandleKey(Keys.VK_RIGHT)
	listeq(Spoken(), { "King" })
	ClearPrinted()
	nav.HandleKey(Keys.VK_RIGHT)	-- end of the range: still answers
	listeq(Spoken(), { "King" })
end)

test("pulldown: Enter lists with the field as title, Escape and Enter read the new form", function()
	g_GameParameters = Params()
	diff.Value = diff.Values[2]
	local item = KeyNavSetup_PulldownItem(nil, diff, "Difficulty")
	item.key = "d"
	local nav = newNav(item)
	nav.Focus(item, false)
	ClearPrinted()
	nav.HandleKey(Keys.VK_RETURN)
	eq(Spoken()[1]:sub(1, 28), "Difficulty, Prince, 2 of 3. ")
	ClearPrinted()
	nav.HandleKey(Keys.VK_ESCAPE)
	listeq(Spoken(), { "Cancelled, Prince, Difficulty" })
	nav.HandleKey(Keys.VK_RETURN)
	nav.HandleKey(Keys.VK_DOWN)
	ClearPrinted()
	nav.HandleKey(Keys.VK_RETURN)
	listeq(Spoken(), { "King, Difficulty" })
end)

test("leader: value is the 'Leader, Civ' text of the list", function()
	g_GameParameters = Params()
	GetPlayerInfo = function() return { CivilizationName = "Rome" } end
	local leader = { Name = "Leader", Value = { Name = "Trajan", Value = "LEADER_TRAJAN", Domain = "d" },
		Values = { { Name = "Trajan", Value = "LEADER_TRAJAN", Domain = "d" }, { Name = "Pericles", Value = "LEADER_PERICLES", Domain = "d" } } }
	local item = KeyNavSetup_LeaderItem(nil, Params(), leader, "Leader")
	item.key = "l"
	local nav = newNav(item)
	ClearPrinted()
	nav.Focus(item, false)
	listeq(Spoken(), { "Trajan, Rome, Leader, dropdown, Left/Right or Enter to change" })
	GetPlayerInfo = nil
end)

test("map button: value first, Left/Right only the new map", function()
	local map = { Name = "Map", Value = { Name = "Continents", Value = 1 },
		Values = { { Name = "Continents", Value = 1 }, { Name = "Pangaea", Value = 2 } } }
	g_GameParameters = Params()
	local item = KeyNavSetup_MapItem(nil, { Map = map }, "Map Type", function() end)
	item.key = "m"
	local nav = newNav(item)
	ClearPrinted()
	nav.Focus(item, false)
	listeq(Spoken(), { "Continents, Map Type" })
	ClearPrinted()
	nav.HandleKey(Keys.VK_RIGHT)
	listeq(Spoken(), { "Pangaea" })
end)

test("checkbox: Space says only checked / unchecked", function()
	local p = { Value = false }
	g_GameParameters = Params()
	local item = { key = "c", kind = "checkbox",
		valueText = function() return p.Value and "checked" or "unchecked" end,
		getText = function() return KeyNavSetup_CheckText("Science Victory", p.Value, "Victory Conditions") end,
		toggle = function() p.Value = not p.Value end }
	local nav = newNav(item)
	ClearPrinted()
	nav.Focus(item, false)
	listeq(Spoken(), { "Science Victory: unchecked, Victory Conditions" })
	ClearPrinted()
	nav.HandleKey(Keys.VK_SPACE)
	listeq(Spoken(), { "checked" })
end)
