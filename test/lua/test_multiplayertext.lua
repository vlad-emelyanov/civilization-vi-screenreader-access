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

test("staging room: mod download, host, loaded game, missing humans", function()
	eq(MPText_ModDownload("Anna", 2, 3), "Anna is downloading mods, 2 of 3 left")
	eq(MPText_ModsReady("Anna"), "Anna has the mods")
	eq(MPText_ModRowStatus(1, 3), "downloading mods, 1 of 3 left")
	eq(MPText_ModStepChanged(nil, 3), true)
	eq(MPText_ModStepChanged(3, 3), false)
	eq(MPText_ModStepChanged(3, 2), true)
	eq(MPText_HostNotice("Anna", false), "Anna is now the host")
	eq(MPText_HostNotice("Anna", true), "You are now the host")
	eq(MPText_LoadedGame(3, 1), "Loaded game, 3 human seats, 1 still empty")
	eq(MPText_LoadedGame(1, 0), "Loaded game, 1 human seat, all taken")
	eq(MPText_MissingHumans({"Trajan", "Cleopatra"}), "Waiting for the players: Trajan, Cleopatra")
	eq(MPText_MissingHumans({}), nil)
	eq(MPText_StillWaiting(), "Still waiting for the others")
end)

test("mod tracking: progress steps, ready once, ready arriving late", function()
	local st = { remaining = {}, readyLast = {} }
	eq(MPText_ModTrack(st, 2, 1, 3, 3, false), "download")
	eq(MPText_ModTrack(st, 2, 1, 3, 3, false), nil)		-- same step (bytes progress)
	eq(MPText_ModTrack(st, 2, 1, 2, 3, false), "download")
	eq(st.remaining[2].remaining, 2)
	eq(MPText_ModTrack(st, 2, 0, 0, 3, true), "ready")		-- finish callback with ready
	eq(st.remaining[2], nil)
	eq(MPText_ModTrack(st, 2, 0, 0, 3, true), nil)			-- no repeat
	-- ready never arrives with the finish callback: nothing then, "has the mods" when it does
	eq(MPText_ModTrack(st, 3, 1, 1, 1, false), "download")
	eq(MPText_ModTrack(st, 3, 0, 0, 1, false), nil)
	eq(MPText_ModTrack(st, 3, 0, 0, 1, true), "ready")
	eq(MPText_ModTrack(st, 3, 0, 0, 1, true), nil)
	-- a player never seen downloading who is ready: silent
	eq(MPText_ModTrack(st, 4, 0, 0, 0, true), nil)
end)
