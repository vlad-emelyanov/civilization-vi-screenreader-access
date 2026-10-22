-- ScreenReader.lua: markup stripping in OutputMessageToScreenReader / CleanTextForSpeech
stub("engine")
include("ScreenReader")

local function say(msg, nointerrupt)
	ClearPrinted()
	OutputMessageToScreenReader(msg, nointerrupt)
	return Printed[1]
end

test("plain text gets the prefix", function()
	eq(say("Hello"), "#SCREENREADER - Hello")
end)

test("nointerrupt uses the other prefix", function()
	eq(say("Hello", true), "#SCREENREADER[NOINTERRUPT] - Hello")
end)

test("empty or markup-only messages print nothing", function()
	eq(say(""), nil)
	eq(say("[COLOR_Red][ENDCOLOR]"), nil)
	eq(say(nil), nil)
end)

test("NEWLINE becomes a pause, spaces collapse", function()
	eq(say("One[NEWLINE]Two   three"), "#SCREENREADER - One, Two three")
	eq(say("[NEWLINE][NEWLINE]Two[NEWLINE]"), "#SCREENREADER - Two")
end)

test("colour, link and tab markup is dropped", function()
	eq(say("[COLOR:Red]Danger[ENDCOLOR] ahead"), "#SCREENREADER - Danger ahead")
	eq(say("[COLOR_Civ6Red]Danger[ENDCOLOR]"), "#SCREENREADER - Danger")
	eq(say("a[TAB]b"), "#SCREENREADER - a b")
	eq(say("[LINK:foo]Rome[ENDLINK]"), "#SCREENREADER - Rome")
end)

test("other bracket text is real text", function()
	eq(say("[KOS] Bob declared war"), "#SCREENREADER - [KOS] Bob declared war")
end)

test("percent is spoken as a word", function()
	eq(say("50% of the tiles"), "#SCREENREADER - 50 percent of the tiles")
end)

test("known icons become words, decorative ones vanish", function()
	eq(say("+2 [ICON_Food]"), "#SCREENREADER - +2 Food")
	eq(say("+3 [ICON_Production] [ICON_Gold]"), "#SCREENREADER - +3 Production Gold")
	eq(say("Press [ICON_Bolt] now"), "#SCREENREADER - Press now")
end)

test("an icon is not repeated when the text already says the word", function()
	eq(say("[ICON_Gold] Gold: 20"), "#SCREENREADER - Gold: 20")
	eq(say("Production [ICON_Production]: 5"), "#SCREENREADER - Production : 5")
	eq(say("[ICON_Strength] Combat Strength 10"), "#SCREENREADER - Combat Strength 10")
	eq(say("+1 [ICON_Amenities] Amenity"), "#SCREENREADER - +1 Amenity")
end)

test("CleanTextForSpeech", function()
	eq(CleanTextForSpeech(nil), "")
	eq(CleanTextForSpeech("A[NEWLINE]B"), "A. B")
	eq(CleanTextForSpeech("[COLOR:Red]Hot[ENDCOLOR] +1 [ICON_Culture]"), "Hot +1 Culture")
	eq(CleanTextForSpeech("  [ICON_Foo]  x  "), "x")
end)
