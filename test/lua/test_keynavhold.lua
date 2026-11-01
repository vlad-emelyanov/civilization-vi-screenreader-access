-- KeyNavList Enter hold: a screen the AI opened takes no Enter for a while (down, up or a leftover up), says it once
stub("engine")
include("ScreenReader")
include("KeyNavList")

test("no hold: Enter acts", function()
	local s = { holdUntil = nil, said = false }
	eq(KeyNavList_HoldCheck(s, 10), nil)
end)

test("inside the window the first Enter says, the rest are silent", function()
	local s = {}
	KeyNavList_HoldStart(s, 10, 2)
	eq(KeyNavList_HoldCheck(s, 10.1), "say")
	eq(KeyNavList_HoldCheck(s, 10.2), "block")
	eq(KeyNavList_HoldCheck(s, 11.9), "block")
end)

test("after 2 seconds Enter acts again", function()
	local s = {}
	KeyNavList_HoldStart(s, 10, 2)
	eq(KeyNavList_HoldCheck(s, 12), nil)
	eq(KeyNavList_HoldCheck(s, 15), nil)
end)

test("a new hold says again", function()
	local s = {}
	KeyNavList_HoldStart(s, 10, 2)
	eq(KeyNavList_HoldCheck(s, 10.5), "say")
	KeyNavList_HoldStart(s, 20, 2)
	eq(KeyNavList_HoldCheck(s, 20.5), "say")
end)
