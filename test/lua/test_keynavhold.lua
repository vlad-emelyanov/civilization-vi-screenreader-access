-- KeyNavList Enter hold: a screen the AI opened takes no Enter for a while; the first Enter says the line and ends the hold
stub("engine")
include("ScreenReader")
include("KeyNavList")

test("no hold: Enter acts", function()
	local s = { holdUntil = nil, said = false }
	eq(KeyNavList_HoldCheck(s, 10, true), nil)
	eq(KeyNavList_HoldCheck(s, 10, false), nil)
end)

test("the first Enter down says and ends the hold; its KeyUp is swallowed; the next Enter acts", function()
	local s = {}
	KeyNavList_HoldStart(s, 10, 2)
	eq(KeyNavList_HoldCheck(s, 10.1, true), "say")
	eq(KeyNavList_HoldCheck(s, 10.2, true), "block")		-- key repeat
	eq(KeyNavList_HoldCheck(s, 10.3, false), "block")		-- the KeyUp of that press
	eq(KeyNavList_HoldCheck(s, 11, true), nil)
	eq(KeyNavList_HoldCheck(s, 11.1, false), nil)
end)

test("a leftover KeyUp inside the window says once and ends the hold", function()
	local s = {}
	KeyNavList_HoldStart(s, 10, 2)
	eq(KeyNavList_HoldCheck(s, 10.1, false), "say")
	eq(KeyNavList_HoldCheck(s, 10.5, true), nil)
end)

test("after 2 seconds Enter acts again", function()
	local s = {}
	KeyNavList_HoldStart(s, 10, 2)
	eq(KeyNavList_HoldCheck(s, 12, true), nil)
	eq(KeyNavList_HoldCheck(s, 15, false), nil)
end)

test("a new hold says again", function()
	local s = {}
	KeyNavList_HoldStart(s, 10, 2)
	eq(KeyNavList_HoldCheck(s, 10.5, false), "say")
	KeyNavList_HoldStart(s, 20, 2)
	eq(KeyNavList_HoldCheck(s, 20.5, false), "say")
end)
