-- HubCore.CutOffEntries: which recently spoken lines a popup's speech probably cut off
stub("engine")
include("ScreenReader")
include("KeyboardNavigation")
include("KeyNavList")
include("HubCore")

local function line(n) return string.rep("x", n) end

test("a line that had time to finish is not replayed", function()
	local r = { { text = line(28), kind = "x", time = 10 } }		-- 2 s of speech
	eq(#HubCore.CutOffEntries(r, 11), 1)
	eq(#HubCore.CutOffEntries(r, 12.5), 0)
end)

test("lines queue behind each other", function()
	local r = { { text = line(28), kind = "a", time = 10 }, { text = line(28), kind = "b", time = 10.1 } }
	local c = HubCore.CutOffEntries(r, 13)		-- first ends 12, second 14
	eq(#c, 1)
	eq(c[1].kind, "b")
end)

test("cursor keys text follows the bindings", function()
	eq(SRCursorKeysText({ "Shift+Left", "Shift+Right", "Shift+Up", "Shift+Down" }), "Shift+Arrows")
	eq(SRCursorKeysText({ "Left", "Right", "Up", "Down" }), "Arrows")
	eq(SRCursorKeysText({ "Alt+Left", "Shift+Right", "Shift+Up", "Shift+Down" }), "the cursor keys")
	eq(SRCursorKeysText({ "Shift+A", "Shift+D", "Shift+W", "Shift+S" }), "the cursor keys")
	eq(SRCursorKeysText({ "Shift+Left" }), "the cursor keys")
end)

test("the turn line is not replayed after a second", function()
	local r = { { text = line(200), kind = "turn", time = 10 } }
	eq(#HubCore.CutOffEntries(r, 10.5), 1)
	eq(#HubCore.CutOffEntries(r, 11.2), 0)
end)
