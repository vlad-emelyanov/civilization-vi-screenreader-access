-- ===========================================================================
--	InGameAccess: screen reader hub for the in-game UI (see docs/ingame-plan.md).
--	A context without visuals, added to InGame (UI/Additions/InGameAccess.xml). It owns
--	  - the map cursor (Shift+Arrows) and its plot announcements,
--	  - the in-game hotkeys (I plot details, . cursor to selection, J places list, N what is next, Tab unit actions),
--	  - the unit actions menu and the target modes (move to, attack ...), which take over Up/Down/Enter/Escape and
--	    Shift+Arrows through this context's input handler (see the bottom of the file),
--	  - the regions: top panel (Control+Y), notifications (Control+N) and the city report (Control+I), with arrivals announced,
--	  - event announcements: unit/city selected, new turn, end of turn, unit results, enemies spotted.
--	Input order (verified, see docs/ingame-plan.md): this context's input handler runs before WorldInput and
--	ActionPanel; a key it consumes (KeyDown and KeyUp) also never becomes an input action.
-- ===========================================================================

Hub = {};		-- shared state and functions of the hub (the modules below add their own tables)

include( "ScreenReader" );
include( "KeyboardNavigation" );
include( "PlotDescription" );
include( "KeyNavList" );
include( "Civ6Common" );		-- MoveUnitToPlot (war declaration check + the right move/attack operation)
include( "SettleScan" );		-- settler: can settle here, best spots
include( "PlacementScan" );		-- city: where a district or wonder can go
include( "TopPanelData" );		-- top panel values as sentences (Control+Y, Control+G)
-- City report (Control+I): CityReportGather includes the game's CitySupport (GetCityData), which is heavy and may fail in
-- a ruleset: a failure here only loses the report, never the rest of the hub.
Hub.m_cityReportLoaded = pcall( function()
	include( "CityReportData" );
	include( "CityReportGather" );
end );
if not Hub.m_cityReportLoaded then print( "InGameAccess: the city report files did not load" ); end

-- ===========================================================================
--	MEMBERS
-- ===========================================================================

local m_actions				:table = {};		-- actionId -> handler
local m_enterLabel			:string = "";		-- what the action panel said Enter would do

-- ===========================================================================
--	ENTER (Next Action) must always say something
-- ===========================================================================
function Hub.IsGovernorLabel()
	local label:table = ContextPtr:LookUpControl( "/InGame/HUD/ActionPanel/EndTurnText" );
	local text:string = ( label ~= nil ) and label:GetText() or "";
	for _, key in ipairs( { "LOC_ACTION_PANEL_GOVERNOR_APPOINTMENT", "LOC_ACTION_PANEL_GOVERNOR_OPPORTUNITY", "LOC_ACTION_PANEL_GOVERNOR_PROMOTION", "LOC_ACTION_PANEL_GOVERNOR_IDLE" } ) do
		if text == Locale.Lookup( key ) then print( "InGameAccess: Enter held back, end-turn label '" .. text .. "' right after an attack" ); return true; end
	end
	return false;
end

function Hub.IsUnitOrdersLabel( text:string )
	return text == Locale.Lookup( "LOC_ACTION_PANEL_NEEDS_ORDERS" ) or text == Locale.Lookup( "LOC_ACTION_PANEL_STACKED_UNIT" )
		or text == Locale.Lookup( "LOC_ACTION_PANEL_UNIT_MOVES_REMAINING" );
end

function Hub.ArmEnterWatch()
	local label:table = ContextPtr:LookUpControl( "/InGame/HUD/ActionPanel/EndTurnText" );
	m_enterLabel = ( label ~= nil ) and label:GetText() or "";
	HubCore.m_enterWatch = 0.8;
end

-- Enter was pressed, nothing announced a new selection, turn end or mode: the game re-selected the same unit
-- (or none could be selected). Say what is going on.
function Hub.EnterFallback()
	if not Hub.IsUnitOrdersLabel( m_enterLabel ) then return; end
	local unit:table = UI.GetHeadSelectedUnit();
	if unit ~= nil then
		local text:string = HubAnnounce.UnitText( unit ) .. ", needs orders. Tab for its actions";
		-- a unit the game lets neither skip nor sleep (UnitPanel adds a disabled Skip Turn entry with the reason)
		local okHint:boolean, hint = pcall( function()
			for _, item in ipairs( HubMenus.FetchMenuItems( false ) ) do
				if item.action.typeName == "UNITOPERATION_SKIP_TURN" and item.action.disabled then return item.action.reason; end
			end
			return nil;
		end );
		if okHint and hint ~= nil and hint ~= "" then text = text .. ". Cannot skip: " .. hint; end
		local promotion:string = HubAnnounce.PromotionHint( unit );
		if promotion ~= nil then text = text .. ". " .. promotion; end
		HubCore.SayResult( text );
	else
		HubCore.SayResult( HubCore.Capitalize( CleanTextForSpeech( m_enterLabel ) ) );
	end
