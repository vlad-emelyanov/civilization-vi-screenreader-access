-- HubAnnounce.LoyaltyWarningText / LoyaltyWarningLines (turn-start loyalty warning) and the confirm hold of the Enter watch.
-- The pure functions are extracted from the source (HubAnnounce itself needs the whole hub stub, see test_hubmodules.lua).
local f = assert(io.open("ScreenReaderAccess/Assets/UI/Accessibility/HubAnnounce.lua", "rb"))
local src = f:read("*a"):gsub("\r\n", "\n")
f:close()
local block = src:match("(local LOYALTY_WARN_TURNS.-\nfunction HubAnnounce%.LoyaltyWarningLines.-\nend)\n")
assert(block, "loyalty block not found")
local hold = src:match("(local CONFIRM_HOLD.-\nfunction HubAnnounce%.ConfirmPending.-\nend)\n")
assert(hold, "confirm block not found")
HubAnnounce = {}
HubCore = {}
Clock = { now = 10 }
UI = { GetElapsedTime = function() return Clock.now end }
local function strip(text)
	for _, t in ipairs({ "number", "string", "table", "boolean" }) do text = text:gsub("%s*:" .. t .. "%f[%A]", "") end
	return text
end
assert(loadstring(strip(block), "loyalty"))()
assert(loadstring(strip(hold), "confirm"))()

test("LoyaltyWarningText: one city", function()
	eq(HubAnnounce.LoyaltyWarningText("Lugdunum", 62, -19, 4, "Control+I"),
		"Lugdunum loyalty 62, falling 19 a turn, lost in 4 turns. Control+I on that city for why", "full")
	eq(HubAnnounce.LoyaltyWarningText("Rome", 40, -0.4, 3, nil), "Rome loyalty 40, falling less than 1 a turn, lost in 3 turns", "small fall")
	eq(HubAnnounce.LoyaltyWarningText("Lugdunum", 61.96, -2.54, 1, nil), "Lugdunum loyalty 62, falling 2.5 a turn, lost in 1 turn", "no hint, rounded")
end)

test("LoyaltyWarningLines: worst first, three at most, then a count", function()
	local function e(name, perTurn, turns) return { name = name, current = 50, perTurn = perTurn, turns = turns } end
	local lines = HubAnnounce.LoyaltyWarningLines({ e("A", -5, 6), e("B", -9, 2), e("C", -3, 2), e("D", -1, 8), e("E", -4, 7) }, "K")
	eq(#lines, 4, "three lines and a count")
	eq(lines[1], "B loyalty 50, falling 9 a turn, lost in 2 turns. K on that city for why", "soonest, steeper first")
	eq(lines[2]:sub(1, 1), "C", "second")
	eq(lines[3]:sub(1, 1), "A", "third")
	eq(lines[4], "and 2 more", "rest")
end)

test("LoyaltyWarningLines: far, rising or unknown conversions are not warned", function()
	local lines = HubAnnounce.LoyaltyWarningLines({
		{ name = "Far", current = 80, perTurn = -2, turns = 9 },
		{ name = "Rising", current = 80, perTurn = 2, turns = 3 },
		{ name = "Zero", current = 80, perTurn = -2, turns = 0 },
	}, nil)
	eq(#lines, 0, "none")
	eq(#HubAnnounce.LoyaltyWarningLines({}, nil), 0, "empty")
	eq(#HubAnnounce.LoyaltyWarningLines({ { name = "Edge", current = 10, perTurn = -2, turns = 8 } }, nil), 1, "8 turns is warned")
end)

test("Chooser owns Enter only in a chooser mode", function()
	eq(HubAnnounce.ChooserOwnsEnter(nil), false, "no mode")
	eq(HubAnnounce.ChooserOwnsEnter(12345), false, "unknown mode")
end)

test("Confirm hold: silent for 3 seconds or until cleared", function()
	Clock.now = 10
	eq(HubAnnounce.ConfirmPending(Clock.now), false, "idle")
	HubAnnounce.NoteConfirm()
	eq(HubAnnounce.ConfirmPending(11), true, "within")
	eq(HubAnnounce.ConfirmPending(13.5), false, "expired")
	HubAnnounce.NoteConfirm()
	HubAnnounce.ClearConfirm()
	eq(HubAnnounce.ConfirmPending(11), false, "cleared by the result")
	HubAnnounce.NoteConfirm()
	HubAnnounce.NoteConfirm(false)
	eq(HubAnnounce.ConfirmPending(11), false, "cleared by a failed confirm")
end)
