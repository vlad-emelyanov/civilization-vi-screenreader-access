-- luacheck: globals HubPad
-- ===========================================================================
--	HubGamepad: the controller buttons that are F-keys (docs/controller-plan.md, button map).
--	Part of the InGameAccess hub (see docs/ingame-plan.md, Architecture): included by UI/Additions/InGameAccess.lua, which calls
--	HubGamepad.HandleInput first thing in its input handler and HubGamepad.Init() from Initialize.
--
--	The console app sends buttons without a keyboard equivalent as F13..F24 (Gamepad.lua has the table). Here:
--	  - ModeOn / ModeOff (F22 / F23) set the controller mode flag,
--	  - global buttons (Menu, View, LB, RB, stick clicks, right stick) act on KeyUp, both events are consumed,
--	  - mode-dependent buttons (X, LT, RT) go to the open hub list first, are silent in a target mode, and act on the bare map,
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

local function Ring( step:number )
	if not HubTargets.CanOpenMode() then return; end		-- target mode / placement: says why (with "B" in controller mode)
	if step > 0 then
		if HubPad ~= nil and HubPad.RingNext ~= nil then HubPad.RingNext(); else Say( "Ring not available" ); end
	else
		if HubPad ~= nil and HubPad.RingPrev ~= nil then HubPad.RingPrev(); else Say( "Ring not available" ); end
	end
end

local function Capital()
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
function HubGamepad.HandleInput( input:table, msg:number, key:number, isControl:boolean )
	local button:string = Gamepad.ButtonOf( key, isControl );
	if button == nil then return false; end
	if button == "ModeOn" then Gamepad.SetActive( true ); return true; end
	if button == "ModeOff" then Gamepad.SetActive( false ); return true; end
	Gamepad.SetActive( true );
	local isUp:boolean = ( msg == KeyEvents.KeyUp );

	if HubCore.IsGamePopupOpen() then
		if button == "LB" or button == "RB" then
			if isUp then Say( "Close the screen first" ); end
			return true;
		end
		return false;		-- screens may use the other buttons
	end

	local action = GLOBAL_ACTIONS[ button ];
	if action ~= nil then
		if isUp then HubCore.Safe( "Pad" .. button, action )(); end
		return true;
	end

	if MAP_ACTIONS[ button ] ~= nil then
		if HubCore.m_mode ~= nil then
			-- the open list may have an action for the button (extraKeys[ Gamepad.Key( "X" ) ])
			local ok:boolean, consumed = xpcall( function() return HubCore.m_mode.list.HandleInput( input ); end, KeyNavErrorHandler );
			if not ok then print( "InGameAccess Pad" .. button .. " list error: " .. tostring( consumed ) ); end
			return true;
		end
		if HubTargets.GetTargetMode() ~= nil then return true; end
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
	HubCore.Listen( LuaEvents.SRA_PadCursor, HubCore.Safe( "PadCursor", function( dx:number, dy:number ) if not HubCore.IsGamePopupOpen() then HubCursor.MoveCursor( dx, dy ); end end ) );
	HubCore.Listen( LuaEvents.SRA_PadDetails, HubCore.Safe( "PadDetails", OnPadDetails ) );
	HubCore.Listen( LuaEvents.SRA_PadInfo, HubCore.Safe( "PadInfo", OnPadInfo ) );
end
