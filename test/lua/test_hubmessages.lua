-- HubMessages.lua: the history of the mod's own announcements (cap, repeat skip, newest first, sections, empty list)
stub("engine")
Keys.M = 77
local world = stub("world").new{ width = 30, height = 20 }
world:install()
include("ScreenReader")
include("KeyboardNavigation")
include("KeyNavList")
include("HubCore")
HubTargets = { CanOpenMode = function() return true end }
HubAnnounce = { PositionText = function(plot) return "2 tiles north of Rome" end }
include("HubMessages")

local turn = 1
Game.GetCurrentGameTurn = function() return turn end

local function reset() HubMessages.Clear(); turn = 1 end

test("newest first, one section per turn", function()
	reset()
	turn = 45
	HubMessages.Add("Turn 45, 1200 BC")
	turn = 46
	HubMessages.Add("Turn 46, 1190 BC")
	HubMessages.Add("Warrior spotted", 5)
	local items = HubMessages.BuildItems()
	eq(#items, 3)
	eq(items[1].text, "Warrior spotted")
	eq(items[1].section, "Turn 46")
	eq(items[2].text, "Turn 46, 1190 BC")
	eq(items[3].section, "Turn 45")
end)

test("the same text twice in one turn is skipped, even when not adjacent", function()
	reset()
	HubMessages.Add("Barbarians near Rome")
	HubMessages.Add("Barbarians near Rome")
	eq(HubMessages.Count(), 1)
	HubMessages.Add("Other")
	HubMessages.Add("Barbarians near Rome")
	eq(HubMessages.Count(), 2)
	turn = 2
	HubMessages.Add("Barbarians near Rome")
	eq(HubMessages.Count(), 3)
end)

test("a turn keeps at most 30 entries, its turn line stays", function()
	reset()
	turn = 7
	HubMessages.Add("Turn 7, 500 BC")
	for i = 1, 60 do HubMessages.Add("spotted " .. i) end
	eq(HubMessages.Count(), 30)
	local items = HubMessages.BuildItems()
	eq(items[1].text, "spotted 60")
	eq(items[30].text, "Turn 7, 500 BC")
	turn = 8
	HubMessages.Add("Turn 8, 490 BC")
	eq(HubMessages.Count(), 31)
end)

test("the history keeps the newest 100", function()
	reset()
	for i = 1, 130 do turn = 1 + math.floor(i / 10); HubMessages.Add("m" .. i) end
	eq(HubMessages.Count(), 100)
	local items = HubMessages.BuildItems()
	eq(items[1].text, "m130")
	eq(items[100].text, "m31")
end)

test("Space adds the turn and the position", function()
	reset()
	turn = 45
	HubMessages.Add("Archer spotted.", 3)
	HubMessages.Add("Plain line")
	local items = HubMessages.BuildItems()
	eq(items[1].detail(), "Plain line, turn 45")
	eq(items[2].detail(), "Archer spotted, turn 45, 2 tiles north of Rome")
end)

test("empty history says so", function()
	reset()
	ClearPrinted()
	HubMessages.Open()
	eq(Spoken()[1], "No messages yet")
end)

test("PlotIndexOf is nil for no position", function()
	eq(HubMessages.PlotIndexOf(nil, nil), nil)
end)

test("routine notification types are known; arrival lines drop them from the history", function()
	eq(HubMessages.IsRoutine("NOTIFICATION_COMMAND_UNITS"), true)
	eq(HubMessages.IsRoutine("NOTIFICATION_CHOOSE_CITY_PRODUCTION"), true)
	eq(HubMessages.IsRoutine("NOTIFICATION_BARBARIANS_SIGHTED"), false)
	local said, history = HubMessages.ArrivalTexts{ { text = "Choose research", routine = true }, { text = "Units need orders", routine = true } }
	eq(said, "2 new notifications: Choose research, Units need orders")
	eq(history, nil)
	said, history = HubMessages.ArrivalTexts{ { text = "Choose research", routine = true }, { text = "Barbarians sighted", plotIndex = 7 } }
	eq(history, "Notification: Barbarians sighted")
	said, history = HubMessages.ArrivalTexts{ { text = "A" }, { text = "B", routine = true }, { text = "C" } }
	eq(history, "2 new notifications: A, C")
	eq(said, "3 new notifications: A, B, C")
	said, history = HubMessages.ArrivalTexts{ { text = "A", plotIndex = 3 } }
	eq(history, "Notification: A")
end)
