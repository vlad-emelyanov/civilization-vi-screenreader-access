-- MultiplayerText.lua: chat lines, durations, turn timer warnings, player notices
stub("engine")
include("MultiplayerText")

test("chat lines: all, team, private", function()
	eq(MPText_ChatLine("Anna", "all", "hello"), "Anna: hello")
	eq(MPText_ChatLine("Anna", "team", "hello"), "Anna, team: hello")
	eq(MPText_ChatLine("Anna", "private", "hello"), "Anna, private: hello")
end)

test("chat text: markup goes, a bracketed word stays, pins are named", function()
	eq(MPText_CleanChat("[color:ChatMessage_Global]hi [ICON_Capital] there[NEWLINE]you [ENDCOLOR]"), "hi there you")
	eq(MPText_CleanChat("  [sad]   ok "), "[sad] ok")
	eq(MPText_CleanChat("look [pin:1,2]"), "look map pin")
	eq(MPText_CleanChat(nil), "")
end)

test("durations", function()
	eq(MPText_Duration(80), "1 minute 20 seconds")
	eq(MPText_Duration(60), "1 minute")
	eq(MPText_Duration(120), "2 minutes")
	eq(MPText_Duration(45.2), "46 seconds")
	eq(MPText_Duration(1), "1 second")
	eq(MPText_Duration(0), "0 seconds")
	eq(MPText_Duration(-3), "0 seconds")
end)

test("timer warnings at 60, 30 and 10, once each", function()
	local w = {}
	eq(MPText_TimerDue(120, w), nil)
	eq(MPText_TimerDue(61, w), nil)
	eq(MPText_TimerDue(59.5, w), 60)
	eq(MPText_TimerDue(58, w), nil)
	eq(MPText_TimerDue(30, w), 30)
	eq(MPText_TimerDue(29, w), nil)
	eq(MPText_TimerDue(9.9, w), 10)
	eq(MPText_TimerDue(5, w), nil)
	eq(MPText_TimerDue(0, w), nil)
	-- a new turn (time above 60 again) rearms them
	eq(MPText_TimerDue(90, w), nil)
	eq(MPText_TimerDue(55, w), 60)
end)

test("a timer first seen late gives only the matching warning", function()
	local w = {}
	eq(MPText_TimerDue(25, w), 30)
	eq(MPText_TimerDue(24, w), nil)
	eq(MPText_TimerDue(8, w), 10)
	local w2 = {}
	eq(MPText_TimerDue(5, w2), 10)
	eq(MPText_TimerDue(4, w2), nil)
	eq(MPText_TimerDue(nil, w2), nil)
end)

test("a pending warning stays due until it is marked (gated warnings are not lost)", function()
	local w = {}
	eq(MPText_TimerPending(25, w), 30)
	eq(MPText_TimerPending(24, w), 30)
	MPText_TimerMark(30, w)
	eq(MPText_TimerPending(24, w), nil)
	eq(MPText_TimerPending(9, w), 10)
end)

test("a timer of 60 seconds or less warns again after the warned table is reset for a new turn", function()
	local w = {}
	eq(MPText_TimerDue(45, w), 60)
	eq(MPText_TimerDue(40, w), nil)
	w = {}
	eq(MPText_TimerDue(45, w), 60)
end)

test("timer wording", function()
	eq(MPText_TimerWarning(29.6), "30 seconds left in the turn")
	eq(MPText_TimerWarning(59.9), "1 minute left in the turn")
	eq(MPText_TimerItem(80), "Turn timer: 1 minute 20 seconds left")
end)

test("chat title and player notices", function()
	eq(MPText_ChatTitle(1), "Chat, 1 message")
	eq(MPText_ChatTitle(12), "Chat, 12 messages")
	eq(MPText_ChatTitle(0), "Chat, 0 messages")
	eq(MPText_PlayerNotice("Bob", "disconnected"), "Bob disconnected")
	eq(MPText_PlayerNotice("Bob", "reconnected"), "Bob reconnected")
	eq(MPText_PlayerNotice("Bob", "kicked"), "Bob was kicked")
	eq(MPText_PlayerNotice("Bob", "ai"), "Bob is now played by the computer")
end)
