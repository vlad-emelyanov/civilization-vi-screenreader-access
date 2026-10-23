-- HubCore speech hold (HubCore.Announce / SetSpeechHold / UpdateSpeech), HubAnnounce loyalty text, SRDescriptionFirst
stub("engine")
include("ScreenReader")
include("HubCore")

local function reset() HubCore.ClearSpeechHold(); ClearPrinted(); Clock.now = 100 end
local function tick(seconds) Clock.now = Clock.now + seconds; HubCore.UpdateSpeech(seconds) end

test("without a hold an announcement is spoken at once", function()
	reset()
	HubCore.Announce("Settler", true, "selection")
	eq(table.concat(Spoken(), "|"), "Settler")
end)

test("a hold queues, release speaks in order after 0.4 s", function()
	reset()
	HubCore.SetSpeechHold("BoostUnlocked", true)
	HubCore.Announce("Turn 5", true, "turn")
	HubCore.Announce("Settler", true, "selection")
	eq(#Spoken(), 0)
	tick(1)
	eq(#Spoken(), 0, "still held")
	HubCore.SetSpeechHold("BoostUnlocked", false)
	tick(0.2)
	eq(#Spoken(), 0, "release delay")
	tick(0.3)
	eq(table.concat(Spoken(), "|"), "Turn 5|Settler")
end)

test("duplicates dropped, a newer selection replaces an older one with its settle sentence", function()
	reset()
	HubCore.SetSpeechHold("a", true)
	HubCore.Announce("Warrior", true, "selection")
	HubCore.Announce("Settle at x", true, "settle")
	HubCore.Announce("Turn 5", true, "turn")
	HubCore.Announce("Turn 5", true, "turn")
	HubCore.Announce("Settler", true, "selection")
	HubCore.SetSpeechHold("a", false)
	tick(0.5)
	eq(table.concat(Spoken(), "|"), "Turn 5|Settler")
end)

test("the queue keeps 6 entries", function()
	reset()
	HubCore.SetSpeechHold("a", true)
	for i = 1, 9 do HubCore.Announce("e" .. i, true) end
	HubCore.SetSpeechHold("a", false)
	tick(0.5)
	eq(table.concat(Spoken(), "|"), "e4|e5|e6|e7|e8|e9")
end)

test("two holders: released only when both are gone", function()
	reset()
	HubCore.SetSpeechHold("a", true)
	HubCore.SetSpeechHold("b", true)
	HubCore.Announce("x", true)
	HubCore.SetSpeechHold("a", false)
	tick(1)
	eq(#Spoken(), 0)
	HubCore.SetSpeechHold("b", false)
	tick(0.5)
	eq(table.concat(Spoken(), "|"), "x")
end)

test("a hold expires after 60 s", function()
	reset()
	HubCore.SetSpeechHold("a", true)
	HubCore.Announce("x", true)
	tick(59)
	eq(#Spoken(), 0)
	tick(2)	-- expired: release delay starts
	tick(0.5)
	eq(table.concat(Spoken(), "|"), "x")
end)

test("an announcement spoken just before the hold is queued again", function()
	reset()
	HubCore.Announce("Turn 5", true, "turn")
	eq(#Spoken(), 1)
	Clock.now = Clock.now + 0.5
	HubCore.SetSpeechHold("a", true)
	HubCore.Announce("Settler", true, "selection")
	HubCore.SetSpeechHold("a", false)
	tick(0.5)
	eq(table.concat(Spoken(), "|"), "Turn 5|Turn 5|Settler")
end)

test("an older announcement is not repeated", function()
	reset()
	HubCore.Announce("Turn 5", true, "turn")
	Clock.now = Clock.now + 5
	HubCore.SetSpeechHold("a", true)
	HubCore.SetSpeechHold("a", false)
	tick(1)
	eq(#Spoken(), 1)
end)

test("ClearSpeechHold forgets holds and queue", function()
	reset()
	HubCore.SetSpeechHold("a", true)
	HubCore.Announce("x", true)
	HubCore.ClearSpeechHold()
	tick(1)
	eq(#Spoken(), 0)
	HubCore.Announce("y", true)
	eq(table.concat(Spoken(), "|"), "y")
end)

test("keys are not held: SayResult after a key speaks at once", function()
	reset()
	HubCore.m_lastKeyTime = Clock.now
	HubCore.SetSpeechHold("a", true)
	HubCore.SayResult("Fortified")
	eq(table.concat(Spoken(), "|"), "Fortified")
	Clock.now = Clock.now + 5
	HubCore.SayResult("Road built")
	eq(#Spoken(), 1, "own-less result waits")
end)

-- loyalty
include("HubAnnounce")
test("loyalty text", function()
	eq(HubAnnounce.LoyaltyText(100, 100, 0), "full loyalty")
	eq(HubAnnounce.LoyaltyText(100, 100, 2.4), "full loyalty")
	eq(HubAnnounce.LoyaltyText(100, 100, -1), "loyalty 100 of 100, minus 1 per turn")
	eq(HubAnnounce.LoyaltyText(72, 100, -3), "loyalty 72 of 100, minus 3 per turn")
	eq(HubAnnounce.LoyaltyText(72.4, 100, 2), "loyalty 72.4 of 100, plus 2 per turn")
	eq(HubAnnounce.LoyaltyText(50, 100, 0), "loyalty 50 of 100")
end)

-- production description
test("description comes first, name once", function()
	local Lookup = Locale and Locale.Lookup
	Locale = Locale or {}
	Locale.Lookup = function(s) return s end
	eq(SRDescriptionFirst("Settler", "Used to found new cities.", "SETTLER[NEWLINE]Moves 2[NEWLINE]Used to found new cities.[NEWLINE]Cost 30"),
		"Settler: Used to found new cities. Moves 2. Cost 30")
	eq(SRDescriptionFirst("Granary", nil, "GRANARY[NEWLINE]+1 food"), "Granary: +1 food")
	eq(SRDescriptionFirst("Granary", "A store.", "GRANARY"), "Granary: A store.")
	Locale.Lookup = Lookup
end)

test("a queued ready sentence is dropped when the turn is no longer ready", function()
	reset()
	local ready = true
	local real = HubAnnounce.IsReadyNow
	local realWatch = HubAnnounce.UpdateReadyWatch
	HubAnnounce.UpdateReadyWatch = function() end
	HubAnnounce.IsReadyNow = function() return ready end
	HubCore.SetSpeechHold("a", true)
	HubCore.Announce("All done. Enter ends the turn", true, "ready")
	HubCore.Announce("Settler", true, "selection")
	ready = false
	HubCore.SetSpeechHold("a", false)
	tick(0.5)
	eq(table.concat(Spoken(), "|"), "Settler")
	reset()
	ready = true
	HubCore.SetSpeechHold("a", true)
	HubCore.Announce("All done. Enter ends the turn", true, "ready")
	HubCore.SetSpeechHold("a", false)
	tick(0.5)
	eq(table.concat(Spoken(), "|"), "All done. Enter ends the turn")
	HubAnnounce.IsReadyNow = real
	HubAnnounce.UpdateReadyWatch = realWatch
end)