end

-- ===========================================================================
--	INPUT HANDLER: runs before WorldInput and ActionPanel (see docs/ingame-plan.md, Input order)
-- ===========================================================================
function Hub.HandleInput( input:table )
	if not HubCore.IsLocalPlayerActive() then return false; end
	local msg:number = input:GetMessageType();
	if msg ~= KeyEvents.KeyDown and msg ~= KeyEvents.KeyUp then return false; end
	HubCore.m_lastKeyTime = UI.GetElapsedTime();
	if HubCore.m_mode ~= nil then return HubCore.m_mode.list.HandleInput( input ); end
	if input:IsShiftDown() or input:IsControlDown() or input:IsAltDown() then return false; end
	local key:number = input:GetKey();
	if HubTargets.GetTargetMode() ~= nil then
		-- Enter and Escape belong to the mode; both KeyDown and KeyUp are consumed, so ActionPanel never sees Enter
		if UI.GetHeadSelectedUnit() == nil and UI.GetHeadSelectedCity() == nil then
			HubTargets.ResetStaleMode();		-- nothing left to act: the keys go to the game again
			return false;
		end
		if key == Keys.VK_RETURN or key == Keys.VK_ESCAPE then
			-- consumed even when the handler fails, so that Enter never falls through to Next Action mid-mode
			if msg == KeyEvents.KeyUp then
				local ok:boolean, err = xpcall( function() if key == Keys.VK_RETURN then HubTargets.ConfirmTarget(); else HubTargets.CancelTarget(); end end, KeyNavErrorHandler );
				if not ok then
					print( "InGameAccess target mode error: " .. tostring( err ) );
					OutputMessageToScreenReader( "Something went wrong, Escape to cancel" );
				end
			end
			return true;
		end
		return false;
	end
	-- Just after an attack the end-turn label can flash a governor blocker; Enter would open the Governors screen
	if key == Keys.VK_RETURN and UI.GetElapsedTime() - HubTargets.attackTime < 5 and Hub.IsGovernorLabel() then
		if msg == KeyEvents.KeyUp then HubCore.SayResult( "The attack is still resolving, press Enter again in a moment" ); end
		return true;
	end
	if key == Keys.VK_RETURN and msg == KeyEvents.KeyUp and not HubCore.IsGamePopupOpen() then Hub.ArmEnterWatch(); end		-- an open screen (City-States, governors) takes Enter itself
	return false;
end

function Hub.OnInput( input:table )
	local ok:boolean, consumed = xpcall( function() return Hub.HandleInput( input ); end, KeyNavErrorHandler );
	if not ok then
		print( "InGameAccess input error: " .. tostring( consumed ) );
		return false;
	end
	return consumed == true;
end

function Hub.OnUpdate( deltaTime:number )
	HubCursor.UpdateMouse( deltaTime );
	if HubCore.m_arrivalTimer >= 0 then
		HubCore.m_arrivalTimer = HubCore.m_arrivalTimer - deltaTime;
		if HubCore.m_arrivalTimer < 0 then
			HubCore.m_arrivalTimer = -1;
			local ok:boolean, err = xpcall( HubRegions.FlushArrivals, KeyNavErrorHandler );
			if not ok then print( "InGameAccess FlushArrivals error: " .. tostring(err) ); end
		end
	end
	local i:number = 1;
	while i <= #HubCore.m_delayed do
		local entry:table = HubCore.m_delayed[i];
		entry.time = entry.time - deltaTime;
		if entry.time <= 0 then
			table.remove( HubCore.m_delayed, i );
			local ok:boolean, err = xpcall( entry.fn, KeyNavErrorHandler );
			if not ok then print( "InGameAccess delayed call error: " .. tostring( err ) ); end
		else
			i = i + 1;
		end
	end
	if HubCore.m_enterWatch >= 0 then
		HubCore.m_enterWatch = HubCore.m_enterWatch - deltaTime;
		if HubCore.m_enterWatch < 0 then
			HubCore.m_enterWatch = -1;
			Hub.EnterFallback();
		end
	end
