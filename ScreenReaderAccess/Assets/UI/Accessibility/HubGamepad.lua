-- luacheck: globals HubPad
-- ===========================================================================
--	HubGamepad: the controller buttons that are F-keys (docs/controller-plan.md, button map).
--	Part of the InGameAccess hub (see docs/ingame-plan.md, Architecture): included by UI/Additions/InGameAccess.lua, which calls
--	HubGamepad.HandleInput first thing in its input handler and HubGamepad.Init() from Initialize.
--
--	The console app sends buttons without a keyboard equivalent as F13..F24 (Gamepad.lua has the table). Here:
--	  - ModeOn / ModeOff (F22 / F23) set the controller mode flag,
--	  - global buttons (Menu, View, LB, RB, stick clicks, right stick) act on KeyUp, both events are consumed,
--	  - mode-dependent buttons (X, LT, RT) go to the open hub list first, in a target mode X scans for foreign units and LT / RT are silent, and act on the bare map,
--	  - while a game screen or popup is open every button but LB / RB passes through (LB / RB say "Close the screen first").
--	Keys that no screen wanted reach WorldInput's catcher (Gamepad_CatchKey), which fires LuaEvents.SRA_PadCursor / SRA_PadDetails /
--	SRA_PadInfo; the listeners are here.
-- ===========================================================================
HubGamepad = {};

local function Say( text:string )
	OutputMessageToScreenReader( text );
end

-- ===========================================================================
--	BUTTON ACTIONS (KeyUp)
-- ===========================================================================
local function OpenGameMenu()
	HubCore.CloseMode( false, false );
	LuaEvents.InGame_OpenInGameOptionsMenu();
end

-- LB / RB in a target mode: the places list (J), Enter there only moves the target; refuses only where CanOpenMode( true ) does
local function TargetPlaces()
	if not HubTargets.CanOpenMode( true ) then return; end
	HubPlaces.TogglePlaces();
end

local function Ring( step:number )
	if HubTargets.GetTargetMode() ~= nil then TargetPlaces(); return; end
	if not HubTargets.CanOpenMode() then return; end		-- target mode / placement: says why (with "B" in controller mode)
	local fn = nil;
	if HubPad ~= nil then
		if step > 0 then fn = HubPad.RingNext; else fn = HubPad.RingPrev; end
	end
	if fn == nil then Say( "Ring not available" ); return; end
	fn();
end

local function Capital()
	if HubTargets.GetTargetMode() ~= nil then HubTargets.CapitalKey(); return; end		-- Backslash: only moves the target
	if Players[ Game.GetLocalPlayer() ]:GetCities():GetCapitalCity() == nil then Say( "No capital" ); return; end
	LuaEvents.SRA_PadCapital();
end

local function CityStep( step:number )
	local player:table = Players[ Game.GetLocalPlayer() ];
	if player:GetCities():GetCount() == 0 then Say( "You have no cities" ); return; end
	local current:table = UI.GetHeadSelectedCity();
	if step < 0 then UI.SelectPrevCity( current ); else UI.SelectNextCity( current ); end
end

local GLOBAL_ACTIONS:table = {
	Menu		= OpenGameMenu,
	View		= function() HubHelp.Toggle(); end,
	LB			= function() Ring( -1 ); end,
	RB			= function() Ring( 1 ); end,
	LSClick		= Capital,
	RSClick		= function() LuaEvents.SRA_PadNextUnit(); end,
	RSUp		= function() HubCursor.CycleAllUnits( -1 ); end,
	RSDown		= function() HubCursor.CycleAllUnits( 1 ); end,
	RSLeft		= function() CityStep( -1 ); end,
	RSRight		= function() CityStep( 1 ); end,
};

-- LT: what the W key does. A unit: UnitPanel's Attack hotkey code; a city: the city attack mode.
local function AttackButton()
	if UI.GetHeadSelectedUnit() ~= nil then LuaEvents.SRA_PadHotkey( "Attack" );
	elseif UI.GetHeadSelectedCity() ~= nil then HubTargets.CityAttackKey();
	else Say( "No unit selected" ); end
end

-- RT: what the M key does for the selected unit.
local function MoveButton()
	if UI.GetHeadSelectedUnit() ~= nil then LuaEvents.SRA_PadHotkey( "MoveTo" );
	else Say( "No unit selected" ); end
end

local MAP_ACTIONS:table = {
	X	= function() HubCursor.SelectAtCursor(); end,
	LT	= AttackButton,
	RT	= MoveButton,
};

-- ===========================================================================
--	INPUT (called first in Hub.HandleInput; true = consumed)
-- ===========================================================================
-- A held button (RT is Shift for the console app) acts on its KeyUp only if no other key event came between its KeyDown and KeyUp
-- (modifier keys and the mode keys do not count). m_held[ button ] = true once tainted. A KeyUp with no known KeyDown acts.
local m_held:table = {};

