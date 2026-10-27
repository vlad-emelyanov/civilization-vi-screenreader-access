-- ===========================================================================
--	Gamepad: the canonical key table of the Xbox controller support (docs/controller-plan.md).
--	The console app turns controller buttons into these keys (mirrored in ScreenreaderAccess.Console/Gamepad/GamepadMap.cs;
--	test/py/test_gamepadmap.py checks that both tables agree). Buttons without a keyboard equivalent are F13..F24, the second
--	bank is the same keys with Control. Included by the hub (HubGamepad) and by WorldInput (the catcher).
--	Pure functions only; the engine key codes are looked up when called.
-- ===========================================================================
Gamepad = {};

-- One entry per line in exactly this form (a Python test parses it).
Gamepad.Map = {
	A = { key = "VK_RETURN", control = false },
	B = { key = "VK_ESCAPE", control = false },
	Y = { key = "VK_SPACE", control = false },
	X = { key = "VK_F13", control = false },
	LB = { key = "VK_F14", control = false },
	RB = { key = "VK_F15", control = false },
	LT = { key = "VK_F16", control = false },
	RT = { key = "VK_F17", control = false },
	View = { key = "VK_F18", control = false },
	Menu = { key = "VK_F19", control = false },
	LSClick = { key = "VK_F20", control = false },
	RSClick = { key = "VK_F21", control = false },
	RSUp = { key = "VK_F13", control = true },
	RSDown = { key = "VK_F14", control = true },
	RSLeft = { key = "VK_F15", control = true },
	RSRight = { key = "VK_F16", control = true },
	LUp = { key = "VK_UP", control = false },
	LDown = { key = "VK_DOWN", control = false },
	LLeft = { key = "VK_LEFT", control = false },
	LRight = { key = "VK_RIGHT", control = false },
	DUp = { key = "VK_HOME", control = false },
	DDown = { key = "VK_END", control = false },
	DRight = { key = "VK_TAB", control = false },
	DLeft = { key = "VK_TAB", control = true },
	ModeOn = { key = "VK_F22", control = false },
	ModeOff = { key = "VK_F23", control = false },
};

local m_active:boolean = false;

-- The engine key code of a button (nil for an unknown name or a key this engine lacks).
function Gamepad.Key( name:string )
	local entry:table = Gamepad.Map[ name ];
	if entry == nil then return nil; end
	return Keys[ entry.key ];
end

-- The button an F-key press stands for (X, LB, ... RSRight, ModeOn, ModeOff), or nil. Plain keys (Enter, arrows) are no buttons.
function Gamepad.ButtonOf( key, isControl:boolean )
	if key == nil then return nil; end
	local control:boolean = ( isControl == true );
	for name, entry in pairs( Gamepad.Map ) do
		if string.sub( entry.key, 1, 4 ) == "VK_F" and entry.control == control and Keys[ entry.key ] == key then return name; end
	end
	return nil;
end

function Gamepad.IsActive()
	return m_active;
end

-- Controller mode on / off. LuaEvents.SRA_GamepadMode( active ) fires only on a change.
function Gamepad.SetActive( active:boolean )
	active = ( active == true );
	if active == m_active then return; end
	m_active = active;
	LuaEvents.SRA_GamepadMode( active );
end

-- The catcher decision for a key that reached WorldInput's default handlers (nothing wanted it). Returns nil (not caught) or
-- { consume = true, event = "cursor"|"details"|"info"|"swallow", dx, dy, info }. Arrows act on KeyDown (a held stick repeats),
-- Space / Home / End / Control+Tab on KeyUp; Escape is swallowed so that it does not open the game menu.
function Gamepad_CatchKey( msg:number, key:number, isControl:boolean, active:boolean )
	if not active then return nil; end
	if msg ~= KeyEvents.KeyDown and msg ~= KeyEvents.KeyUp then return nil; end
	local isDown:boolean = ( msg == KeyEvents.KeyDown );
	local swallow:table = { consume = true, event = "swallow" };
	if key == Keys.VK_ESCAPE then return swallow; end
	if isControl then
		if key == Keys.VK_TAB then
			if isDown then return swallow; end
			return { consume = true, event = "info", info = "overview" };
		end
		return nil;
	end
	local dx:number, dy:number = nil, nil;
	if key == Keys.VK_LEFT then dx, dy = -1, 0;
	elseif key == Keys.VK_RIGHT then dx, dy = 1, 0;
	elseif key == Keys.VK_UP then dx, dy = 0, 1;
	elseif key == Keys.VK_DOWN then dx, dy = 0, -1;
	end
	if dx ~= nil then
		if isDown then return { consume = true, event = "cursor", dx = dx, dy = dy }; end
		return swallow;
	end
	if key == Keys.VK_SPACE then
		if isDown then return swallow; end
		return { consume = true, event = "details" };
	end
	if key == Keys.VK_HOME or key == Keys.VK_END then
		if isDown then return swallow; end
		return { consume = true, event = "info", info = ( key == Keys.VK_HOME ) and "next" or "where" };
	end
	return nil;
end