end

-- ===========================================================================
--	INPUT ACTIONS
-- ===========================================================================
function Hub.OnInputActionTriggered( actionId:number )
	local handler = m_actions[ actionId ];
	if handler ~= nil then handler(); end
end

function Hub.RegisterAction( name:string, handler )
	local id:number = Input.GetActionId( name );
	if id == nil then
		print( "InGameAccess: unknown input action " .. name );
		return;
	end
	m_actions[ id ] = HubCore.Safe( name, handler );
end

-- Hub modules (Accessibility/Hub*.lua), see docs/ingame-plan.md
include( "HubCore" );
include( "HubCursor" );
include( "HubTargets" );
include( "HubAnnounce" );
include( "HubSettle" );
include( "HubPlacement" );
include( "HubMenus" );
include( "HubRegions" );
include( "HubPlaces" );
include( "HubCityReport" );
include( "HubEvents" );

-- ===========================================================================
function Initialize()
	-- Contexts added with AddUserInterfaces start hidden, and a hidden context gets no input actions or updates.
	ContextPtr:SetHide( false );

	-- A hot reload (civctl deploy) happens in the middle of a game: LoadScreenClose will not come again, so the hub would
	-- stay "not ready" (no event announcements) with a fresh state. Start it as it would be after the load, without
	-- repeating the turn announcement.
	if ContextPtr:IsHotLoad() and HubCore.IsLocalPlayerActive() then
		HubCore.m_ready = true;
		HubCore.m_cursorPlayer = Game.GetLocalPlayer();
		HubCore.m_lastAnnouncedTurn = Game.GetLocalPlayer() .. ":" .. Game.GetCurrentGameTurn();
		for _, unit in Players[ Game.GetLocalPlayer() ]:GetUnits():Members() do HubCore.RememberUnit( unit ); end
	end

	Hub.RegisterAction( "KeyNavMoveCellLeft",		function() HubCursor.MoveCursor( -1, 0 ); end );
	Hub.RegisterAction( "KeyNavMoveCellRight",		function() HubCursor.MoveCursor( 1, 0 ); end );
	Hub.RegisterAction( "KeyNavMoveCellUp",			function() HubCursor.MoveCursor( 0, 1 ); end );
	Hub.RegisterAction( "KeyNavMoveCellDown",		function() HubCursor.MoveCursor( 0, -1 ); end );
	Hub.RegisterAction( "KeyNavPlotDetails",		HubCursor.SpeakPlotDetails );
	Hub.RegisterAction( "KeyNavCursorToSelection",	HubCursor.CursorToSelection );
	Hub.RegisterAction( "KeyNavWhatsNext",			HubAnnounce.SpeakWhatsNext );
	Hub.RegisterAction( "KeyNavUnitActions",		HubMenus.ToggleUnitMenu );
	Hub.RegisterAction( "KeyNavSelectAtCursor",		HubCursor.SelectAtCursor );
	Hub.RegisterAction( "KeyNavCycleAllUnits",		HubCursor.CycleAllUnits );
	Hub.RegisterAction( "KeyNavScanUnits",			HubSettle.ScanKey );
	Hub.RegisterAction( "KeyNavDiplomacy",			HubMenus.ToggleCivMenu );
	Hub.RegisterAction( "KeyNavTopPanel",			HubRegions.ToggleTopPanel );
	Hub.RegisterAction( "KeyNavNotifications",		HubRegions.ToggleNotifications );
	Hub.RegisterAction( "KeyNavYields",				HubRegions.SpeakYields );
	Hub.RegisterAction( "KeyNavCityReport",			HubCityReport.ToggleCityReport );
	Hub.RegisterAction( "KeyNavReports",			HubTargets.ToggleReports );
	Hub.RegisterAction( "KeyNavPlaces",				HubPlaces.TogglePlaces );
	Hub.RegisterAction( "KeyNavGreatWorks",		HubRegions.ToggleGreatWorks );
	Hub.RegisterAction( "RangedAttack",			HubTargets.CityAttackKey );		-- R and W with a city selected: UnitPanel is hidden and silent
	Hub.RegisterAction( "Attack",					HubTargets.CityAttackKey );
	HubCore.Listen( Events.InputActionTriggered, Hub.OnInputActionTriggered );

	HubCore.Listen( Events.UnitSelectionChanged, HubCore.Safe( "UnitSelectionChanged", HubAnnounce.OnUnitSelectionChanged ) );
	HubCore.Listen( Events.CitySelectionChanged, HubCore.Safe( "CitySelectionChanged", HubAnnounce.OnCitySelectionChanged ) );
	HubCore.Listen( Events.LocalPlayerTurnBegin, HubCore.Safe( "LocalPlayerTurnBegin", HubAnnounce.AnnounceTurn ) );
	HubCore.Listen( Events.LoadScreenClose, HubCore.Safe( "LoadScreenClose", HubAnnounce.OnLoadScreenClose ) );
	HubCore.Listen( Events.LocalPlayerTurnEnd, HubCore.Safe( "LocalPlayerTurnEnd", HubAnnounce.OnLocalPlayerTurnEnd ) );

	HubCore.AddEvent( "InterfaceModeChanged",		HubTargets.OnInterfaceModeChanged );
	HubCore.AddEvent( "UnitOperationStarted",		HubEvents.OnUnitOperationStarted );
	HubCore.AddEvent( "UnitOperationAdded",			HubEvents.OnUnitOperationAdded );
	HubCore.AddEvent( "UnitCommandStarted",			HubEvents.OnUnitCommandStarted );
	HubCore.AddEvent( "UnitMoveComplete",			HubEvents.OnUnitMoveComplete );
	HubCore.AddEvent( "CombatVisBegin",				HubEvents.OnCombatVisBegin );
	HubCore.AddEvent( "UnitDamageChanged",			HubEvents.OnUnitDamageChanged );
	HubCore.AddEvent( "CityAddedToMap",				HubEvents.OnCityAddedToMap );
	HubCore.AddEvent( "ImprovementAddedToMap",		HubEvents.OnImprovementAddedToMap );
	HubCore.AddEvent( "UnitVisibilityChanged",		HubEvents.OnUnitVisibilityChanged );
	-- "Promoted: X" is spoken by the UnitPromotionPopup override (the only keyboard way to promote)
	HubCore.AddEvent( "UnitUpgraded",				function( player:number, unitID:number, unitType:number )
		local row:table = GameInfo.Units[ unitType ];
		if player == Game.GetLocalPlayer() and HubCore.m_ready and row ~= nil then HubCore.SayResult( "Upgraded to " .. Locale.Lookup( row.Name ) ); end
	end );
	HubCore.AddEvent( "UnitKilledInCombat",			HubEvents.OnUnitKilledInCombat );
	HubCore.Listen( LuaEvents.SRA_UnitActions, HubMenus.OnUnitActionsReceived );
	HubCore.Listen( LuaEvents.SRA_Notifications, HubRegions.OnNotificationsReceived );
	HubCore.Listen( LuaEvents.SRA_NotificationAdded, HubCore.Safe( "NotificationAdded", HubRegions.OnNotificationAdded ) );
	HubCore.Listen( LuaEvents.SRA_NotificationActivated, HubCore.Safe( "NotificationActivated", HubRegions.OnNotificationActivated ) );
	HubCore.Listen( LuaEvents.SRA_AttackKey, HubCore.Safe( "AttackKey", HubTargets.AttackKey ) );
	HubCore.Listen( LuaEvents.SRA_TradeResult, HubCore.Safe( "TradeResult", HubEvents.OnTradeResult ) );		-- trade choosers: outcome of the route / move
	HubCore.Listen( LuaEvents.SRA_CursorTo, HubCore.Safe( "CursorTo", function( x:number, y:number ) HubPlaces.OnCursorTo( x, y ); end ) );		-- City-States / espionage screens: Show on map
	HubCore.AddEvent( "UnitRemovedFromMap",			function() HubCore.After( 0.3, HubTargets.ResetStaleMode ); end );
	HubCore.AddEvent( "UnitAddedToMap",				function( playerID:number, unitID:number )
		local player:table = Players[ playerID ];
		if player ~= nil then HubCore.RememberUnit( player:GetUnits():FindID( unitID ) ); end
	end );

	ContextPtr:SetInputHandler( Hub.OnInput, true );
	ContextPtr:SetUpdate( HubCore.Safe( "Update", Hub.OnUpdate ) );
	ContextPtr:SetShutdown( HubCore.OnShutdown );
end
Initialize();
