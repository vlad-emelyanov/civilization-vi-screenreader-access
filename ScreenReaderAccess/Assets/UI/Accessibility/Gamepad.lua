-- ===========================================================================
--	Gamepad: the canonical key table of the Xbox controller support (docs/controller-plan.md).
--	The console app turns controller buttons into these keys (mirrored in ScreenreaderAccess.Console/Gamepad/GamepadMap.cs;
--	test/py/test_gamepadmap.py checks that both tables agree). Buttons without a keyboard equivalent are F13..F24, the second
--	bank is the same keys with Control. Included by the hub (HubGamepad) and by WorldInput (the catcher).
--	Pure functions only; the engine key codes are looked up when called.
-- ===========================================================================
-- (include() may run this file again in a context that already has it: keep the first copy, with its mode flag)
if Gamepad ~= nil and Gamepad.Map ~= nil then return; end
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
	PageUp = { key = "VK_PRIOR", control = false },
	PageDown = { key = "VK_NEXT", control = false },
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
-- With Shift the F-keys are the wheel's slots (Gamepad.WheelOf), never buttons.
function Gamepad.ButtonOf( key, isControl:boolean, isShift:boolean )
	if key == nil or isShift == true then return nil; end
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

-- The wheel (experiment, docs/controller-plan.md "The wheel"): while LT is held the console app turns the left stick's direction into
-- one of WHEEL_SLOTS slots, clockwise from straight up (slot 0 = up, 6 = right, 12 = down, 18 = left), sent as Shift+F13..F24
-- (slots 0..11) and Control+Shift+F13..F24 (slots 12..23), one tap per slot change. A list maps the slot to one of its items.
Gamepad.WHEEL_SLOTS = 24;

-- The slot (0..23) of a wheel key, or nil. Pure apart from the engine key codes.
function Gamepad.WheelOf( key, isControl:boolean, isShift:boolean )
	if key == nil or isShift ~= true then return nil; end
	for n = 13, 24 do
		if Keys[ "VK_F" .. n ] == key then return ( n - 13 ) + ( isControl == true and 12 or 0 ); end
	end
	return nil;
end

-- Pure. The item (1..count) a wheel slot points at: the items sit evenly around the wheel, clockwise, item 1 straight up
-- (4 items: up, right, down, left). More items than slots: the slot lands on the nearest item, every count / slots-th one is reachable
-- (a coarse jump; the stick then moves one by one).
function Gamepad.WheelIndex( slot:number, count:number )
	if count == nil or count < 1 or slot == nil then return nil; end
	return math.floor( slot * count / Gamepad.WHEEL_SLOTS + 0.5 ) % count + 1;
end

-- The engine key of PageUp (down = false) / PageDown (true): the console app sends them while LB or RB is held (group jump).
-- The engine's names for them are not verified (the game's own Lua never uses a page key; the engine's Keys names are Win32-like,
-- VK_PRIOR / VK_NEXT are the expected ones): the first one this engine has wins. Check with: for k in pairs( Keys ) do print( k ) end.
function Gamepad.PageKey( down:boolean )
	local names:table = down and { "VK_NEXT", "VK_PAGEDOWN", "VK_PGDN", "VK_PAGE_DOWN" } or { "VK_PRIOR", "VK_PAGEUP", "VK_PGUP", "VK_PAGE_UP" };
	for _, name in ipairs( names ) do
		if Keys[ name ] ~= nil then return Keys[ name ]; end
	end
	return nil;
end

-- Pad state in contexts without the hub (game screens, popups, the front end): the hub broadcasts LuaEvents.SRA_GamepadMode when
-- the mode changes and answers SRA_GamepadModeRequest with the current mode; Follow() listens (the listener only stores, it never
-- fires the event again) and asks once. Idempotent per context. Where no hub exists (front end), NoteModeKey sees F22 / F23 itself.
local m_followed:boolean = false;

function Gamepad.Follow()
	if m_followed then return; end
	m_followed = true;
	if SRListen == nil or LuaEvents == nil then return; end
	SRListen( LuaEvents.SRA_GamepadMode, function( active ) m_active = ( active == true ); end );
	Gamepad.RequestMode();