local function TaintHeld()
	for held, _ in pairs( m_held ) do m_held[ held ] = true; end
end

-- Records the event; true = a KeyUp whose button must not act
local function TrackEvent( button:string, msg:number, key:number )
	if button == "ModeOn" or button == "ModeOff" then return false; end
	if button == nil then
		if key ~= Keys.VK_SHIFT and key ~= Keys.VK_CONTROL and key ~= Keys.VK_ALT then TaintHeld(); end
		return false;
	end
	if msg == KeyEvents.KeyDown then
		TaintHeld();
		m_held[ button ] = false;
		return false;
	end
	local tainted:boolean = ( m_held[ button ] == true );
	m_held[ button ] = nil;
	return tainted;
end

function HubGamepad.HandleInput( input:table, msg:number, key:number, isControl:boolean )
	local button:string = Gamepad.ButtonOf( key, isControl );
	local suppressed:boolean = TrackEvent( button, msg, key );
	if button == nil then return false; end
	if button == "ModeOn" then Gamepad.SetActive( true ); return true; end
	if button == "ModeOff" then Gamepad.SetActive( false ); return true; end
	if not HubCore.IsLocalPlayerActive() then return false; end
	Gamepad.SetActive( true );
	local isUp:boolean = ( msg == KeyEvents.KeyUp ) and not suppressed;

	if HubCore.IsGamePopupOpen() then
		if button == "LB" or button == "RB" then
			if isUp then Say( "Close the screen first" ); end
			return true;
		end
		if suppressed then return true; end		-- a KeyUp after another key (held RT = Shift) is consumed
		return false;		-- screens may use the other buttons
	end

	local action = GLOBAL_ACTIONS[ button ];
	if action ~= nil then
		if isUp then HubCore.Safe( "Pad" .. button, action )(); end
		return true;
	end

	if MAP_ACTIONS[ button ] ~= nil then
		if HubCore.m_mode ~= nil then
			if suppressed then return true; end
			-- the open list may have an action for the button (extraKeys[ Gamepad.Key( "X" ) ])
			local ok:boolean, consumed = xpcall( function() return HubCore.m_mode.list.HandleInput( input ); end, KeyNavErrorHandler );
			if not ok then print( "InGameAccess Pad" .. button .. " list error: " .. tostring( consumed ) ); end
			return true;
		end
		if HubTargets.GetTargetMode() ~= nil then
			if button == "X" and isUp then HubCore.Safe( "PadX", HubSettle.ScanKey )(); end		-- X key in a target mode: the nearest foreign unit
			return true;		-- LT / RT: silent
		end
		if isUp then HubCore.Safe( "Pad" .. button, MAP_ACTIONS[ button ] )(); end
		return true;
	end
	return false;
end

-- ===========================================================================
--	CATCHER EVENTS (WorldInput: keys that nothing wanted in controller mode)
-- ===========================================================================
-- Y on the bare map: an own city on the cursor tile opens its report, anything else reads the tile.
local function CatcherAllowed()
	return HubCore.IsLocalPlayerActive() and HubCore.m_mode == nil and not HubCore.IsGamePopupOpen();
end

local function OnPadDetails()
	if not CatcherAllowed() then return; end
	local x:number, y:number = HubCursor.GetCursor();
	local city:table = Cities.GetCityInPlot( x, y );
	if city ~= nil and city:GetOwner() == Game.GetLocalPlayer() and Hub.m_cityReportLoaded and HubTargets.GetTargetMode() == nil then
		HubCityReport.ToggleCityReport( true );
	else
		HubCursor.SpeakPlotDetails();
	end
end

local function OnPadInfo( info:string )
	if not CatcherAllowed() or HubTargets.GetTargetMode() ~= nil then return; end		-- D-pad: nothing in a target mode
	if info == "next" then HubAnnounce.SpeakWhatsNext();
	elseif info == "where" then HubCursor.CursorToSelection();
	elseif info == "overview" then HubOverview.Toggle();
	end
end

function HubGamepad.Init()
	-- WorldInput keeps a copy of the mode flag: answer its request (it may load after the hub or be hot reloaded) and tell it once now
	HubCore.Listen( LuaEvents.SRA_GamepadModeRequest, HubCore.Safe( "GamepadModeRequest", function() LuaEvents.SRA_GamepadMode( Gamepad.IsActive() ); end ) );
	LuaEvents.SRA_GamepadMode( Gamepad.IsActive() );
	HubCore.Listen( LuaEvents.SRA_PadCursor, HubCore.Safe( "PadCursor", function( dx:number, dy:number ) if not HubCore.IsGamePopupOpen() then HubCursor.MoveCursor( dx, dy ); end end ) );
	HubCore.Listen( LuaEvents.SRA_PadDetails, HubCore.Safe( "PadDetails", OnPadDetails ) );
	HubCore.Listen( LuaEvents.SRA_PadInfo, HubCore.Safe( "PadInfo", OnPadInfo ) );
end
