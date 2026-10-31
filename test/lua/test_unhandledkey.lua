-- KeyNavList_UnhandledKeyText: a modal list answers Tab and the F-keys instead of staying silent
stub("engine")
include("KeyNavList")
Keys.VK_F7 = 118
Keys.VK_F1 = 112

test("Tab and F-keys answer, other keys stay quiet", function()
	eq(KeyNavList_UnhandledKeyText(Keys.VK_TAB, false, false, false), "No tabs here", "tab")
	eq(KeyNavList_UnhandledKeyText(Keys.VK_F7, false, false, false), "Close the list first, [KEY:Escape] closes it", "F7")
	eq(KeyNavList_UnhandledKeyText(Keys.VK_F1, false, false, false), "Close the list first, [KEY:Escape] closes it", "F1")
	eq(KeyNavList_UnhandledKeyText(Keys.VK_F7, true, false, false), nil, "ctrl combination")
	eq(KeyNavList_UnhandledKeyText(65, false, false, false), nil, "letter")
end)

test("SayUnhandledKey speaks on KeyUp only", function()
	ClearPrinted()
	eq(KeyNavList_SayUnhandledKey(Input{ key = Keys.VK_TAB }), false, "down")
	eq(#Spoken(), 0, "nothing on down")
	eq(KeyNavList_SayUnhandledKey(Input{ key = Keys.VK_TAB, up = true }), true, "up")
	eq(Spoken()[1], "No tabs here", "spoken")
end)