end

-- Asks the hub for the current mode (it answers with LuaEvents.SRA_GamepadMode, which listeners only store). Lists ask on Open
-- so a mode change that a context missed (a popup above the hub took the F-key) is repaired.
function Gamepad.RequestMode()
	if LuaEvents ~= nil and LuaEvents.SRA_GamepadModeRequest ~= nil then LuaEvents.SRA_GamepadModeRequest(); end
end

-- F22 / F23 passing a handler (a popup above the hub, the front end): remember the mode and tell the others on a change, so the
-- hub and the other contexts do not keep a stale flag. No loop: the listeners (Follow, WorldInput) only store, the hub's answer to
-- a request is an event of the same kind that changes nothing here (no change, no event).
function Gamepad.NoteModeKey( key, isControl:boolean, isShift:boolean )
	local button:string = Gamepad.ButtonOf( key, isControl, isShift );
	local want = nil;
	if button == "ModeOn" then want = true;
	elseif button == "ModeOff" then want = false;
	end
	if want == nil or want == m_active then return; end
	m_active = want;
	if LuaEvents ~= nil and LuaEvents.SRA_GamepadMode ~= nil then LuaEvents.SRA_GamepadMode( want ); end
end

-- Pure. A list or screen with sections sees the pad's keys as the keys it already knows (docs/controller-plan.md):
-- D-pad up / down (Home / End) = Up / Down, D-pad right / left (Tab / Control+Tab) = Right / Left (the left stick's keys),
-- LB / RB (F14 / F15) = Control+Tab / Tab (previous / next section). Returns key, isControl, fromBumper. Inactive (keyboard):
-- unchanged, so Home / End / Tab keep their keyboard meaning. Not for the bare map (WorldInput's catcher).
function Gamepad.TranslateListKey( key, isControl:boolean, active:boolean )
	isControl = ( isControl == true );
	if not active or key == nil then return key, isControl, false; end
	if isControl then
		if key == Keys.VK_TAB then return Keys.VK_LEFT, false, false; end
		return key, isControl, false;
	end
	if key == Keys.VK_HOME then return Keys.VK_UP, false, false; end
	if key == Keys.VK_END then return Keys.VK_DOWN, false, false; end
	if key == Keys.VK_TAB then return Keys.VK_RIGHT, false, false; end
	local button:string = Gamepad.ButtonOf( key, false );
	if button == "LB" then return Keys.VK_TAB, true, true; end
	if button == "RB" then return Keys.VK_TAB, false, true; end
	return key, isControl, false;
end

-- An input struct as the pad-aware screen sees it: GetKey / IsControlDown translated by TranslateListKey (only in controller mode,
-- only without Shift / Alt); every other method passes through. Screens with their own Tab / Home / End handling call this first.
function Gamepad.WrapInput( input:table )
	Gamepad.Follow();
	if input == nil then return input; end
	local msg:number = input:GetMessageType();
	if msg ~= KeyEvents.KeyDown and msg ~= KeyEvents.KeyUp then return input; end
	local rawKey = input:GetKey();
	local rawControl:boolean = input:IsControlDown();
	Gamepad.NoteModeKey( rawKey, rawControl, input:IsShiftDown() );
	if not m_active or input:IsShiftDown() or input:IsAltDown() then return input; end
	local key, ctrl = Gamepad.TranslateListKey( rawKey, rawControl, true );
	if key == rawKey and ctrl == rawControl then return input; end
	return setmetatable( { GetKey = function() return key; end, IsControlDown = function() return ctrl; end },
		{ __index = function( _, name ) return function( _, ... ) return input[ name ]( input, ... ); end; end } );
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
	-- PageUp / PageDown (the held-bumper group jump) never reach the game: Gathering Storm binds PageDown to the Climate screen
	if key ~= nil and ( key == Gamepad.PageKey( false ) or key == Gamepad.PageKey( true ) ) then return swallow; end
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
