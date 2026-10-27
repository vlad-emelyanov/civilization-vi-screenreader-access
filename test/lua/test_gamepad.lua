-- Gamepad.lua: key table, ButtonOf, the controller mode flag and the catcher decision (Gamepad_CatchKey)
stub("engine")
for i = 13, 24 do Keys["VK_F" .. i] = 100 + i end
local fired = {}
LuaEvents = setmetatable({}, { __index = function(_, name)
	return function(...) table.insert(fired, { name = name, args = { ... } }) end
end })
include("Gamepad")

local DOWN, UP = KeyEvents.KeyDown, KeyEvents.KeyUp

test("Key looks the engine code up", function()
	eq(Gamepad.Key("X"), Keys.VK_F13)
	eq(Gamepad.Key("RT"), Keys.VK_F17)
	eq(Gamepad.Key("A"), Keys.VK_RETURN)
	eq(Gamepad.Key("DUp"), Keys.VK_HOME)
	eq(Gamepad.Key("Nope"), nil)
end)

test("ButtonOf: only the F-key bank are buttons", function()
	eq(Gamepad.ButtonOf(Keys.VK_F13, false), "X")
	eq(Gamepad.ButtonOf(Keys.VK_F13, true), "RSUp")
	eq(Gamepad.ButtonOf(Keys.VK_F16, true), "RSRight")
	eq(Gamepad.ButtonOf(Keys.VK_F22, false), "ModeOn")
	eq(Gamepad.ButtonOf(Keys.VK_F23, false), "ModeOff")
	eq(Gamepad.ButtonOf(Keys.VK_F20, false), "LSClick")
	eq(Gamepad.ButtonOf(Keys.VK_RETURN, false), nil)
	eq(Gamepad.ButtonOf(Keys.VK_TAB, true), nil)
	eq(Gamepad.ButtonOf(Keys.VK_F24, false), nil)
	eq(Gamepad.ButtonOf(nil, false), nil)
end)

test("every F-key button round-trips through Key and ButtonOf", function()
	for name, entry in pairs(Gamepad.Map) do
		if entry.key:sub(1, 4) == "VK_F" then eq(Gamepad.ButtonOf(Gamepad.Key(name), entry.control), name) end
	end
end)

test("SetActive fires SRA_GamepadMode once per change", function()
	fired = {}
	eq(Gamepad.IsActive(), false)
	Gamepad.SetActive(true)
	Gamepad.SetActive(true)
	eq(#fired, 1)
	eq(fired[1].name, "SRA_GamepadMode")
	eq(fired[1].args[1], true)
	eq(Gamepad.IsActive(), true)
	Gamepad.SetActive(false)
	eq(#fired, 2)
	eq(fired[2].args[1], false)
	Gamepad.SetActive(false)
	eq(#fired, 2)
end)

test("catcher: inactive catches nothing", function()
	for _, key in ipairs({ Keys.VK_UP, Keys.VK_ESCAPE, Keys.VK_SPACE, Keys.VK_HOME, Keys.VK_END, Keys.VK_TAB }) do
		eq(Gamepad_CatchKey(DOWN, key, false, false), nil)
		eq(Gamepad_CatchKey(UP, key, true, false), nil)
	end
end)

test("catcher: arrows move the cursor on KeyDown and are swallowed on KeyUp", function()
	local function dir(key, dx, dy)
		local c = Gamepad_CatchKey(DOWN, key, false, true)
		eq(c.event, "cursor"); eq(c.dx, dx); eq(c.dy, dy); eq(c.consume, true)
		local u = Gamepad_CatchKey(UP, key, false, true)
		eq(u.event, "swallow"); eq(u.consume, true)
	end
	dir(Keys.VK_LEFT, -1, 0)
	dir(Keys.VK_RIGHT, 1, 0)
	dir(Keys.VK_UP, 0, 1)
	dir(Keys.VK_DOWN, 0, -1)
	eq(Gamepad_CatchKey(DOWN, Keys.VK_UP, true, true), nil)		-- Control+arrow is the keyboard's
end)

test("catcher: Escape is swallowed both ways", function()
	eq(Gamepad_CatchKey(DOWN, Keys.VK_ESCAPE, false, true).event, "swallow")
	local u = Gamepad_CatchKey(UP, Keys.VK_ESCAPE, false, true)
	eq(u.event, "swallow"); eq(u.consume, true)
end)

test("catcher: Space reads details on KeyUp", function()
	eq(Gamepad_CatchKey(DOWN, Keys.VK_SPACE, false, true).event, "swallow")
	local u = Gamepad_CatchKey(UP, Keys.VK_SPACE, false, true)
	eq(u.event, "details"); eq(u.consume, true)
end)

test("catcher: Home, End and Control+Tab are info on KeyUp", function()
	eq(Gamepad_CatchKey(DOWN, Keys.VK_HOME, false, true).event, "swallow")
	local home = Gamepad_CatchKey(UP, Keys.VK_HOME, false, true)
	eq(home.event, "info"); eq(home.info, "next")
	local fin = Gamepad_CatchKey(UP, Keys.VK_END, false, true)
	eq(fin.event, "info"); eq(fin.info, "where")
	eq(Gamepad_CatchKey(DOWN, Keys.VK_TAB, true, true).event, "swallow")
	local tab = Gamepad_CatchKey(UP, Keys.VK_TAB, true, true)
	eq(tab.event, "info"); eq(tab.info, "overview"); eq(tab.consume, true)
	eq(Gamepad_CatchKey(UP, Keys.VK_TAB, false, true), nil)		-- plain Tab stays the unit actions key
end)

test("catcher: other keys and other messages are not caught", function()
	eq(Gamepad_CatchKey(DOWN, Keys.VK_RETURN, false, true), nil)
	eq(Gamepad_CatchKey(DOWN, Keys.VK_DELETE, false, true), nil)
	eq(Gamepad_CatchKey(99, Keys.VK_UP, false, true), nil)
end)
