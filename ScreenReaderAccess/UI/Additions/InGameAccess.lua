-- ===========================================================================
--	InGameAccess: screen reader hub for the in-game UI (see docs/ingame-plan.md).
--	A context without visuals, added to InGame (UI/Additions/InGameAccess.xml). It owns
--	  - the map cursor (Shift+Arrows) and its plot announcements,
--	  - the in-game hotkeys (I plot details, J cursor to selection, N what is next, Tab unit actions),
--	  - the unit actions menu and the target modes (move to, attack ...), which take over Up/Down/Enter/Escape and
--	    Shift+Arrows through this context's input handler (see the bottom of the file),
--	  - the regions: top panel (Control+Y), notifications (Control+N) and the city report (Control+I), with arrivals announced,
--	  - event announcements: unit/city selected, new turn, end of turn, unit results, enemies spotted.
--	Input order (verified, see docs/ingame-plan.md): this context's input handler runs before WorldInput and
--	ActionPanel; a key it consumes (KeyDown and KeyUp) also never becomes an input action.
-- ===========================================================================

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
local m_cityReportLoaded:boolean = pcall( function()
	include( "CityReportData" );
	include( "CityReportGather" );
end );
if not m_cityReportLoaded then print( "InGameAccess: the city report files did not load" ); end

-- ===========================================================================
--	MEMBERS
-- ===========================================================================
local MOUSE_MOVE_DELAY		:number = 0.8;		-- seconds to let the camera settle before the real mouse follows the cursor

local m_cursorX				:number = nil;		-- map cursor (plot coordinates)
local m_cursorY				:number = nil;
local m_mouseTimer			:number = -1;		-- >= 0: seconds until the mouse is moved onto the cursor plot
local m_actions				:table = {};		-- actionId -> handler
local H						:table = {};			-- handlers defined late (a chunk holds at most 200 locals, this one was full)
local m_lastAnnouncedTurn	:string = "";		-- "<local player>:<turn>" of the last turn announcement (hotseat: every player hears their turn)
local m_cursorPlayer		:number = -1;		-- local player the cursor belongs to
local m_ready				:boolean = false;	-- a game is loaded (LoadScreenClose seen): event announcements are allowed
local m_mode				:table = nil;		-- the active keyboard mode { name, list, onClose }, see MODES below; nil: none
local m_unitActions			:table = {};		-- plain list of the selected unit's actions, sent by UnitPanel (SRA_UnitActions)
local m_delayed				:table = {};		-- { time = seconds left, fn = function }
local m_enterWatch			:number = -1;		-- >= 0: Enter (Next Action) was pressed; seconds until we check that something was said
local m_enterLabel			:string = "";		-- what the action panel said Enter would do
local m_placeCommitTime		:number = -100;		-- UI.GetElapsedTime() of the last placement commit (its result must outlive the selection that follows)
local m_lastResultTime		:number = -100;		-- UI.GetElapsedTime() of the last announced result of a player's action
local m_movers				:table = {};		-- unit id -> { dest = plot index, issued = time }: units on a move order given in this session
local m_lastKeyTime			:number = -100;		-- UI.GetElapsedTime() of the last key press seen by the input handler
local m_attackIntent		:boolean = false;	-- the MOVE_TO mode was entered with the Attack key: only enemies are valid targets
local m_menuItems			:table = {};		-- items of the unit actions menu, fetched when it opens
local m_unitNames			:table = {};		-- "player:unit" -> spoken name, remembered while the unit is alive (it is gone when its death is reported)
local m_scanOrigin			:number = nil;		-- plot the X scan started from
local m_spotted				:table = {};		-- "player:unit" -> turn the enemy was last announced
local m_spottedTurn			:number = -1;		-- turn m_spottedCount counts
local m_spottedCount		:number = 0;
local m_settleItems			:table = {};		-- its items, from the scan made when it opened
local m_notifData			:table = {};		-- notifications sent by NotificationPanel (SRA_Notifications), plain data
local m_notifAnswered		:boolean = false;	-- NotificationPanel answered the last SRA_RequestNotifications
local m_arrivals			:table = {};		-- texts of notifications that arrived and are not yet announced
local m_arrivalTimer		:number = -1;		-- >= 0: seconds until the arrivals are announced together
local m_lastSelectionSpeech	:number = -100;		-- UI.GetElapsedTime() of the last unit/city selection announcement
local m_pendingUnit			:number = nil;		-- unit selected while the game was still loading: announced once it is ready
local m_placeScan			:table = nil;		-- PlacementScan result of the open placement mode (district / wonder browser)
local m_placeParams			:table = nil;		-- insert-mode parameters read from the interface mode when placement began
local m_placeConfirm		:number = nil;		-- plot index the placement browser asked "Enter to confirm" for
local m_placeBusy			:boolean = false;	-- a tile purchase is waiting for its rescan: Enter says "Wait"
local m_placeReplaced		:boolean = false;	-- the placement mode is closing because another placement mode replaced it
local PlacementPlotText;						-- defined with the placement browser: what the cursor plot means there
local OpenPlacement;

-- ===========================================================================
--	HELPERS
-- ===========================================================================

-- Runs f, printing any error instead of silently losing it. The error handler is captured at load: after a hot reload a
-- stale instance must not look the global up again (it is gone there) and fail with a second error.
local m_errorHandler = KeyNavErrorHandler;
local function Safe( name:string, f )
	return function( ... )
		local count:number = select( "#", ... );
		local args:table = { ... };
		local ok:boolean, err = xpcall( function() return f( unpack(args, 1, count) ); end, m_errorHandler or tostring );
		if not ok then print( "InGameAccess " .. name .. " error: " .. tostring(err) ); end
	end
end

-- Every Events.* / LuaEvents.* listener goes through Listen, so OnShutdown can remove them all. Listeners of a context
-- that was hot reloaded would otherwise survive in the engine, fire in a dead environment and run next to the new ones.
local m_listeners:table = {};
local function Listen( event, fn )
	event.Add( fn );
	table.insert( m_listeners, { event = event, fn = fn } );
end

local function OnShutdown()
	print( "InGameAccess: shutdown, removing " .. #m_listeners .. " listeners" );
	for _, l in ipairs( m_listeners ) do l.event.Remove( l.fn ); end
	m_listeners = {};
end

local function Capitalize( text:string )
	text = string.lower( text );
	return string.upper( string.sub(text, 1, 1) ) .. string.sub( text, 2 );
end

local function IsLocalPlayerActive()
	local localPlayer:number = Game.GetLocalPlayer();
	return localPlayer ~= nil and localPlayer ~= -1 and Players[localPlayer] ~= nil;
end

-- The selected unit or city: what "relative to me" refers to.
local function GetSelectionPlot()
	local unit:table = UI.GetHeadSelectedUnit();
	if unit ~= nil then return Map.GetPlot( unit:GetX(), unit:GetY() ), unit; end
	local city:table = UI.GetHeadSelectedCity();
	if city ~= nil then return Map.GetPlot( city:GetX(), city:GetY() ), nil; end
	return nil, nil;
end

local function FormatNumber( value:number )
	return tostring( math.floor( value * 10 + 0.5 ) / 10 );
end

-- Is one of the game's popups or screens open (the options menu included)? Contexts that are always shown are skipped.
local ALWAYS_SHOWN:table = { TopPanel = true, DiplomacyRibbon = true, PartialScreenHooks = true, InGameAccess = true };

local function IsGamePopupOpen()
	local menu = ContextPtr:LookUpControl( "/InGame/TopOptionsMenu" );
	if menu ~= nil and not menu:IsHidden() then return true; end
	for _, name in ipairs( { "WorldPopups", "FakePopups", "Screens", "PartialScreens", "Diplomacy", "EndGame" } ) do
		local parent = ContextPtr:LookUpControl( "/InGame/" .. name );
		if parent ~= nil then
			for _, child in ipairs( parent:GetChildren() ) do
				if not child:IsHidden() and not ALWAYS_SHOWN[ child:GetID() ] then return true; end
			end
		end
	end
	-- Gathering Storm popups added straight to the InGame context (not under a container)
	for _, name in ipairs( { "EraReviewPopup", "DedicationPopup", "WorldCongressPopup", "WorldCongressIntro", "WorldCongressBetweenTurns" } ) do
		local popup = ContextPtr:LookUpControl( "/InGame/" .. name );
		if popup ~= nil and not popup:IsHidden() then return true; end
	end
	return false;
end

-- Runs fn after the given seconds (from the update loop).
local function After( seconds:number, fn )
	table.insert( m_delayed, { time = seconds, fn = fn } );
end

-- Speaks the result of something the player just did. Selection announcements that follow within a moment (the
-- game selects the next unit) do not cut it off. Only results that follow the player's own key press interrupt;
-- the ones that happen on their own (a multi-turn move at the start of a turn, auto-explore) wait their turn.
local function SayResult( text:string )
	local now:number = UI.GetElapsedTime();
	local own:boolean = now - m_lastKeyTime < 1.0;
	if own then m_lastResultTime = now; end
	OutputMessageToScreenReader( text, not own );
end

local function IsPlotVisibleToLocal( plot:table )
	local vis:table = PlayersVisibility[ Game.GetLocalPlayer() ];
	return vis ~= nil and plot ~= nil and vis:IsVisible( plot:GetIndex() );
end

-- Is this player an enemy of the local player: barbarians and civilizations at war with us.
local function IsHostile( playerID:number )
	local player:table = Players[ playerID ];
	if player == nil or playerID == Game.GetLocalPlayer() then return false; end
	if player:IsBarbarian() then return true; end
	local localPlayer:table = Players[ Game.GetLocalPlayer() ];
	if localPlayer == nil then return false; end
	local diplomacy:table = localPlayer:GetDiplomacy();
	return diplomacy ~= nil and diplomacy:IsAtWarWith( playerID );
end

-- A foreign unit the local player can really see (not fogged, not an invisible submarine ...).
local function IsForeignUnitVisible( unit:table )
	return unit:GetOwner() ~= Game.GetLocalPlayer() and PlotDescription_IsUnitVisible( unit );
end

-- Remembers a unit's spoken name while it is alive: when it dies the unit object is already gone.
local function RememberUnit( unit:table )
	if unit ~= nil then m_unitNames[ unit:GetOwner() .. ":" .. unit:GetID() ] = PlotDescription_GetUnitName( unit ); end
end

-- Is (x, y) within the distance of one of the local player's units or cities?
local function IsNearLocal( x:number, y:number, distance:number )
	local player:table = Players[ Game.GetLocalPlayer() ];
	if player == nil then return false; end
	for _, unit in player:GetUnits():Members() do
		if Map.GetPlotDistance( x, y, unit:GetX(), unit:GetY() ) <= distance then return true; end
	end
	for _, city in player:GetCities():Members() do
		if Map.GetPlotDistance( x, y, city:GetX(), city:GetY() ) <= distance then return true; end
	end
	return false;
end

local function Plural( n:number, one:string, many:string )
	if n == 1 then return n .. " " .. one; end
	return n .. " " .. many;
end

-- Is this one of the local player's units that can found a city?
local function IsSettler( unit:table )
	if unit == nil or unit:GetOwner() ~= Game.GetLocalPlayer() then return false; end
	local row:table = GameInfo.Units[ unit:GetUnitType() ];
	return row ~= nil and row.FoundCity == true;
end

-- Builders (non-combat units with build charges: Builder, Military Engineer): the improvements each unit type can ever
-- build, from Improvement_ValidBuildUnits, cached per unit type.
local m_builderLists:table = {};

local function BuilderImprovements( unit:table )
	if unit == nil or unit:GetOwner() ~= Game.GetLocalPlayer() then return nil; end
	local unitType:number = unit:GetUnitType();
	local cached = m_builderLists[ unitType ];
	if cached ~= nil then return cached.list; end
	local entry:table = { list = nil };
	local row:table = GameInfo.Units[ unitType ];
	if row ~= nil and row.BuildCharges ~= nil and row.BuildCharges > 0 and ( row.Combat or 0 ) == 0 then
		local found:table = {};
		for valid in GameInfo.Improvement_ValidBuildUnits() do
			local improvement:table = ( valid.UnitType == row.UnitType ) and GameInfo.Improvements[ valid.ImprovementType ] or nil;
			if improvement ~= nil then table.insert( found, { hash = improvement.Hash, name = Locale.Lookup( improvement.Name ) } ); end
		end
		if #found > 0 then entry.list = found; end
	end
	m_builderLists[ unitType ] = entry;
	return entry.list;
end

-- "Builder can build: Farm, Mine" / "Builder can build nothing here" for the plot, as the engine answers for this unit
-- (the same check the unit panel makes). Nil when the unit is no builder or the plot is not known.
local function BuilderBuildText( unit:table, plot:table )
	local list:table = BuilderImprovements( unit );
	if list == nil or plot == nil then return nil; end
	local vis:table = PlayersVisibility[ Game.GetLocalPlayer() ];
	if vis == nil or not vis:IsRevealed( plot:GetIndex() ) then return nil; end
	local name:string = Locale.Lookup( GameInfo.Units[ unit:GetUnitType() ].Name );
	if unit:GetMovesRemaining() <= 0 then return name .. " has no moves left"; end
	local operation:number = UnitOperationTypes.BUILD_IMPROVEMENT;
	local names:table = {};
	for _, improvement in ipairs( list ) do
		local params:table = {};
		params[ UnitOperationTypes.PARAM_IMPROVEMENT_TYPE ] = improvement.hash;
		if UnitManager.CanStartOperation( unit, operation, plot, params, false ) then table.insert( names, improvement.name ); end
	end
	if #names == 0 then return name .. " can build nothing here"; end
	if #names > 6 then
		local extra:number = #names - 5;
		names = { names[1], names[2], names[3], names[4], names[5], extra .. " more" };
	end
	return name .. " can build: " .. table.concat( names, ", " );
end

-- The first n good and m bad reasons of a settle candidate as "river, coast, silk, but floods, poor food" (empty when
-- there are none).
local function SettleReasonList( candidate:table, n:number, m:number )
	local parts:table = {};
	for i = 1, math.min( n, #candidate.reasons ) do table.insert( parts, candidate.reasons[i] ); end
	local bad:table = {};
	for i = 1, math.min( m, #candidate.negatives ) do table.insert( bad, candidate.negatives[i] ); end
	local text:string = table.concat( parts, ", " );
	if #bad > 0 then text = text .. ( #parts > 0 and ", " or "" ) .. "but " .. table.concat( bad, ", " ); end
	return text;
end

-- The same with a leading comma (empty when there are none).
local function SettleReasons( candidate:table, n:number, m:number )
	local text:string = SettleReasonList( candidate, n, m or 2 );
	if text == "" then return ""; end
	return ", " .. text;
end

-- One sentence about the settler's plot and the best spot nearby, said when a settler is selected.
-- The terrain and river of the settler's plot are in the unit announcement already: only "can settle" and what is
-- wrong with the plot are said about it.
local function SettleSentence( unit:table )
	local scan:table = SettleScan_Scan( unit );
	local here:table, best:table = scan.here, scan.best;
	local text:string;
	if here ~= nil then
		text = "Can settle here" .. SettleReasons( { reasons = {}, negatives = here.negatives }, 0, 2 );
	elseif scan.hereReason ~= nil and scan.hereReason ~= "" then
		text = "Cannot settle here: " .. scan.hereReason;
	else
		text = "Cannot settle here";
	end
	if best == nil then return text .. ". No spot found nearby."; end
	if best.here then
		local list:string = SettleReasonList( best, 3, 2 );
		return ( here ~= nil and "Can settle here" or text ) .. ", this is the best spot nearby" .. ( list ~= "" and ( ": " .. list ) or "" )
			.. ( unit:GetMovesRemaining() > 0 and ". B to found." or ". B to found next turn." );
	end
	text = text .. ". Best: " .. best.relative .. ", " .. Plural( best.turns, "turn", "turns" ) .. SettleReasons( best, 3 );
	if best.recommended then text = text .. ", recommended"; end
	return text .. ". X to browse.";
end

-- Adds a handler to an event when the game has that event.
local function AddEvent( name:string, handler )
	if Events[name] == nil then
		print( "InGameAccess: unknown event " .. name );
		return;
	end
	Listen( Events[name], Safe( name, handler ) );
end

-- ===========================================================================
--	MODES: the keyboard lists of the hub (unit actions menu, diplomacy list, settle spot browser, top panel,
--	notifications). Exactly one can be active: m_mode holds it, opening one closes the one before, and the input handler
--	gives keys to m_mode.list only. Whatever makes a mode stale (selection change, turn end, load, player change,
--	entering a target mode) closes it through CloseMode, which also resets the list so that it reopens fresh.
--	The engine's target modes (move to, attacks ...) are the other kind of state: they are exclusive with m_mode by
--	CanOpenMode (refuses to open a mode in a target mode) and OnInterfaceModeChanged (entering one closes the mode).
-- ===========================================================================

local function IsModeOpen( name:string )
	return m_mode ~= nil and m_mode.name == name;
end

-- speak: say "Closed" (the player closed it). quiet: closed because it went stale, so a mode's restoring work (the
-- settle browser puts the cursor back on the settler) is not done.
local function CloseMode( speak:boolean, quiet:boolean )
	local mode:table = m_mode;
	if mode == nil then return; end
	m_mode = nil;
	mode.list.Reset();
	if mode.onClose ~= nil then
		local ok:boolean, err = xpcall( function() mode.onClose( quiet == true ); end, KeyNavErrorHandler );
		if not ok then print( "InGameAccess mode close error: " .. tostring( err ) ); end
	end
	if speak then OutputMessageToScreenReader( "Closed" ); end
end

-- Makes the list the active mode (closing the previous one) and announces it.
local function OpenMode( name:string, list:table, title:string, onClose )
	CloseMode( false, false );
	m_mode = { name = name, list = list, onClose = onClose };
	list.Open( title );
end

-- ===========================================================================
--	MAP CURSOR
-- ===========================================================================

-- Keeps the real mouse on the cursor plot (for sighted helpers and for the few things that still click),
-- once the camera has had time to arrive. The plot tooltip must not read the plot again: it is already announced.
local function QueueMouseMove( plot:table )
	LuaEvents.SRA_CursorPlot( plot:GetIndex() );
	m_mouseTimer = MOUSE_MOVE_DELAY;
end

-- Finds where a plot is on the screen by sampling the engine's screen-to-plot mapping (there is no plot-to-screen
-- call). Normalized screen coordinates run from -1 to 1 with y up. Returns pixel coordinates or nil when off screen.
local function FindPlotScreenPos( x:number, y:number )
	local sumX:number, sumY:number, count:number = 0, 0, 0;
	local STEPS:number = 25;
	for iy = -STEPS, STEPS do
		for ix = -STEPS, STEPS do
			local nx:number, ny:number = ix / STEPS, iy / STEPS;
			local px:number, py:number = UI.GetPlotCoordFromNormalizedScreenPos( nx, ny );
			if px == x and py == y then
				sumX = sumX + nx;
				sumY = sumY + ny;
				count = count + 1;
			end
		end
	end
	if count == 0 then return nil; end
	local screenWidth:number, screenHeight:number = UIManager:GetScreenSizeVal();
	return math.floor( ( sumX / count / 2 + 0.5 ) * screenWidth ), math.floor( ( 0.5 - sumY / count / 2 ) * screenHeight );
end

local function UpdateMouse( deltaTime:number )
	if m_mouseTimer < 0 then return; end
	m_mouseTimer = m_mouseTimer - deltaTime;
	if m_mouseTimer >= 0 then return; end
	m_mouseTimer = -1;
	if m_cursorX == nil then return; end
	-- SetCursor asked the camera to put the cursor plot at the screen centre. Near the edge of the map it cannot, and
	-- the mouse at the centre would sit on another plot (and the game would read that one): find the real position.
	local centerX:number, centerY:number = UI.GetPlotCoordFromNormalizedScreenPos( 0, 0 );
	local screenWidth:number, screenHeight:number = UIManager:GetScreenSizeVal();
	if centerX == m_cursorX and centerY == m_cursorY then
		KeyNavMoveMouseToScreen( math.floor( screenWidth / 2 ), math.floor( screenHeight / 2 ) );
		return;
	end
	local px:number, py:number = FindPlotScreenPos( m_cursorX, m_cursorY );
	if px ~= nil then KeyNavMoveMouseToScreen( px, py ); end
end

local function ResetCursor()
	m_cursorX, m_cursorY = nil, nil;
	m_mouseTimer = -1;
	m_cursorPlayer = Game.GetLocalPlayer();
	CloseMode( false, true );		-- another player (hotseat) or a new game: a list of the previous one is stale
end

local function GetCursor()
	if m_cursorPlayer ~= Game.GetLocalPlayer() then ResetCursor(); end	-- hotseat: the next player starts at their own units
	if m_cursorX == nil then
		local plot:table = GetSelectionPlot();
		local capital:table = nil;
		if IsLocalPlayerActive() then capital = Players[ Game.GetLocalPlayer() ]:GetCities():GetCapitalCity(); end
		if plot ~= nil then
			m_cursorX, m_cursorY = plot:GetX(), plot:GetY();
		elseif capital ~= nil then
			m_cursorX, m_cursorY = capital:GetX(), capital:GetY();
		else
			m_cursorX, m_cursorY = UI.GetPlotCoordFromNormalizedScreenPos( 0, 0 );	-- what the camera is looking at
		end
	end
	return m_cursorX, m_cursorY;
end

-- ===========================================================================
--	TARGET MODES: interface modes in which the game wants a plot (move to, attacks ...)
-- ===========================================================================
local m_targetModes:table = {};		-- InterfaceModeTypes value -> spoken name
do
	local names:table = {
		MOVE_TO = "Move to", RANGE_ATTACK = "Ranged attack", AIR_ATTACK = "Air attack", CITY_RANGE_ATTACK = "City ranged attack",
		DISTRICT_RANGE_ATTACK = "District ranged attack", WMD_STRIKE = "Nuclear strike", ICBM_STRIKE = "Missile strike",
		COASTAL_RAID = "Coastal raid", DEPLOY = "Deploy", REBASE = "Rebase", AIRLIFT = "Airlift", FORM_CORPS = "Form corps",
		FORM_ARMY = "Form army",
		NAVAL_GOLD_RAID = "Naval raid", SACRIFICE_SELECTION = "Sacrifice", KILL_WEAKER_UNIT = "Kill weaker unit",
		TRANSFORM_UNIT = "Transform unit", RESTORE_UNIT_MOVES = "Restore moves", PRIORITY_TARGET = "Priority target",
	};
	for name, label in pairs( names ) do
		local mode = InterfaceModeTypes[name];
		if mode ~= nil then m_targetModes[mode] = label; end
	end
end

-- Not target modes although the game wants a choice in them: the trade chooser panels (Choosers/TradeRouteChooser.lua,
-- TradeOriginChooser.lua) own these two modes with their own keyboard lists, speech, Enter and Escape. The hub stays
-- silent and lets every key through (as in the production panel); it only closes its unit menu when one starts.
local m_chooserModes:table = {};
for _, name in ipairs( { "MAKE_TRADE_ROUTE", "TELEPORT_TO_CITY", "SPY_TRAVEL_TO_CITY", "SPY_CHOOSE_MISSION" } ) do
	if InterfaceModeTypes[name] ~= nil then m_chooserModes[ InterfaceModeTypes[name] ] = true; end
end

local function GetTargetMode()
	local mode:number = UI.GetInterfaceMode();
	local label:string = m_targetModes[mode];
	if label ~= nil then return mode, label; end
	return nil, nil;
end

-- A list mode cannot be opened in the middle of a target mode.
local function CanOpenMode()
	if not IsLocalPlayerActive() then return false; end
	if GetTargetMode() ~= nil then
		OutputMessageToScreenReader( "Choose a tile, or Escape to cancel first" );
		return false;
	end
	if IsModeOpen( "placement" ) then
		OutputMessageToScreenReader( "Place it, or Escape to cancel first" );
		return false;
	end
	return true;
end

-- Modes in which a city or district (not a unit) acts.
local function IsCityMode( mode:number )
	return mode == InterfaceModeTypes.CITY_RANGE_ATTACK or mode == InterfaceModeTypes.DISTRICT_RANGE_ATTACK;
end

-- The unit or city that chose a target mode is gone (died, deselected, turn ended): leave the mode, or Enter and
-- Escape would be swallowed by a mode that has nothing to act on.
local function ResetStaleMode()
	if GetTargetMode() ~= nil and UI.GetHeadSelectedUnit() == nil and UI.GetHeadSelectedCity() == nil then
		UI.SetInterfaceMode( InterfaceModeTypes.SELECTION );
	end
end

-- Plot indexes the unit may attack with this operation (ranged / air attack).
local function GetAttackTargets( unit:table, operation:number )
	local set:table = {};
	local results:table = UnitManager.GetOperationTargets( unit, operation );
	if results == nil then return set; end
	local plots:table = results[UnitOperationResults.PLOTS];
	local modifiers:table = results[UnitOperationResults.MODIFIERS];
	if plots == nil or modifiers == nil then return set; end
	for i, plotId in ipairs( plots ) do
		if modifiers[i] == UnitOperationResults.MODIFIER_IS_TARGET then set[ plotId ] = true; end
	end
	return set;
end

-- What the game's combat preview would say for this attack (mirrors UnitPanel ShowCombatAssessment): damage both
-- ways and whether someone dies; walls and city health are told apart, a city never "dies" (it can be captured).
local function IsCityOrDistrictPlot( plot:table )
	if plot:IsCity() then return true; end
	local districtType:number = plot:GetDistrictType();
	if districtType ~= nil and districtType >= 0 then
		local row:table = GameInfo.Districts[ districtType ];
		return row ~= nil and not row.InternalOnly;
	end
	return false;
end

local function CombatPreviewText( unit:table, plot:table, combatType )
	local ok:boolean, results = pcall( CombatManager.SimulateAttackInto, unit:GetComponentID(), combatType, plot:GetX(), plot:GetY() );
	if not ok or results == nil then return nil; end
	local attacker:table = results[CombatResultParameters.ATTACKER];
	local defender:table = results[CombatResultParameters.DEFENDER];
	if attacker == nil or defender == nil then return nil; end
	local parts:table = {};
	local dealt:number = defender[CombatResultParameters.DAMAGE_TO] or 0;
	local defenderMax:number = defender[CombatResultParameters.MAX_HIT_POINTS] or 0;
	local defenderFinal:number = defender[CombatResultParameters.FINAL_DAMAGE_TO] or 0;
	local wallsMax:number = defender[CombatResultParameters.MAX_DEFENSE_HIT_POINTS] or 0;
	local wallsDamage:number = defender[CombatResultParameters.DEFENSE_DAMAGE_TO] or 0;
	local wallsFinal:number = defender[CombatResultParameters.FINAL_DEFENSE_DAMAGE_TO] or 0;
	if results[CombatResultParameters.LOCATION_PILLAGED] then
		table.insert( parts, "would pillage" );
	elseif defenderMax == 0 then
		return "no combat";
	elseif wallsMax > 0 then
		-- a city or district with walls: part of the damage goes to the walls
		if wallsDamage > 0 then
			table.insert( parts, "deals " .. wallsDamage .. " damage to the walls, " .. math.max( 0, wallsMax - wallsFinal ) .. " of " .. wallsMax .. " left" );
		end
		if dealt > wallsDamage or wallsDamage == 0 then
			table.insert( parts, "deals " .. dealt .. " damage to the city, " .. math.max( 0, defenderMax - defenderFinal ) .. " of " .. defenderMax .. " health left" );
		end
	elseif defenderFinal >= defenderMax then
		if IsCityOrDistrictPlot( plot ) then
			table.insert( parts, "health to 0" );
		else
			table.insert( parts, "kills the target" );
		end
	else
		table.insert( parts, "deals " .. dealt .. " damage, target left with " .. ( defenderMax - defenderFinal ) .. " of " .. defenderMax );
	end
	local taken:number = attacker[CombatResultParameters.DAMAGE_TO] or 0;
	local attackerMax:number = attacker[CombatResultParameters.MAX_HIT_POINTS] or 0;
	local attackerFinal:number = attacker[CombatResultParameters.FINAL_DAMAGE_TO] or 0;
	if attackerMax > 0 and attackerFinal >= attackerMax then
		table.insert( parts, "you would die" );
	elseif taken > 0 then
		table.insert( parts, "you take " .. taken );
	else
		table.insert( parts, "no damage to you" );
	end
	return table.concat( parts, ", " );
end

-- Players the move or attack of this unit onto the plot would declare war on (nil: none).
local function WarTargets( unit:table, plot:table )
	if unit == nil or plot == nil or not IsPlotVisibleToLocal( plot ) then return nil; end
	local ok:boolean, results = pcall( CombatManager.IsAttackChangeWarState, unit:GetComponentID(), plot:GetX(), plot:GetY() );
	if ok and results ~= nil and #results > 0 then return results; end
	return nil;
end

local function WarTargetNames( targets:table )
	local names:table = {};
	for _, playerID in ipairs( targets ) do table.insert( names, PlotDescription_GetCivName( playerID ) ); end
	return table.concat( names, " and " );
end

-- A visible unit or city of someone we are at war with (or barbarians) on the plot.
local function EnemyVisibleAt( plot:table )
	if not IsPlotVisibleToLocal( plot ) then return false; end
	for _, other in ipairs( Units.GetUnitsInPlot( plot ) ) do
		if IsForeignUnitVisible( other ) and IsHostile( other:GetOwner() ) then return true; end
	end
	if plot:IsCity() then
		local city:table = Cities.GetCityInPlot( plot:GetX(), plot:GetY() );
		if city ~= nil and IsHostile( city:GetOwner() ) then return true; end
	end
	return false;
end

-- City and district ranged attacks (no unit): the plot indexes the selected city may hit.
local function GetCityAttackTargets( city:table )
	local set:table = {};
	local ok:boolean, results = pcall( function()
		local parameters:table = {};
		parameters[CityCommandTypes.PARAM_RANGED_ATTACK] = UI.GetInterfaceModeParameter( CityCommandTypes.PARAM_RANGED_ATTACK );
		return CityManager.GetCommandTargets( city, CityCommandTypes.RANGE_ATTACK, parameters );
	end );
	if not ok or results == nil then return nil; end
	local plots:table = results[CityCommandResults.PLOTS];
	local modifiers:table = results[CityCommandResults.MODIFIERS];
	if plots == nil or modifiers == nil then return nil; end
	for i, plotId in ipairs( plots ) do
		if modifiers[i] == CityCommandResults.MODIFIER_IS_TARGET then set[ plotId ] = true; end
	end
	return set;
end

-- Mode specific words for the cursor plot: path length for a move, valid target and odds for an attack.
local function TargetInfo( mode:number, plot:table, unit:table )
	if unit == nil then
		if mode == InterfaceModeTypes.CITY_RANGE_ATTACK or mode == InterfaceModeTypes.DISTRICT_RANGE_ATTACK then
			local city:table = UI.GetHeadSelectedCity();
			local targets:table = ( city ~= nil ) and GetCityAttackTargets( city ) or nil;
			if targets == nil then return nil; end
			if targets[ plot:GetIndex() ] then return "valid target"; end
			return "no target";
		end
		return nil;
	end
	if mode == InterfaceModeTypes.MOVE_TO then
		if unit:GetX() == plot:GetX() and unit:GetY() == plot:GetY() then return "here"; end
		local war:table = WarTargets( unit, plot );
		local path:table = UnitManager.GetMoveToPathEx( unit, plot:GetIndex() );
		local reachable:boolean = path ~= nil and path.plots ~= nil and #path.plots >= 2;
		local enemy:boolean = EnemyVisibleAt( plot );
		if not reachable and war == nil then
			if m_attackIntent and enemy then return "enemy, cannot reach"; end
			return "unreachable";
		end
		local text:string = "";
		local turns:number = 1;
		if reachable then
			turns = path.turns[ #path.turns ] or 1;
			text = Plural( turns, "turn", "turns" );
		end
		if enemy or war ~= nil then
			text = ( text ~= "" ) and ( "attack, " .. text ) or "attack";
			if turns <= 1 then
				local preview:string = CombatPreviewText( unit, plot, nil );
				if preview ~= nil then text = text .. ", " .. preview; end
			end
		elseif m_attackIntent then
			return "no enemy";
		end
		if war ~= nil then text = "would declare war on " .. WarTargetNames( war ) .. ", " .. text; end
		return text;
	elseif mode == InterfaceModeTypes.RANGE_ATTACK or mode == InterfaceModeTypes.AIR_ATTACK then
		local operation:number = ( mode == InterfaceModeTypes.RANGE_ATTACK ) and UnitOperationTypes.RANGE_ATTACK or UnitOperationTypes.AIR_ATTACK;
		local war:table = WarTargets( unit, plot );
		if not GetAttackTargets( unit, operation )[ plot:GetIndex() ] and war == nil then return "no target"; end
		local combatType = nil;
		if mode == InterfaceModeTypes.RANGE_ATTACK then
			combatType = CombatTypes.RANGED;
			if unit:GetBombardCombat() > unit:GetRangedCombat() then combatType = CombatTypes.BOMBARD; end
		end
		local preview:string = CombatPreviewText( unit, plot, combatType );
		local text:string = "valid target" .. ( preview ~= nil and ( ", " .. preview ) or "" );
		if war ~= nil then text = "would declare war on " .. WarTargetNames( war ) .. ", " .. text; end
		return text;
	end
	return nil;
end

local function DescribeCursorPlot( plot:table )
	local selectionPlot:table, unit:table = GetSelectionPlot();
	local options:table = {};
	local localPlayer:number = Game.GetLocalPlayer();
	if unit ~= nil and unit:GetOwner() == localPlayer then options.excludeUnitId = unit:GetID(); end
	local text:string = PlotDescription_GetShort( plot, options );
	local mode:number = GetTargetMode();
	local placement:string = PlacementPlotText( plot );
	if placement ~= nil then
		text = placement .. ". " .. text;
	elseif mode ~= nil then
		local info:string = TargetInfo( mode, plot, unit );
		if info ~= nil then text = info .. ". " .. text; end
		local build:string = ( unit ~= nil and unit:GetOwner() == localPlayer ) and BuilderBuildText( unit, plot ) or nil;		-- builders walking to a tile
		if build ~= nil then text = text .. ", " .. build; end
	elseif IsSettler( unit ) then
		local ok:boolean, reason = SettleScan_CanFound( unit, plot );
		text = text .. ( ok and ", can settle" or ( ", " .. SettleScan_CannotText( reason ) ) );
	elseif unit ~= nil then
		local build:string = BuilderBuildText( unit, plot );
		if build ~= nil then text = text .. ", " .. build; end
	end
	local relative:string = PlotDescription_GetRelative( selectionPlot, plot );
	if relative ~= nil then text = text .. ". " .. relative; end
	return text;
end

-- Puts the cursor on (x, y), moves the camera there and optionally speaks the plot.
-- noMouse: the real mouse does not follow (browsing a list of candidates: the mouse must not sit on every one of them).
local function SetCursor( x:number, y:number, speak:boolean, interrupt:boolean, noMouse:boolean )
	local plot:table = Map.GetPlot( x, y );
	if plot == nil then return; end
	m_cursorPlayer = Game.GetLocalPlayer();
	m_cursorX, m_cursorY = x, y;
	if m_placeConfirm ~= nil and m_placeConfirm ~= plot:GetIndex() then m_placeConfirm = nil; end		-- moved away from the tile to confirm
	UI.LookAtPlotScreenPosition( x, y, 0.5, 0.5 );
	if noMouse then
		m_mouseTimer = -1;
	else
		QueueMouseMove( plot );
	end
	if speak then
		OutputMessageToScreenReader( DescribeCursorPlot( plot ), not interrupt );
	end
end

-- Shift+Arrows. Left/Right step along the row; Up/Down step to the next row north/south (alternately north-west
-- and north-east, so that two steps go straight north, as on the screen).
local function MoveCursor( dx:number, dy:number )
	if not IsLocalPlayerActive() then return; end
	local x:number, y:number = GetCursor();
	x = x + dx;
	y = y + dy;
	local width:number, height:number = Map.GetGridSize();
	if y < 0 or y >= height then
		OutputMessageToScreenReader( "Edge of the map" );
		return;
	end
	if x < 0 or x >= width then
		if Map.IsWrapX() then
			x = x % width;
		else
			OutputMessageToScreenReader( "Edge of the map" );
			return;
		end
	end
	SetCursor( x, y, true, true );
end

-- Period: the cursor goes to the selected unit or city and says what is there.
local function CursorToSelection()
	if not IsLocalPlayerActive() then return; end
	local plot:table, unit:table = GetSelectionPlot();
	if plot == nil then
		OutputMessageToScreenReader( "Nothing selected" );
		return;
	end
	SetCursor( plot:GetX(), plot:GetY(), false );
	local options:table = {};
	if unit ~= nil then options.excludeUnitId = unit:GetID(); end
	local name:string = "";	-- a selected city is named by its own plot description
	if unit ~= nil then name = Locale.Lookup( unit:GetName() ) .. ". "; end
	OutputMessageToScreenReader( name .. PlotDescription_GetShort( plot, options ) );
end

local function SelectUnitObject( unit:table )
	UI.DeselectAllCities();
	UI.DeselectUnit( unit );
	UI.SelectUnit( unit );
	if UI.RebuildSelectionList ~= nil then UI.RebuildSelectionList( unit ); end
end

-- Control+K: select the next of all the local player's units (also fortified, sleeping and automated ones), by unit id.
local function CycleAllUnits()
	if not IsLocalPlayerActive() then return; end
	local units:table = {};
	for _, unit in Players[ Game.GetLocalPlayer() ]:GetUnits():Members() do table.insert( units, unit ); end
	if #units == 0 then
		OutputMessageToScreenReader( "You have no units" );
		return;
	end
	table.sort( units, function( a, b ) return a:GetID() < b:GetID(); end );
	local selected:table = UI.GetHeadSelectedUnit();
	local current:number = 0;
	if selected ~= nil then
		for i, unit in ipairs( units ) do
			if unit:GetID() == selected:GetID() then current = i; end
		end
	end
	SelectUnitObject( units[ current % #units + 1 ] );
end

-- K: select the unit (or city) of the local player on the cursor plot; pressed again it cycles through them.
-- Needed to wake fortified units and to pick one of a stack, which Next Action never selects.
local function SelectAtCursor()
	if not IsLocalPlayerActive() then return; end
	local x:number, y:number = GetCursor();
	local plot:table = Map.GetPlot( x, y );
	if plot == nil then return; end
	local localPlayer:number = Game.GetLocalPlayer();
	local candidates:table = {};
	for _, unit in ipairs( Units.GetUnitsInPlot( plot ) ) do
		if unit:GetOwner() == localPlayer then table.insert( candidates, { unit = unit } ); end
	end
	local city:table = Cities.GetCityInPlot( x, y );
	if city ~= nil and city:GetOwner() == localPlayer then table.insert( candidates, { city = city } ); end
	if #candidates == 0 then
		OutputMessageToScreenReader( "Nothing of yours here" );
		return;
	end
	local selectedUnit:table = UI.GetHeadSelectedUnit();
	local selectedCity:table = UI.GetHeadSelectedCity();
	local current:number = 0;
	for i, candidate in ipairs( candidates ) do
		if candidate.unit ~= nil and selectedUnit ~= nil and candidate.unit:GetID() == selectedUnit:GetID() then current = i; end
		if candidate.city ~= nil and selectedUnit == nil and selectedCity ~= nil and candidate.city:GetID() == selectedCity:GetID() then current = i; end
	end
	local target:table = candidates[ current % #candidates + 1 ];
	if target.unit ~= nil then
		SelectUnitObject( target.unit );
	else
		UI.DeselectAllUnits();
		UI.SelectCity( target.city );
	end
end

-- X: the cursor jumps to the nearest plot with foreign units in view (hostile ones first); pressed again, to the
-- next one. One stop per plot (the plot description lists the stack). Finds targets for the attack modes, and
-- threats in general. Said like a cursor move, so target modes add their info.
local m_scanKey:string = nil;
local function ScanUnits( interrupt:boolean )
	if not IsLocalPlayerActive() then return; end
	if interrupt == nil then interrupt = true; end
	local localPlayer:number = Game.GetLocalPlayer();
	local originPlot:table = GetSelectionPlot();
	if originPlot == nil then
		local x:number, y:number = GetCursor();
		originPlot = Map.GetPlot( x, y );
	end
	-- a scan that starts from somewhere else starts again at the nearest plot
	if m_scanOrigin ~= originPlot:GetIndex() then
		m_scanOrigin = originPlot:GetIndex();
		m_scanKey = nil;
	end
	local byPlot:table = {};
	local found:table = {};
	for playerID = 0, 63 do
		local player:table = Players[ playerID ];
		if playerID ~= localPlayer and player ~= nil and player:IsAlive() then
			local hostile:boolean = IsHostile( playerID );
			for _, unit in player:GetUnits():Members() do
				local distance:number = Map.GetPlotDistance( originPlot:GetX(), originPlot:GetY(), unit:GetX(), unit:GetY() );
				if distance <= 10 and PlotDescription_IsUnitVisible( unit ) then
					local plotIndex:number = Map.GetPlot( unit:GetX(), unit:GetY() ):GetIndex();
					local entry:table = byPlot[ plotIndex ];
					if entry == nil then
						entry = { key = tostring( plotIndex ), x = unit:GetX(), y = unit:GetY(), distance = distance, hostile = false };
						byPlot[ plotIndex ] = entry;
						table.insert( found, entry );
					end
					if hostile then entry.hostile = true; end
				end
			end
		end
	end
	if #found == 0 then
		OutputMessageToScreenReader( "No foreign units in view" );
		return;
	end
	table.sort( found, function( a, b )
		if a.hostile ~= b.hostile then return a.hostile; end
		if a.distance ~= b.distance then return a.distance < b.distance; end
		return a.key < b.key;
	end );
	local next:number = 1;
	for i, entry in ipairs( found ) do
		if entry.key == m_scanKey then next = i % #found + 1; end
	end
	m_scanKey = found[ next ].key;
	SetCursor( found[ next ].x, found[ next ].y, true, interrupt );
end

-- I: details of the cursor plot.
local function SpeakPlotDetails()
	if not IsLocalPlayerActive() then return; end
	local x:number, y:number = GetCursor();
	local plot:table = Map.GetPlot( x, y );
	local selectionPlot:table, unit:table = GetSelectionPlot();
	local options:table = {};
	if unit ~= nil then options.excludeUnitId = unit:GetID(); end
	local text:string = PlotDescription_GetDetailed( plot, options );
	local relative:string = PlotDescription_GetRelative( selectionPlot, plot );
	if relative ~= nil then text = text .. ". " .. relative; end
	local build:string = ( unit ~= nil and GetTargetMode() == nil ) and BuilderBuildText( unit, plot ) or nil;
	if build ~= nil then text = text .. ". " .. build; end
	OutputMessageToScreenReader( text );
end

-- ===========================================================================
--	WHAT IS NEXT (N)
-- ===========================================================================

-- What the Next Action key (Enter) will do, as the game's action panel says it ("Unit needs orders", "Choose
-- production", "Next turn", ...). Read from the panel's own label so that expansion blockers are covered too.
local function SpeakWhatsNext()
	if not IsLocalPlayerActive() then return; end
	local label:table = ContextPtr:LookUpControl( "/InGame/HUD/ActionPanel/EndTurnText" );
	local text:string = nil;
	if label ~= nil then text = CleanTextForSpeech( label:GetText() ); end
	if text == nil or text == "" then
		OutputMessageToScreenReader( "Next action unknown" );
		return;
	end
	-- The game's "Please wait" while a World Congress session is open: say what actually blocks the turn
	local okWait:boolean, isWait:boolean = pcall( function()
		-- (the label also stays on the plain end-turn text after Escape closed the popup, while the Resume Congress blocker is pending)
		for _, key in ipairs( { "LOC_ACTION_PANEL_PLEASE_WAIT", "LOC_ACTION_PANEL_NEXT_TURN", "LOC_ACTION_PANEL_END_TURN" } ) do
			if string.lower( text ) == string.lower( CleanTextForSpeech( Locale.Lookup( key ) ) ) then return true; end
		end
		return string.lower( text ) == "end turn";
	end );
	if okWait and isWait then
		local okCongress:boolean, inSession:boolean = pcall( function() return Game.GetWorldCongress():IsInSession(); end );
		if okCongress and inSession then
			OutputMessageToScreenReader( "World Congress in session. Enter or Control+N resumes it" );
			return;
		end
	end
	OutputMessageToScreenReader( Capitalize( text ) );
end

-- ===========================================================================
--	ANNOUNCEMENTS
-- ===========================================================================

local function UnitText( unit:table )
	local parts:table = { Locale.Lookup( unit:GetName() ) };
	local maxMoves:number = unit:GetMaxMoves();
	if maxMoves > 0 then
		table.insert( parts, FormatNumber( unit:GetMovesRemaining() ) .. " of " .. FormatNumber( maxMoves ) .. " moves" );
	end
	local row:table = GameInfo.Units[ unit:GetUnitType() ];
	if row ~= nil and row.BuildCharges ~= nil and row.BuildCharges > 0 then
		local charges:number = unit:GetBuildCharges();
		table.insert( parts, charges .. ( charges == 1 and " charge" or " charges" ) );
	end
	local damage:number = unit:GetDamage();
	if damage > 0 then
		table.insert( parts, ( unit:GetMaxDamage() - damage ) .. " of " .. unit:GetMaxDamage() .. " health" );
	end
	return table.concat( parts, ", " );
end

-- The settle sentence for a selected settler (after the unit announcement, so it does not interrupt it).
local m_lastSettleSpoken:string = nil;	-- unit, plot, turn and moves of the last settle sentence

local function SpeakSettleSentence( unit:table )
	if not IsSettler( unit ) then return; end
	-- Next Action reselecting the same settler where it stood this turn: nothing new to say
	local spokenKey:string = table.concat( { unit:GetID(), unit:GetX(), unit:GetY(), Game.GetCurrentGameTurn(), unit:GetMovesRemaining() }, ":" );
	if spokenKey == m_lastSettleSpoken then return; end
	local ok:boolean, sentence = xpcall( function() return SettleSentence( unit ); end, KeyNavErrorHandler );
	if ok then
		m_lastSettleSpoken = spokenKey;
		OutputMessageToScreenReader( sentence, true );
	else
		print( "InGameAccess settle scan error: " .. tostring( sentence ) );
	end
end

local function OnUnitSelectionChanged( playerID:number, unitID:number, hexI:number, hexJ:number, hexK:number, isSelected:boolean, isEditable:boolean )
	if playerID ~= Game.GetLocalPlayer() then return; end
	CloseMode( false, true );
	if not isSelected then
		ResetStaleMode();
		return;
	end
	m_enterWatch = -1;
	local unit:table = Players[playerID]:GetUnits():FindID( unitID );
	if unit == nil then return; end
	-- a move order that is no longer under way is forgotten
	if m_movers[ unitID ] ~= nil and UnitManager.GetQueuedDestination( unit ) == nil then m_movers[ unitID ] = nil; end
	local plot:table = Map.GetPlot( unit:GetX(), unit:GetY() );
	if plot == nil then return; end
	SetCursor( plot:GetX(), plot:GetY(), false );
	local text:string = UnitText( unit ) .. ". " .. PlotDescription_GetShort( plot, { excludeUnitId = unit:GetID() } );
	if not m_ready then
		-- the game is still loading: it would be spoken before "CONTINUE GAME. Press Enter to start."; said once ready, see OnLoadScreenClose
		m_pendingUnit = unitID;
		return;
	end
	m_lastSelectionSpeech = UI.GetElapsedTime();
	local sinceCommit:number = UI.GetElapsedTime() - m_placeCommitTime;
	OutputMessageToScreenReader( text, UI.GetElapsedTime() - m_lastResultTime < 1.5 or sinceCommit < 3.0 );
	SpeakSettleSentence( unit );
end

local function CityProductionText( city:table )
	local queue:table = city:GetBuildQueue();
	if queue == nil then return nil; end
	local hash:number = queue:GetCurrentProductionTypeHash();
	if hash == nil or hash == 0 then return "No production"; end
	local row:table = GameInfo.Buildings[hash] or GameInfo.Districts[hash] or GameInfo.Units[hash] or GameInfo.Projects[hash];
	if row == nil then return nil; end
	local text:string = Locale.Lookup( row.Name );
	local turns:number = queue:GetTurnsLeft();
	if turns ~= nil and turns > 0 then
		text = text .. ", " .. turns .. ( turns == 1 and " turn" or " turns" );
	end
	return text;
end

local function CityGrowthText( city:table )
	local growth:table = city:GetGrowth();
	if growth == nil then return nil; end
	local turns:number = growth:GetTurnsUntilGrowth();
	if turns ~= nil and turns > 0 and turns ~= -1 then
		return "grows in " .. turns .. ( turns == 1 and " turn" or " turns" );
	end
	local starve:number = growth:GetTurnsUntilStarvation();
	if starve ~= nil and starve > 0 and starve ~= -1 then
		return "starving in " .. starve .. ( starve == 1 and " turn" or " turns" );
	end
	return "not growing";
end

local function OnCitySelectionChanged( owner:number, cityID:number, i:number, j:number, k:number, isSelected:boolean, isEditable:boolean )
	if owner ~= Game.GetLocalPlayer() then return; end
	CloseMode( false, true );
	if not isSelected then return; end
	m_enterWatch = -1;
	local city:table = Players[owner]:GetCities():FindID( cityID );
	if city == nil then return; end
	local plot:table = Map.GetPlot( city:GetX(), city:GetY() );
	if plot ~= nil then SetCursor( plot:GetX(), plot:GetY(), false ); end
	local parts:table = { Locale.Lookup( city:GetName() ), Locale.Lookup( "LOC_HUD_CITY_POPULATION" ) .. " " .. city:GetPopulation() };
	local production:string = CityProductionText( city );
	if production ~= nil then table.insert( parts, production ); end
	local growth:string = CityGrowthText( city );
	if growth ~= nil then table.insert( parts, growth ); end
	m_lastSelectionSpeech = UI.GetElapsedTime();
	OutputMessageToScreenReader( table.concat( parts, ", " ) );
end

-- "Turn 5, 3600 BC". Said once per turn: a new turn and a finished load both announce it, and a loaded game
-- gets no turn-begin event at all.
local function AnnounceTurn()
	if not IsLocalPlayerActive() then return; end
	local turn:number = Game.GetCurrentGameTurn();
	local key:string = Game.GetLocalPlayer() .. ":" .. turn;
	if key == m_lastAnnouncedTurn then return; end
	m_lastAnnouncedTurn = key;
	if m_cursorPlayer ~= Game.GetLocalPlayer() then ResetCursor(); end
	OutputMessageToScreenReader( "Turn " .. turn .. ", " .. Calendar.MakeYearStr( turn ), true );
end

-- The selection that happened while the game was loading, said again now that it is ready.
local function AnnouncePendingUnit()
	local unitID:number = m_pendingUnit;
	m_pendingUnit = nil;
	if unitID == nil or not IsLocalPlayerActive() then return; end
	local unit:table = UI.GetHeadSelectedUnit();
	if unit == nil or unit:GetID() ~= unitID or unit:GetOwner() ~= Game.GetLocalPlayer() then return; end
	local plot:table = Map.GetPlot( unit:GetX(), unit:GetY() );
	if plot == nil then return; end
	OutputMessageToScreenReader( UnitText( unit ) .. ". " .. PlotDescription_GetShort( plot, { excludeUnitId = unit:GetID() } ), true );
	SpeakSettleSentence( unit );
end

-- A game was loaded or started: forget everything about the previous one.
local function OnLoadScreenClose()
	m_lastAnnouncedTurn = "";
	m_lastSettleSpoken = nil;
	ResetCursor();
	m_ready = true;
	m_movers = {};
	m_spotted = {};
	m_arrivals = {};
	m_arrivalTimer = -1;
	CloseMode( false, true );
	-- The unit that was selected while the game loaded (the turn 1 settler!) was announced into the load screen and
	-- without the settle sentence: say it again once the turn announcement is out.
	if m_pendingUnit ~= nil then After( 1.0, function() AnnouncePendingUnit(); end ); end
	-- A save made between turns loads before the player's turn has begun (LocalPlayerTurnBegin follows and announces
	-- the right turn); announce here only when the turn is already running, with a late fallback.
	local player:table = Players[ Game.GetLocalPlayer() ];
	if player ~= nil and player:IsTurnActive() then
		AnnounceTurn();
	else
		After( 3, AnnounceTurn );
	end
end

local function OnLocalPlayerTurnEnd()
	CloseMode( false, true );
	m_enterWatch = -1;
	if GetTargetMode() ~= nil then UI.SetInterfaceMode( InterfaceModeTypes.SELECTION ); end
	-- The event also fires when ending the turn is refused a moment later (a unit that finished exploring asks for
	-- orders, turn number unchanged). Already inactive at event time: the turn really ended, say it now (a deferred
	-- line could land after the next "Turn N"). Still active: check again shortly and speak only if the same turn
	-- is now over; a new turn has announced itself.
	local turn:number = Game.GetCurrentGameTurn();
	local player:table = Players[ Game.GetLocalPlayer() ];
	if player == nil or not player:IsTurnActive() then
		OutputMessageToScreenReader( "Turn ended", true );
		return;
	end
	After( 0.7, function()
		local current:table = Players[ Game.GetLocalPlayer() ];
		if Game.GetCurrentGameTurn() == turn and ( current == nil or not current:IsTurnActive() ) then
			OutputMessageToScreenReader( "Turn ended", true );
		end
	end );
end

-- ===========================================================================
--	TARGET MODES: entering, confirming (Enter) and cancelling (Escape)
-- ===========================================================================
local function OnInterfaceModeChanged( oldMode:number, newMode:number )
	-- the unit menu is about the mode the game was in; any list is out of place in a target mode
	if m_mode ~= nil and ( m_mode.name == "menu" or m_targetModes[ newMode ] ~= nil or m_chooserModes[ newMode ] ) then CloseMode( false, true ); end
	-- placing a district or wonder: the placement browser opens; it ends with the mode (placed, cancelled or replaced)
	if IsModeOpen( "placement" ) then
		m_placeReplaced = ( newMode == InterfaceModeTypes.DISTRICT_PLACEMENT or newMode == InterfaceModeTypes.BUILDING_PLACEMENT );
		CloseMode( false, true );
		m_placeReplaced = false;
	end
	if newMode == InterfaceModeTypes.DISTRICT_PLACEMENT or newMode == InterfaceModeTypes.BUILDING_PLACEMENT then
		OpenPlacement( newMode );
		return;
	end
	m_enterWatch = -1;
	if newMode ~= InterfaceModeTypes.MOVE_TO then m_attackIntent = false; end
	local label:string = m_targetModes[ newMode ];
	if label == nil then return; end
	-- the cursor starts at the acting unit or city, and the tiles are chosen from there
	local plot:table = GetSelectionPlot();
	if plot ~= nil then SetCursor( plot:GetX(), plot:GetY(), false ); end
	if newMode == InterfaceModeTypes.MOVE_TO and m_attackIntent then
		OutputMessageToScreenReader( "Attack: choose a target with Shift+Arrows or X, Enter to attack, Escape to cancel" );
		return;
	end
	OutputMessageToScreenReader( label .. ": choose a tile with Shift+Arrows, Enter to confirm, Escape to cancel" );
end

-- For modes without a direct call below: click the plot with the real mouse, like a sighted player would.
local function ClickCursorPlot()
	local x:number, y:number = GetCursor();
	local screenWidth:number, screenHeight:number = UIManager:GetScreenSizeVal();
	local px:number, py:number = math.floor( screenWidth / 2 ), math.floor( screenHeight / 2 );
	local centerX:number, centerY:number = UI.GetPlotCoordFromNormalizedScreenPos( 0, 0 );
	if centerX ~= x or centerY ~= y then
		px, py = FindPlotScreenPos( x, y );
		if px == nil then
			SayResult( "That tile is off screen" );
			return;
		end
	end
	m_lastKeyTime = UI.GetElapsedTime();	-- the click is the player's own action
	KeyNavMoveMouseToScreen( px, py );
	After( 0.4, function() KeyNavLeftClick(); end );
end

-- Orders the unit to the plot through the game's own path (war declaration check included). A plain move is
-- remembered so that arrival or a stop can be told; an attack or a war declaration (the game asks first, and the
-- order only goes out after the answer) is not a move order.
local function IssueMoveOrder( unit:table, plot:table, war:table, enemy:boolean )
	local unitID:number = unit:GetID();
	local record:table = nil;
	if war == nil and not enemy then
		record = { dest = plot:GetIndex(), issued = UI.GetElapsedTime(), from = Map.GetPlot( unit:GetX(), unit:GetY() ):GetIndex() };
		m_movers[ unitID ] = record;
	end
	MoveUnitToPlot( unit, plot:GetX(), plot:GetY() );
	if record ~= nil then
		After( 1.0, function()
			-- the order never started: blocked at once
			if m_movers[ unitID ] ~= record then return; end
			local mover:table = Players[ Game.GetLocalPlayer() ]:GetUnits():FindID( unitID );
			if mover ~= nil and Map.GetPlot( mover:GetX(), mover:GetY() ):GetIndex() == record.from and UnitManager.GetQueuedDestination( mover ) == nil then
				m_movers[ unitID ] = nil;
				SayResult( "Move blocked, the unit did not move" );
			end
		end );
	end
end

-- Enter in a target mode: what WorldInput does on the left click in that mode, for the cursor plot.
local function ConfirmTarget()
	local mode:number, label:string = GetTargetMode();
	if mode == nil then return; end
	local x:number, y:number = GetCursor();
	local plot:table = Map.GetPlot( x, y );
	local unit:table = UI.GetHeadSelectedUnit();
	if plot == nil then return; end
	if unit == nil and not IsCityMode( mode ) then
		-- nothing is selected any more (the unit died or was deselected): leave the mode
		UI.SetInterfaceMode( InterfaceModeTypes.SELECTION );
		SayResult( "Nothing selected, cancelled" );
		return;
	end
	if mode == InterfaceModeTypes.MOVE_TO and unit ~= nil then
		if unit:GetX() == x and unit:GetY() == y then
			SayResult( "Already here, choose another tile" );
			return;
		end
		local war:table = WarTargets( unit, plot );
		local enemy:boolean = EnemyVisibleAt( plot );
		if war == nil then
			if m_attackIntent and not enemy then
				SayResult( "No enemy there, choose a target" );
				return;
			end
			local path:table = UnitManager.GetMoveToPathEx( unit, plot:GetIndex() );
			if path == nil or path.plots == nil or #path.plots < 2 then
				SayResult( "Unreachable" );
				return;
			end
		end
		IssueMoveOrder( unit, plot, war, enemy );
		UI.SetInterfaceMode( InterfaceModeTypes.SELECTION );
	elseif mode == InterfaceModeTypes.RANGE_ATTACK and unit ~= nil then
		local parameters:table = {};
		parameters[UnitOperationTypes.PARAM_X] = x;
		parameters[UnitOperationTypes.PARAM_Y] = y;
		local war:table = WarTargets( unit, plot );
		if war ~= nil then
			LuaEvents.Civ6Common_ConfirmWarDialog( unit:GetOwner(), war[1], WarTypes.SURPRISE_WAR );
		elseif UnitManager.CanStartOperation( unit, UnitOperationTypes.RANGE_ATTACK, nil, parameters ) then
			UnitManager.RequestOperation( unit, UnitOperationTypes.RANGE_ATTACK, parameters );
			UI.SetInterfaceMode( InterfaceModeTypes.SELECTION );
			SayResult( "Ranged attack" );
		else
			SayResult( "No valid target there" );
		end
	elseif mode == InterfaceModeTypes.AIR_ATTACK and unit ~= nil then
		local parameters:table = {};
		parameters[UnitOperationTypes.PARAM_X] = x;
		parameters[UnitOperationTypes.PARAM_Y] = y;
		local war:table = WarTargets( unit, plot );
		if war ~= nil then
			LuaEvents.Civ6Common_ConfirmWarDialog( unit:GetOwner(), war[1], WarTypes.SURPRISE_WAR );
		elseif UnitManager.CanStartOperation( unit, UnitOperationTypes.AIR_ATTACK, nil, parameters ) then
			UnitManager.RequestOperation( unit, UnitOperationTypes.AIR_ATTACK, parameters );
			UI.SetInterfaceMode( InterfaceModeTypes.SELECTION );
			SayResult( "Air attack" );
		else
			SayResult( "No valid target there" );
		end
	elseif IsCityMode( mode ) then
		-- city and district ranged attacks: the targets come from the game; the attack itself is a click
		local city:table = UI.GetHeadSelectedCity();
		local targets:table = ( city ~= nil ) and GetCityAttackTargets( city ) or nil;
		if targets ~= nil and not targets[ plot:GetIndex() ] then
			SayResult( "No valid target there" );
			return;
		end
		ClickCursorPlot();
	else
		ClickCursorPlot();
	end
end

local function CancelTarget()
	UI.SetInterfaceMode( InterfaceModeTypes.SELECTION );
	SayResult( "Cancelled" );
end

-- W (Attack). The game's own Attack hotkey only works while the mouse hovers an enemy (a combat preview is shown);
-- UnitPanel sends SRA_AttackKey when that is not the case. A ranged or air unit enters its attack mode, any other
-- military unit the move mode in which only enemies are valid ("Attack"). In a target mode W confirms, like Enter.
local function AttackKey()
	if not IsLocalPlayerActive() then return; end
	local mode:number = GetTargetMode();
	if mode ~= nil then
		if mode == InterfaceModeTypes.MOVE_TO and not m_attackIntent then
			m_attackIntent = true;
			OutputMessageToScreenReader( "Attack: choose a target with Shift+Arrows or X, Enter to attack, Escape to cancel" );
			ScanUnits( false );
		else
			ConfirmTarget();
		end
		return;
	end
	local unit:table = UI.GetHeadSelectedUnit();
	if unit == nil or unit:GetOwner() ~= Game.GetLocalPlayer() then
		OutputMessageToScreenReader( "No unit selected" );
		return;
	end
	local name:string = Locale.Lookup( unit:GetName() );
	if unit:GetCombat() <= 0 and unit:GetRangedCombat() <= 0 and unit:GetBombardCombat() <= 0 then
		OutputMessageToScreenReader( name .. " cannot attack" );
		return;
	end
	if unit:GetMovesRemaining() <= 0 then
		OutputMessageToScreenReader( name .. " has no moves left" );
		return;
	end
	local row:table = GameInfo.Units[ unit:GetUnitType() ];
	if row ~= nil and row.Domain == "DOMAIN_AIR" then
		UI.SetInterfaceMode( InterfaceModeTypes.AIR_ATTACK );
	elseif unit:GetRangedCombat() > unit:GetCombat() or unit:GetBombardCombat() > unit:GetCombat() then
		UI.SetInterfaceMode( InterfaceModeTypes.RANGE_ATTACK );
	else
		m_attackIntent = true;
		UI.SetInterfaceMode( InterfaceModeTypes.MOVE_TO );
	end
	After( 0.3, function() if GetTargetMode() ~= nil then ScanUnits( false ); end end );
end

-- ===========================================================================
--	SETTLE SPOT BROWSER (X with a settler selected): candidates from SettleScan, best first
-- ===========================================================================
local m_settleList:table;

-- Browsing moved the cursor over the candidates: back to the settler (not when the mode went stale).
local function SettleClosed( quiet:boolean )
	if quiet then return; end
	local unit:table = UI.GetHeadSelectedUnit();
	if unit ~= nil then SetCursor( unit:GetX(), unit:GetY(), false ); end
end

local function BuildSettleItems()
	return m_settleItems;
end

-- "2 tiles north-east, 1 turn, river, coast, silk, recommended" / "Here, river, wine"
local function SettleItemText( c:table )
	local text:string = c.here and "Here" or ( c.relative .. ", " .. Plural( c.turns, "turn", "turns" ) );
	text = text .. SettleReasons( c, 3, 2 );
	if c.recommended then text = text .. ", recommended"; end
	return text;
end

local function OpenSettleBrowser( unit:table )
	local scan:table = SettleScan_Scan( unit, true );		-- the player asked: look again, the map may have changed
	m_settleItems = {};
	for _, c in ipairs( scan.list ) do
		table.insert( m_settleItems, { key = c.key, text = SettleItemText( c ), detail = c.detail, candidate = c } );
	end
	if #m_settleItems == 0 then
		OutputMessageToScreenReader( "No spot to settle found nearby" .. ( ( scan.hereReason ~= nil and scan.hereReason ~= "" ) and ( ", here: " .. scan.hereReason ) or "" ) );
		return;
	end
	OpenMode( "settle", m_settleList, "Settle spots", SettleClosed );
end

-- Enter on a spot: the settler walks there (the same path as the move-to mode), or on the spot it stands on: B founds.
local function SettleGo( item:table )
	local unit:table = UI.GetHeadSelectedUnit();
	CloseMode( false, false );
	if not IsSettler( unit ) then
		SayResult( "No settler selected" );
		return;
	end
	local c:table = item.candidate;
	local plot:table = Map.GetPlotByIndex( c.plotIndex );
	local ok:boolean, extra = SettleScan_CanFound( unit, plot );
	if c.here or ( unit:GetX() == c.x and unit:GetY() == c.y ) then
		if not ok then
			SayResult( "Cannot settle here" .. ( ( extra ~= nil and extra ~= "" ) and ( ": " .. extra ) or "" ) );
		elseif extra == true then
			SayResult( "B to found next turn" );
		else
			SayResult( "B to found the city here" );
		end
		return;
	end
	if not ok then
		SayResult( "Cannot settle there any more" .. ( ( extra ~= nil and extra ~= "" ) and ( ": " .. extra ) or "" ) );
		return;
	end
	local war:table = WarTargets( unit, plot );
	local path:table = UnitManager.GetMoveToPathEx( unit, plot:GetIndex() );
	if war == nil and ( path == nil or path.plots == nil or #path.plots < 2 ) then
		SayResult( "Unreachable" );
		return;
	end
	IssueMoveOrder( unit, plot, war, false );
end

m_settleList = KeyNavList_Create{
	build		= BuildSettleItems,
	isActive	= function() return IsModeOpen( "settle" ); end,
	onActivate	= SettleGo,
	onClose		= function() CloseMode( true, false ); end,
	onFocus		= function( item ) SetCursor( item.candidate.x, item.candidate.y, false, nil, true ); end,
};

-- X: with a settler selected the spot browser, otherwise the scan for foreign units.
local function ScanKey()
	if not IsLocalPlayerActive() then return; end
	if IsModeOpen( "settle" ) then CloseMode( true, false ); return; end
	local unit:table = UI.GetHeadSelectedUnit();
	if IsSettler( unit ) and GetTargetMode() == nil then
		OpenSettleBrowser( unit );
		return;
	end
	ScanUnits( true );
end

-- ===========================================================================
--	PLACEMENT BROWSER: district and wonder placement by keyboard. The game enters DISTRICT_PLACEMENT / BUILDING_PLACEMENT
--	(ProductionPanel, Purchase tab); the candidate tiles come from PlacementScan. Up/Down browse (the cursor follows without
--	the real mouse), Shift+Arrows move the cursor freely ("valid, plus 2 Science" / "purchasable, 60 gold" / "can't place
--	here"), Enter (twice) places on the cursor tile, Space explains, Escape goes back / cancels.
--	Committing mirrors StrategicView_MapPlacement.ConfirmPlaceDistrict / ConfirmPlaceWonder (without their popup); the
--	game buys a tile in its own, separate step (PlotInfo.OnClickPurchasePlot), which Enter on a purchasable tile does too.
-- ===========================================================================
local m_placeList:table;

local function IsPlacementMode( mode:number )
	return mode == InterfaceModeTypes.DISTRICT_PLACEMENT or mode == InterfaceModeTypes.BUILDING_PLACEMENT;
end

-- "plus 3 Science, removes Woods and Deer, buy tile 60 gold" (the parts that apply, comma separated; empty when none).
local function PlacementEffects( c:table, withBuy:boolean )
	local parts:table = {};
	for _, text in ipairs( c.adjacency ) do table.insert( parts, text ); end
	if #c.removes > 0 then table.insert( parts, "removes " .. table.concat( c.removes, " and " ) ); end
	for _, text in ipairs( c.notes ) do table.insert( parts, text ); end
	if withBuy and not c.owned then table.insert( parts, "buy tile " .. c.tileCost .. " gold" ); end
	return table.concat( parts, ", " );
end

-- "2 tiles north-east, plus 3 Science, removes Woods, buy tile 60 gold"
local function PlacementItemText( c:table )
	local effects:string = PlacementEffects( c, true );
	if effects == "" then return c.relative; end
	return c.relative .. ", " .. effects;
end

-- What the cursor plot means for the item being placed (nil when no placement is going on).
PlacementPlotText = function( plot:table )
	local scan:table = m_placeScan;
	if scan == nil or not IsModeOpen( "placement" ) then return nil; end
	local c:table = scan.byIndex[ plot:GetIndex() ];
	if c == nil then
		local why:string = PlacementScan_Cannot( scan, plot );
		return "can't place here" .. ( why ~= "" and ( ": " .. why ) or "" );
	end
	local text:string;
	if c.owned then
		text = "valid";
	else
		text = "purchasable, " .. c.tileCost .. " gold";
	end
	local effects:string = PlacementEffects( c, false );
	if effects ~= "" then text = text .. ", " .. effects; end
	return text;
end

local function PlacementDetail( c:table )
	local text:string = m_placeScan.name .. " at " .. c.relative;
	if c.explanation ~= "" then
		text = text .. ". " .. c.explanation;
	elseif m_placeScan.kind == "district" then
		text = text .. ". No adjacency bonus";
	end
	if #c.removes > 0 then text = text .. ". Removes " .. table.concat( c.removes, " and " ); end
	for _, note in ipairs( c.notes ) do text = text .. ". " .. note; end
	if not c.owned then text = text .. ". You do not own this tile yet, buying it costs " .. c.tileCost .. " gold"; end
	local plot:table = Map.GetPlotByIndex( c.plotIndex );
	if plot ~= nil then text = text .. ". " .. PlotDescription_GetShort( plot, {} ); end
	return text;
end

local function BuildPlacementItems()
	local items:table = {};
	if m_placeScan == nil then return items; end
	for _, c in ipairs( m_placeScan.list ) do
		table.insert( items, { key = c.key, text = PlacementItemText( c ), candidate = c, detail = function() return PlacementDetail( c ); end } );
	end
	return items;
end

-- Puts the mode away: the cursor goes back to the city. A mode that went stale while the game is still placing leaves
-- the placement mode, or Enter and Escape would have nothing to act on.
local function PlacementClosed( quiet:boolean )
	m_placeScan = nil;
	m_placeConfirm = nil;
	m_placeBusy = false;
	-- not when the close is the mode being replaced by another placement mode: that one must stay
	if not m_placeReplaced and IsPlacementMode( UI.GetInterfaceMode() ) then UI.SetInterfaceMode( InterfaceModeTypes.SELECTION ); end
	local plot:table = GetSelectionPlot();
	if plot ~= nil then SetCursor( plot:GetX(), plot:GetY(), false, nil, true ); end
end

local function PlacementCancel()
	SayResult( "Placement cancelled" );
	UI.SetInterfaceMode( InterfaceModeTypes.SELECTION );		-- the mode change closes the browser; the game reopens the production panel
end

-- Escape: back from the confirmation first, then out of the placement.
local function PlacementEscape()
	if m_placeConfirm ~= nil then
		m_placeConfirm = nil;
		OutputMessageToScreenReader( "Back to the list" );
		return;
	end
	PlacementCancel();
end

-- Asks the engine again (a tile was bought, or the map changed).
local function PlacementRescan()
	local scan:table = m_placeScan;
	if scan == nil then return nil; end
	local city:table = UI.GetHeadSelectedCity();
	if city == nil then return nil; end
	m_placeScan = PlacementScan_Scan( city, scan.kind, scan.hash, scan.purchaseYield );
	return m_placeScan;
end

-- The production / purchase that followed the placement, said once the engine has applied it.
local function PlacementResult( scan:table, before:table, tries:number )
	-- the city captured at commit time: the game may already have selected the next unit (no selected city any more)
	local city:table = before.city;
	if city == nil or not IsLocalPlayerActive() then return; end
	-- the selection of the next unit may already have been spoken: do not cut it off, queue behind it
	local SayResult = function( text:string )
		m_lastResultTime = UI.GetElapsedTime();
		OutputMessageToScreenReader( text, m_lastSelectionSpeech > m_placeCommitTime );
	end
	if scan.purchaseYield ~= nil then
		local player:table = Players[ Game.GetLocalPlayer() ];
		local isGold:boolean = ( scan.purchaseYield == YieldTypes.GOLD );
		local balance:number = isGold and math.floor( player:GetTreasury():GetGoldBalance() ) or math.floor( player:GetReligion():GetFaithBalance() );
		if balance < before.balance then
			SayResult( "Bought " .. scan.name .. ", " .. balance .. ( isGold and " gold" or " faith" ) .. " left" );
			return;
		end
	else
		local queue:table = city:GetBuildQueue();
		local hash:number = queue:GetCurrentProductionTypeHash();
		if hash == scan.hash or queue:GetSize() > before.size then
			local text:string = ( hash == scan.hash and "Producing " or "Queued " ) .. scan.name;
			local turns:number = queue:GetTurnsLeft();
			if hash == scan.hash and turns ~= nil and turns > 0 then text = text .. ", " .. Plural( turns, "turn", "turns" ); end
			SayResult( text );
			return;
		end
	end
	if tries < 3 then
		After( 0.5, function() PlacementResult( scan, before, tries + 1 ); end );
	else
		SayResult( "Not placed. Tab to the production panel to check" );
	end
end

local function PlacementCommit( c:table )
	local scan:table = m_placeScan;
	local city:table = UI.GetHeadSelectedCity();
	local plot:table = Map.GetPlotByIndex( c.plotIndex );
	if scan == nil or city == nil or plot == nil then return; end
	local params:table = {};
	params[ CityOperationTypes.PARAM_X ] = plot:GetX();
	params[ CityOperationTypes.PARAM_Y ] = plot:GetY();
	local purchase:boolean = ( scan.purchaseYield ~= nil );
	if scan.kind == "district" then
		params[ CityOperationTypes.PARAM_DISTRICT_TYPE ] = scan.hash;
		params[ CityCommandTypes.PARAM_YIELD_TYPE ] = scan.purchaseYield;
	else
		params[ CityOperationTypes.PARAM_BUILDING_TYPE ] = scan.hash;
	end
	for key, value in pairs( m_placeParams or {} ) do params[ key ] = value; end		-- insert mode and queue position
	local can:boolean, results;
	if purchase then
		can, results = CityManager.CanStartCommand( city, CityCommandTypes.PURCHASE, params, true );
	else
		can, results = CityManager.CanStartOperation( city, CityOperationTypes.BUILD, params, true );
	end
	local player:table = Players[ Game.GetLocalPlayer() ];
	if not can then
		if purchase then
			local ok:boolean, cost:number = pcall( function() return city:GetGold():GetPurchaseCost( scan.purchaseYield, scan.hash ); end );
			local isGold:boolean = ( scan.purchaseYield == YieldTypes.GOLD );
			local balance:number = isGold and math.floor( player:GetTreasury():GetGoldBalance() ) or math.floor( player:GetReligion():GetFaithBalance() );
			if ok and cost ~= nil and cost > balance then
				SayResult( "Can't buy " .. scan.name .. ", need " .. ( cost - balance ) .. ( isGold and " more gold" or " more faith" ) );
				return;
			end
		end
		local reasons:table = {};
		if results ~= nil then
			for _, text in ipairs( results[ CityOperationResults.FAILURE_REASONS ] or results[ CityCommandResults.FAILURE_REASONS ] or {} ) do table.insert( reasons, CleanTextForSpeech( Locale.Lookup( text ) ) ); end
		end
		SayResult( "Can't place " .. scan.name .. " here any more" .. ( #reasons > 0 and ( ": " .. table.concat( reasons, ", " ) ) or "" ) );
		PlacementRescan();
		return;
	end
	local before:table = { size = city:GetBuildQueue():GetSize(), balance = 0, city = city };
	if purchase then
		before.balance = ( scan.purchaseYield == YieldTypes.GOLD ) and math.floor( player:GetTreasury():GetGoldBalance() ) or math.floor( player:GetReligion():GetFaithBalance() );
		CityManager.RequestCommand( city, CityCommandTypes.PURCHASE, params );
	else
		CityManager.RequestOperation( city, CityOperationTypes.BUILD, params );
	end
	m_lastKeyTime = UI.GetElapsedTime();
	m_placeCommitTime = m_lastKeyTime;
	LuaEvents.SRA_ExitPlacement( false );		-- WorldInput: leave the mode as the game does after placing (closes this mode)
	After( 0.3, function()		-- the hook may be missing or fail: never stay in the placement mode after a commit
		if IsPlacementMode( UI.GetInterfaceMode() ) then UI.SetInterfaceMode( InterfaceModeTypes.SELECTION ); end
	end );
	After( 0.4, function() PlacementResult( scan, before, 1 ); end );
end

local function PlacementBuyTile( c:table )
	local scan:table = m_placeScan;
	local city:table = UI.GetHeadSelectedCity();
	local plot:table = Map.GetPlotByIndex( c.plotIndex );
	if scan == nil or city == nil or plot == nil then return; end
	local player:table = Players[ Game.GetLocalPlayer() ];
	local gold:number = math.floor( player:GetTreasury():GetGoldBalance() );
	-- the engine's reasons that are not about ownership: then buying the tile would waste the gold
	local blockers:string = PlacementScan_Blockers( scan, plot );
	if blockers ~= "" then
		print( "InGameAccess: not buying tile " .. plot:GetX() .. "," .. plot:GetY() .. " for " .. scan.typeName .. ": " .. blockers );
		SayResult( "Not buying this tile, " .. scan.name .. " can't go there: " .. blockers );
		return;
	end
	local params:table = {};
	params[ CityCommandTypes.PARAM_PLOT_PURCHASE ] = UI.GetInterfaceModeParameter( CityCommandTypes.PARAM_PLOT_PURCHASE );
	params[ CityCommandTypes.PARAM_X ] = c.x;
	params[ CityCommandTypes.PARAM_Y ] = c.y;
	-- CanStartCommand does not look at the balance (verified: it says yes and the purchase then silently fails)
	if gold < c.tileCost then
		SayResult( "Can't buy this tile, need " .. ( c.tileCost - gold ) .. " more gold" );
		return;
	end
	if not CityManager.CanStartCommand( city, CityCommandTypes.PURCHASE, params ) then
		SayResult( "Can't buy this tile" );
		return;
	end
	local owner:number = plot:GetOwner();
	CityManager.RequestCommand( city, CityCommandTypes.PURCHASE, params );
	m_lastKeyTime = UI.GetElapsedTime();
	m_placeBusy = true;
	local function Report( tries:number )
		if not IsModeOpen( "placement" ) then m_placeBusy = false; return; end
		if plot:GetOwner() == owner then
			if tries < 2 then
				After( 1.0, function() Report( tries + 1 ); end );		-- the engine may not have applied the purchase yet
				return;
			end
			m_placeBusy = false;
			PlacementRescan();
			SayResult( "Tile not bought" .. ( gold < c.tileCost and ( ", need " .. ( c.tileCost - gold ) .. " more gold" ) or "" ) );
			return;
		end
		local fresh:table = PlacementRescan();
		m_placeBusy = false;
		if fresh == nil then return; end
		local c2:table = fresh.byIndex[ c.plotIndex ];
		if c2 ~= nil and c2.owned then
			local effects:string = PlacementEffects( c2, false );
			SayResult( "Tile bought for " .. c.tileCost .. " gold. Valid" .. ( effects ~= "" and ( ", " .. effects ) or "" ) .. ". Enter to place " .. fresh.name .. " here" );
		else
			local why:string = PlacementScan_Blockers( fresh, plot );
			if why == "" then why = PlacementScan_Cannot( fresh, plot ); end
			print( "InGameAccess: tile " .. plot:GetX() .. "," .. plot:GetY() .. " bought but refused for " .. fresh.typeName .. ": " .. why );
			SayResult( "Tile bought, but " .. fresh.name .. " can't go there" .. ( why ~= "" and ( ": " .. why ) or "" ) );
		end
	end
	After( 0.6, function() Report( 1 ); end );
end

-- Enter: the tile under the cursor (browsing puts the cursor on the listed tile; Shift+Arrows move it freely). The first
-- Enter asks, the second one does it.
local function PlacementEnter( item:table )
	local scan:table = m_placeScan;
	if scan == nil then return; end
	if m_placeBusy then SayResult( "Wait" ); return; end
	local x:number, y:number = GetCursor();
	local plot:table = Map.GetPlot( x, y );
	if plot == nil then return; end
	local c:table = scan.byIndex[ plot:GetIndex() ];
	if c == nil then
		local why:string = PlacementScan_Cannot( scan, plot );
		SayResult( "Can't place " .. scan.name .. " here" .. ( why ~= "" and ( ": " .. why ) or "" ) );
		return;
	end
	if m_placeConfirm == c.plotIndex then
		m_placeConfirm = nil;
		if c.owned then PlacementCommit( c ); else PlacementBuyTile( c ); end
		return;
	end
	m_placeConfirm = c.plotIndex;
	local effects:string = PlacementEffects( c, false );
	if c.owned then
		SayResult( "Place " .. scan.name .. " here?" .. ( effects ~= "" and ( " " .. effects .. "." ) or "" ) .. " Enter to confirm, Escape to go back" );
	else
		SayResult( "Buy this tile for " .. c.tileCost .. " gold?" .. ( effects ~= "" and ( " " .. effects .. "." ) or "" ) .. " Enter to confirm, then Enter again to place " .. scan.name .. ". Escape to go back" );
	end
end

m_placeList = KeyNavList_Create{
	build		= BuildPlacementItems,
	isActive	= function() return IsModeOpen( "placement" ); end,
	onActivate	= PlacementEnter,
	onClose		= PlacementEscape,
	onFocus		= function( item )
		m_placeConfirm = nil;
		SetCursor( item.candidate.x, item.candidate.y, false, nil, true );
	end,
};

-- The game entered DISTRICT_PLACEMENT / BUILDING_PLACEMENT: scan, open the mode, say what can be done.
OpenPlacement = function( mode:number )
	local city:table = UI.GetHeadSelectedCity();
	if city == nil or not IsLocalPlayerActive() then
		OutputMessageToScreenReader( "Placement: nothing to browse, Escape to cancel" );
		return;
	end
	local kind:string, hash:number;
	local purchaseYield:number = nil;
	if mode == InterfaceModeTypes.DISTRICT_PLACEMENT then
		kind = "district";
		hash = UI.GetInterfaceModeParameter( CityOperationTypes.PARAM_DISTRICT_TYPE );
		local yield:number = UI.GetInterfaceModeParameter( CityCommandTypes.PARAM_YIELD_TYPE );
		if yield ~= nil and ( yield == YieldTypes.GOLD or yield == YieldTypes.FAITH ) then purchaseYield = yield; end
	else
		kind = "wonder";
		hash = UI.GetInterfaceModeParameter( CityOperationTypes.PARAM_BUILDING_TYPE );
	end
	m_placeParams = {};		-- read now: leaving the mode forgets them
	for _, key in ipairs( { CityOperationTypes.PARAM_INSERT_MODE, CityOperationTypes.PARAM_QUEUE_LOCATION,
			CityOperationTypes.PARAM_QUEUE_SOURCE_LOCATION, CityOperationTypes.PARAM_QUEUE_DESTINATION_LOCATION } ) do
		m_placeParams[ key ] = UI.GetInterfaceModeParameter( key );
	end
	local scan:table = PlacementScan_Scan( city, kind, hash, purchaseYield );
	if scan.name == nil then
		OutputMessageToScreenReader( "Placement: nothing to browse, Escape to cancel" );
		return;
	end
	local function Leave()
		After( 0.1, function() if IsPlacementMode( UI.GetInterfaceMode() ) then UI.SetInterfaceMode( InterfaceModeTypes.SELECTION ); end end );
	end
	-- No owned tile can take it. The game still highlights tiles it could buy, so ask the engine why: either only the
	-- location is missing (a bought tile can help), or there is a real reason (population for another district, a
	-- missing building ...) and buying a tile would waste the gold.
	local ownedNone:boolean = ( scan.owned == 0 );
	if ownedNone then
		local why:table = PlacementScan_Explain( scan );
		if not why.canBuy and #why.reasons > 0 then
			OutputMessageToScreenReader( "Can't build " .. scan.name .. ": " .. table.concat( why.reasons, ", " ) );
			Leave();
			return;
		end
		if #scan.list == 0 then
			local text:string = "Can't build " .. scan.name .. ": no tile fits";
			if scan.blockedReason ~= nil then text = text .. ", " .. scan.blockedReason; end
			OutputMessageToScreenReader( text );
			Leave();
			return;
		end
	end
	if #scan.list == 0 then
		OutputMessageToScreenReader( "No valid tiles for " .. scan.name );
		Leave();
		return;
	end
	m_placeScan = scan;
	m_placeConfirm = nil;
	m_placeBusy = false;
	CloseMode( false, true );
	m_mode = { name = "placement", list = m_placeList, onClose = PlacementClosed };
	local best:table = scan.best;
	m_placeList.Open( "", best.key, true );
	SetCursor( best.x, best.y, false, nil, true );
	local text:string;
	if ownedNone then
		text = "No owned tile fits; " .. Plural( #scan.list, "tile", "tiles" ) .. " can be bought. Best: " .. PlacementItemText( best ) .. ".";
	else
		text = "Place " .. scan.name .. " for " .. scan.cityName .. ( purchaseYield ~= nil and ", bought with " .. ( purchaseYield == YieldTypes.GOLD and "gold" or "faith" ) or "" )
			.. ", " .. Plural( #scan.list, "tile", "tiles" ) .. ". Best: " .. PlacementItemText( best ) .. ".";
	end
	if scan.blocked > 0 and scan.blockedReason ~= nil then
		text = text .. " " .. Plural( scan.blocked, "tile", "tiles" ) .. " not offered: " .. scan.blockedReason .. ".";
	end
	OutputMessageToScreenReader( text );
end

-- ===========================================================================
--	UNIT ACTIONS MENU (Tab): the actions of the game's own unit panel (Panels/UnitPanel.lua)
-- ===========================================================================
local OPERATION_RESULTS = {
	UNITOPERATION_FORTIFY = "Fortified", UNITOPERATION_HEAL = "Fortified until healed", UNITOPERATION_SLEEP = "Sleeping",
	UNITOPERATION_ALERT = "On alert", UNITOPERATION_SKIP_TURN = "Turn skipped", UNITOPERATION_AUTOMATE_EXPLORE = "Exploring automatically",
	UNITOPERATION_REST_REPAIR = "Resting", UNITCOMMAND_WAKE = "Awake", UNITCOMMAND_CANCEL = "Orders cancelled",
};
-- Actions that announce their outcome in another way (events below, popups, target modes).
local RESULT_SILENT = {
	UNITOPERATION_FOUND_CITY = true, UNITOPERATION_BUILD_IMPROVEMENT = true, UNITCOMMAND_UPGRADE = true, PROMOTION = true,
	UNITOPERATION_MOVE_TO = true, UNITCOMMAND_PROMOTE = true,
};

local function OnUnitActionsReceived( unitId:number, list:table )
	m_unitActions = list or {};
end

-- Asks UnitPanel for the selected unit's actions (it answers at once with SRA_UnitActions). refresh: let the panel
-- refresh its state first; only done when the menu opens and when an action is run, not on every key.
local function FetchMenuItems( refresh:boolean )
	local items:table = {};
	if UI.GetHeadSelectedUnit() == nil then return items; end
	m_unitActions = {};
	LuaEvents.SRA_RequestUnitActions( refresh );
	for _, action in ipairs( m_unitActions ) do
		local text:string = action.name;
		if action.hotkey ~= nil and action.hotkey ~= "" then text = text .. ", key " .. action.hotkey; end
		if action.disabled then
			text = text .. ", unavailable" .. ( action.reason ~= "" and ( ": " .. action.reason ) or "" );
		end
		table.insert( items, {
			key = action.tag .. "|" .. action.name, text = text, detail = action.detail,
			choosable = not action.disabled, reason = ( action.reason ~= "" ) and action.reason or "Not available",
			action = action } );
	end
	return items;
end

local function BuildMenuItems()
	return m_menuItems;
end

local m_menu:table;

local function RunMenuItem( item:table )
	local unit:table = UI.GetHeadSelectedUnit();
	if unit == nil then return; end
	-- the state may have changed since the menu was opened: look the action up again, with a refresh
	local fresh:table = nil;
	for _, candidate in ipairs( FetchMenuItems( true ) ) do
		if candidate.key == item.key then fresh = candidate; end
	end
	if fresh == nil or fresh.choosable == false then
		CloseMode( false, false );
		SayResult( ( fresh ~= nil ) and fresh.reason or "No longer available" );
		return;
	end
	item = fresh;
	CloseMode( false, false );
	local modeBefore:number = UI.GetInterfaceMode();
	LuaEvents.SRA_RunUnitAction( item.action.id, unit:GetID() );
	-- Fortify, sleep ... speak their result from the game's UnitOperationStarted event (so the hotkeys are covered too);
	-- target modes, found city, building and the like announce themselves. Anything else: say what was chosen.
	if UI.GetInterfaceMode() == modeBefore and not RESULT_SILENT[ item.action.typeName ]
			and OPERATION_RESULTS[ item.action.typeName ] == nil then
		SayResult( item.action.name );
	end
end

local function ToggleUnitMenu()
	if not IsLocalPlayerActive() then return; end
	if IsModeOpen( "menu" ) then
		CloseMode( true, false );
		return;
	end
	local unit:table = UI.GetHeadSelectedUnit();
	if unit == nil then
		local city:table = UI.GetHeadSelectedCity();
		if city ~= nil and city:GetOwner() == Game.GetLocalPlayer() then
			-- A city has no action menu; Tab opens its production panel (Tab inside it switches Production / Purchase).
			CloseMode( false, true );
			LuaEvents.CityPanel_ProductionOpen();
		elseif city ~= nil then
			OutputMessageToScreenReader( "Not your city" );
		else
			OutputMessageToScreenReader( "No unit selected" );
		end
		return;
	end
	if unit:GetOwner() ~= Game.GetLocalPlayer() then
		OutputMessageToScreenReader( "Not your unit" );
		return;
	end
	if not CanOpenMode() then return; end
	m_menuItems = FetchMenuItems( true );
	if #m_menuItems == 0 then
		OutputMessageToScreenReader( Locale.Lookup( unit:GetName() ) .. " has no actions" );
		return;
	end
	OpenMode( "menu", m_menu, Locale.Lookup( unit:GetName() ) .. " actions" );
end

m_menu = KeyNavList_Create{
	build		= BuildMenuItems,
	isActive	= function() return IsModeOpen( "menu" ); end,
	onActivate	= RunMenuItem,
	onClose		= function() CloseMode( true, false ); end,
};

-- ===========================================================================
--	DIPLOMACY (V): the civilizations met so far; Enter opens the game's diplomacy screen with that leader
-- ===========================================================================
local m_civMenu:table;

local function BuildCivItems()
	local items:table = {};
	local localPlayer:number = Game.GetLocalPlayer();
	if not IsLocalPlayerActive() then return items; end
	local diplomacy:table = Players[ localPlayer ]:GetDiplomacy();
	for _, other in ipairs( PlayerManager.GetAliveMajors() ) do
		local id:number = other:GetID();
		if id ~= localPlayer and diplomacy:HasMet( id ) then
			local config:table = PlayerConfigurations[ id ];
			local state:string = diplomacy:IsAtWarWith( id ) and "at war" or "at peace";
			table.insert( items, {
				key = "civ:" .. id, civ = id,
				text = Locale.Lookup( config:GetLeaderName() ) .. ", " .. PlotDescription_GetCivName( id ) .. ", " .. state,
			} );
		end
	end
	return items;
end

m_civMenu = KeyNavList_Create{
	build		= BuildCivItems,
	isActive	= function() return IsModeOpen( "civ" ); end,
	onActivate	= function( item )
		CloseMode( false, false );
		LuaEvents.DiplomacyRibbon_OpenDiplomacyActionView( item.civ );
	end,
	onClose		= function() CloseMode( true, false ); end,
};

local function ToggleCivMenu()
	if not IsLocalPlayerActive() then return; end
	if IsModeOpen( "civ" ) then CloseMode( true, false ); return; end
	if not CanOpenMode() then return; end
	if #BuildCivItems() == 0 then
		OutputMessageToScreenReader( "You have not met any other civilization" );
		return;
	end
	OpenMode( "civ", m_civMenu, "Diplomacy, met civilizations" );
end

-- ===========================================================================
--	REGIONS: the top panel (Control+Y) and the notifications (Control+N) as lists
--	Up/Down (Left/Right in the top panel too) move and wrap, Home/End, Space reads details, Enter opens/activates,
--	Escape returns to the map. Control+Y / Control+N again closes.
-- ===========================================================================
local m_topList:table;
local m_notifList:table;

m_topList = KeyNavList_Create{
	build		= function() return TopPanelData_BuildItems(); end,
	isActive	= function() return IsModeOpen( "top" ); end,
	horizontal	= true,
	onActivate	= function( item )
		if item.open == "research" then
			CloseMode( false, false );
			LuaEvents.ActionPanel_OpenChooseResearch();
		elseif item.open == "civic" then
			CloseMode( false, false );
			LuaEvents.ActionPanel_OpenChooseCivic();
		else
			OutputMessageToScreenReader( "Nothing to open here. Space reads the details" );
		end
	end,
	onClose		= function() CloseMode( true, false ); end,
};

local function ToggleTopPanel()
	if IsModeOpen( "top" ) then CloseMode( true, false ); return; end
	if not CanOpenMode() then return; end
	OpenMode( "top", m_topList, "Top panel" );
end

-- Control+G: the basic yields in one sentence, without entering the region.
local function SpeakYields()
	if not IsLocalPlayerActive() then return; end
	OutputMessageToScreenReader( TopPanelData_Summary() );
end

-- Control+I: the city report region (yields, growth and housing, amenities, loyalty, defense, production, districts,
-- citizens, religion ...). Data: CityReportGather (the game's GetCityData), text: CityReportData. About the selected city,
-- else your city on the map cursor plot. The city is remembered by id, the items are rebuilt at every key.
local m_reportCity:table = nil;		-- { owner, id } of the city the open report is about
local m_reportList:table;

local function GetReportCity()
	if m_reportCity == nil then return nil; end
	local player:table = Players[ m_reportCity.owner ];
	if player == nil then return nil; end
	return player:GetCities():FindID( m_reportCity.id );
end


-- City management inside the report (Enter on the Focus, Tiles or Specialists item opens a sub-list; Escape goes back to the
-- report). The commands are the ones the game's mouse UI sends, replicated parameter for parameter (the originals live in
-- other contexts: PlotInfo.lua, CityPanel.lua), see the Request* functions. UNVERIFIED in game.
local MG:table = {};
MG.m_manageView = nil;		-- nil: the report itself; "focus", "tiles" or "specialists"
MG.m_manageConfirm = nil;		-- key of the buyable tile that waits for its second Enter
MG.m_manageBusy = false;		-- a request was sent and its result is not known yet

-- Mirrors PlotInfo.OnClickCitizen (Base/Assets/UI/WorldView/PlotInfo.lua:55-67): the click on a citizen button of a tile.
-- The game's click toggles work/lock on a tile and adds specialists to a district.
function MG.RequestCitizenClick( city:table, plot:table )
	local params:table = {};
	params[ CityCommandTypes.PARAM_MANAGE_CITIZEN ] = UI.GetInterfaceModeParameter( CityCommandTypes.PARAM_MANAGE_CITIZEN );
	params[ CityCommandTypes.PARAM_X ] = plot:GetX();
	params[ CityCommandTypes.PARAM_Y ] = plot:GetY();
	CityManager.RequestCommand( city, CityCommandTypes.MANAGE, params );
end

-- Mirrors PlotInfo.OnClickPurchasePlot (PlotInfo.lua:83-98). False when the engine refuses.
function MG.RequestPlotPurchase( city:table, plot:table )
	local params:table = {};
	params[ CityCommandTypes.PARAM_PLOT_PURCHASE ] = UI.GetInterfaceModeParameter( CityCommandTypes.PARAM_PLOT_PURCHASE );
	params[ CityCommandTypes.PARAM_X ] = plot:GetX();
	params[ CityCommandTypes.PARAM_Y ] = plot:GetY();
	if not CityManager.CanStartCommand( city, CityCommandTypes.PURCHASE, params ) then return false; end
	CityManager.RequestCommand( city, CityCommandTypes.PURCHASE, params );
	return true;
end

-- Mirror CityPanel.SetYieldFocus / SetYieldIgnore (Base/Assets/UI/Panels/CityPanel.lua:445-478), g_pCity = city.
function MG.RequestYieldFocus( city:table, yieldType:number )
	local citizens:table = city:GetCitizens();
	local params:table = {};
	params[ CityCommandTypes.PARAM_FLAGS ] = 0;				-- Set Favored
	params[ CityCommandTypes.PARAM_YIELD_TYPE ] = yieldType;
	if citizens:IsFavoredYield( yieldType ) then
		params[ CityCommandTypes.PARAM_DATA0 ] = 0;
	else
		if citizens:IsDisfavoredYield( yieldType ) then MG.RequestYieldIgnore( city, yieldType ); end
		params[ CityCommandTypes.PARAM_DATA0 ] = 1;
	end
	CityManager.RequestCommand( city, CityCommandTypes.SET_FOCUS, params );
end

MG.RequestYieldIgnore = function( city:table, yieldType:number )
	local citizens:table = city:GetCitizens();
	local params:table = {};
	params[ CityCommandTypes.PARAM_FLAGS ] = 1;				-- Set Ignored
	params[ CityCommandTypes.PARAM_YIELD_TYPE ] = yieldType;
	if citizens:IsDisfavoredYield( yieldType ) then
		params[ CityCommandTypes.PARAM_DATA0 ] = 0;
	else
		if citizens:IsFavoredYield( yieldType ) then MG.RequestYieldFocus( city, yieldType ); end
		params[ CityCommandTypes.PARAM_DATA0 ] = 1;
	end
	CityManager.RequestCommand( city, CityCommandTypes.SET_FOCUS, params );
end

function MG.ManageData()
	local city:table = GetReportCity();
	if city == nil then return nil, nil; end
	return CityManage_Gather( city ), city;
end

-- "Food plus 5, production 13" of the city as it is now
function MG.ManageTotals( city:table )
	local data:table = CityReport_Gather( city );
	if data == nil then return ""; end
	return CityManage_Totals( data );
end

-- After a request: waits until read() differs from before (the engine applies the command a moment later), then say( now ).
-- Gives up after 2 s with "Nothing changed".
function MG.ManageWatch( read, before:string, say )
	MG.m_manageBusy = true;
	m_lastKeyTime = UI.GetElapsedTime();
	local function Poll( tries:number )
		After( 0.4, function()
			if not IsModeOpen( "cityreport" ) then MG.m_manageBusy = false; return; end
			local ok:boolean, now = pcall( read );
			if ok and now ~= before then
				MG.m_manageBusy = false;
				local ok2:boolean, err = pcall( say, now );
				if not ok2 then print( "InGameAccess city management error: " .. tostring( err ) ); end
			elseif tries >= 5 then
				MG.m_manageBusy = false;
				print( "InGameAccess: the city management request changed nothing" );
				OutputMessageToScreenReader( "Nothing changed" );
			else
				Poll( tries + 1 );
			end
		end );
	end
	Poll( 1 );
end

function MG.FindByPlot( list:table, plotIndex:number )
	for _, entry in ipairs( list or {} ) do
		if entry.plotIndex == plotIndex then return entry; end
	end
	return nil;
end

function MG.EnterManageView( view:string )
	local city:table = GetReportCity();
	if city == nil then return; end
	MG.m_manageView = view;
	MG.m_manageConfirm = nil;
	MG.m_manageBusy = false;
	if view == "focus" then
		MG.m_focusList.Reset();
		MG.m_focusList.Open( "Focus" );
	elseif view == "tiles" then
		MG.m_tilesList.Reset();
		MG.m_tilesList.Open( "Tiles" );
	else
		MG.m_specList.Reset();
		MG.m_specList.Open( "Specialists" );
	end
end

function MG.LeaveManageView()
	local view:string = MG.m_manageView;
	MG.m_manageView = nil;
	MG.m_manageConfirm = nil;
	MG.m_manageBusy = false;
	MG.m_focusList.Reset();
	MG.m_tilesList.Reset();
	MG.m_specList.Reset();
	local city:table = GetReportCity();
	if city ~= nil and view ~= "focus" then SetCursor( city:GetX(), city:GetY(), false, nil, true ); end
	m_reportList.Focus( view );
end

function MG.CursorToPlotIndex( plotIndex:number )
	local plot:table = Map.GetPlotByIndex( plotIndex );
	if plot ~= nil then SetCursor( plot:GetX(), plot:GetY(), false, nil, true ); end
end

function MG.FocusState( city:table, yieldType:number )
	local citizens:table = city:GetCitizens();
	if citizens:IsFavoredYield( yieldType ) then return "favored"; end
	if citizens:IsDisfavoredYield( yieldType ) then return "ignored"; end
	return "normal";
end

function MG.FocusEnter( item:table )
	if MG.m_manageBusy then OutputMessageToScreenReader( "Wait" ); return; end
	local city:table = GetReportCity();
	if city == nil then return; end
	local f:table = item.yield;
	local name:string = string.lower( f.name );
	local before:string = MG.FocusState( city, f.yieldType );
	if item.ignore then MG.RequestYieldIgnore( city, f.yieldType ); else MG.RequestYieldFocus( city, f.yieldType ); end
	MG.ManageWatch( function() return MG.FocusState( city, f.yieldType ); end, before, function( now )
		local text:string;
		if now == "favored" then
			text = f.name .. " focus on";
		elseif now == "ignored" then
			text = "Ignoring " .. name;
		elseif item.ignore then
			text = "No longer ignoring " .. name;
		else
			text = f.name .. " focus off";
		end
		OutputMessageToScreenReader( text .. ". " .. MG.ManageTotals( city ) );
	end );
end

function MG.TilesEnter( item:table )
	if MG.m_manageBusy then OutputMessageToScreenReader( "Wait" ); return; end
	local city:table = GetReportCity();
	local t:table = item.tile;
	local plot:table = Map.GetPlotByIndex( t.plotIndex );
	if city == nil or plot == nil then return; end
	if t.cost ~= nil then
		local gold:number = math.floor( Players[ Game.GetLocalPlayer() ]:GetTreasury():GetGoldBalance() );
		-- CanStartCommand does not look at the balance (docs/engine-notes.md)
		if gold < t.cost then
			MG.m_manageConfirm = nil;
			OutputMessageToScreenReader( "Can't buy this tile, need " .. ( t.cost - gold ) .. " more gold" );
			return;
		end
		if MG.m_manageConfirm ~= t.key then
			MG.m_manageConfirm = t.key;
			OutputMessageToScreenReader( "Buy this tile for " .. t.cost .. " gold? Enter to confirm, Escape to go back" );
			return;
		end
		MG.m_manageConfirm = nil;
		if not MG.RequestPlotPurchase( city, plot ) then
			OutputMessageToScreenReader( "Can't buy this tile" );
			return;
		end
		MG.ManageWatch( function() return tostring( plot:GetOwner() ); end, tostring( plot:GetOwner() ), function()
			MG.m_tilesList.Focus( "t" .. t.plotIndex, "Bought for " .. t.cost .. " gold" );
		end );
		return;
	end
	local function Sig()
		local m:table = MG.ManageData();
		local now:table = m ~= nil and MG.FindByPlot( m.tiles, t.plotIndex ) or nil;
		if now == nil then return "gone"; end
		return now.count .. ":" .. tostring( now.locked );
	end
	local before:string = Sig();
	MG.RequestCitizenClick( city, plot );
	MG.ManageWatch( Sig, before, function()
		local m:table = MG.ManageData();
		local now:table = m ~= nil and MG.FindByPlot( m.tiles, t.plotIndex ) or nil;
		local state:string = ( now ~= nil ) and CityManage_TileState( now ) or "Changed";
		OutputMessageToScreenReader( state .. ". " .. MG.ManageTotals( city ) );
	end );
end

function MG.SpecialistsEnter( item:table )
	if MG.m_manageBusy then OutputMessageToScreenReader( "Wait" ); return; end
	local city:table = GetReportCity();
	local dist:table = item.district;
	local plot:table = Map.GetPlotByIndex( dist.plotIndex );
	if city == nil or plot == nil then return; end
	local function Count()
		local m:table = MG.ManageData();
		local now:table = m ~= nil and MG.FindByPlot( m.districts, dist.plotIndex ) or nil;
		return now ~= nil and tostring( now.count ) or "gone";
	end
	local before:string = Count();
	MG.RequestCitizenClick( city, plot );
	MG.ManageWatch( Count, before, function()
		local m:table = MG.ManageData();
		local now:table = m ~= nil and MG.FindByPlot( m.districts, dist.plotIndex ) or nil;
		if now == nil then return; end
		OutputMessageToScreenReader( CityManage_DistrictText( now ) .. ". " .. MG.ManageTotals( city ) );
	end );
end

-- Backspace / Delete: one specialist less. The game has no "remove one" click (a click adds, and past the last slot the
-- district empties), so this clicks until the count has dropped by one (at most as many clicks as slots plus one).
function MG.SpecialistsRemove()
	if MG.m_manageBusy then OutputMessageToScreenReader( "Wait" ); return; end
	local m:table, city:table = MG.ManageData();
	if m == nil then return; end
	local focusKey = MG.m_specList.GetFocusKey();
	local dist:table = nil;
	for _, candidate in ipairs( m.districts ) do
		if candidate.key == focusKey then dist = candidate; end
	end
	if dist == nil then return; end
	if dist.count == 0 then
		OutputMessageToScreenReader( dist.name .. " has no specialists to remove" );
		return;
	end
	local plot:table = Map.GetPlotByIndex( dist.plotIndex );
	local goal:number = dist.count - 1;
	local clicks:number = 0;
	local function Count()
		local fresh:table = MG.ManageData();
		local now:table = fresh ~= nil and MG.FindByPlot( fresh.districts, dist.plotIndex ) or nil;
		return now ~= nil and tostring( now.count ) or "gone";
	end
	local function Say()
		local fresh:table = MG.ManageData();
		local now:table = fresh ~= nil and MG.FindByPlot( fresh.districts, dist.plotIndex ) or nil;
		if now == nil then return; end
		OutputMessageToScreenReader( CityManage_DistrictText( now ) .. ". " .. MG.ManageTotals( city ) );
	end
	local function Step()
		clicks = clicks + 1;
		local before:string = Count();
		MG.RequestCitizenClick( city, plot );
		MG.ManageWatch( Count, before, function( now )
			if tonumber( now ) == goal or clicks > dist.max then Say(); else Step(); end
		end );
	end
	Step();
end

m_reportList = KeyNavList_Create{
	build		= function()
		local city:table = GetReportCity();
		if city == nil then return {}; end
		local data:table = CityReport_Gather( city );
		if data == nil then return {}; end
		return CityReport_BuildItems( data );
	end,
	isActive	= function() return IsModeOpen( "cityreport" ) and MG.m_manageView == nil; end,
	onActivate	= function( item )
		if item.manage ~= nil then MG.EnterManageView( item.manage ); return; end
		OutputMessageToScreenReader( "Nothing to open here. Space reads the details" );
	end,
	onClose		= function() CloseMode( true, false ); end,
};

MG.m_focusList = KeyNavList_Create{
	build		= function()
		local m:table = MG.ManageData();
		if m == nil then return {}; end
		return CityManage_FocusItems( m );
	end,
	isActive	= function() return IsModeOpen( "cityreport" ) and MG.m_manageView == "focus"; end,
	onActivate	= MG.FocusEnter,
	onClose		= MG.LeaveManageView,
};

MG.m_tilesList = KeyNavList_Create{
	build		= function()
		local m:table = MG.ManageData();
		if m == nil then return {}; end
		local items:table = CityManage_TileItems( m );
		for _, item in ipairs( items ) do
			local plotIndex:number = item.tile.plotIndex;
			item.detail = function()
				local plot:table = Map.GetPlotByIndex( plotIndex );
				if plot == nil then return nil; end
				return PlotDescription_GetDetailed( plot, {} );
			end;
		end
		return items;
	end,
	isActive	= function() return IsModeOpen( "cityreport" ) and MG.m_manageView == "tiles"; end,
	onActivate	= MG.TilesEnter,
	onClose		= MG.LeaveManageView,
	onFocus		= function( item )
		MG.m_manageConfirm = nil;
		MG.CursorToPlotIndex( item.tile.plotIndex );
	end,
};

MG.m_specList = KeyNavList_Create{
	build		= function()
		local m:table = MG.ManageData();
		if m == nil then return {}; end
		local items:table = CityManage_DistrictItems( m );
		for _, item in ipairs( items ) do
			item.detail = item.text .. ". Enter adds a specialist, Backspace removes one";
		end
		return items;
	end,
	isActive	= function() return IsModeOpen( "cityreport" ) and MG.m_manageView == "specialists"; end,
	onActivate	= MG.SpecialistsEnter,
	onClose		= MG.LeaveManageView,
	onFocus		= function( item ) MG.CursorToPlotIndex( item.district.plotIndex ); end,
	extraKeys	= { [Keys.VK_BACK] = MG.SpecialistsRemove, [Keys.VK_DELETE] = MG.SpecialistsRemove },
};

-- What the mode holds: the report list and its sub-lists (each handles keys only while it is the active view).
MG.m_reportFacade = {
	Open		= function( title:string ) MG.m_manageView = nil; m_reportList.Open( title ); end,
	Reset		= function()
		MG.m_manageView = nil;
		MG.m_manageConfirm = nil;
		MG.m_manageBusy = false;
		m_reportList.Reset();
		MG.m_focusList.Reset();
		MG.m_tilesList.Reset();
		MG.m_specList.Reset();
	end,
	HandleInput	= function( input:table )
		return m_reportList.HandleInput( input ) or MG.m_focusList.HandleInput( input ) or MG.m_tilesList.HandleInput( input ) or MG.m_specList.HandleInput( input );
	end,
};

local function ToggleCityReport()
	if IsModeOpen( "cityreport" ) then CloseMode( true, false ); return; end
	if not CanOpenMode() then return; end
	if not m_cityReportLoaded or CityReport_Gather == nil or CityReport_BuildItems == nil then
		OutputMessageToScreenReader( "The city report is not available" );
		return;
	end
	local localPlayer:number = Game.GetLocalPlayer();
	local city:table = UI.GetHeadSelectedCity();
	if city == nil or city:GetOwner() ~= localPlayer then
		city = nil;
		local x:number, y:number = GetCursor();
		local atCursor:table = Cities.GetCityInPlot( x, y );
		if atCursor ~= nil and atCursor:GetOwner() == localPlayer then city = atCursor; end
	end
	if city == nil then
		OutputMessageToScreenReader( "No city selected. Backslash selects the capital" );
		return;
	end
	m_reportCity = { owner = city:GetOwner(), id = city:GetID() };
	OpenMode( "cityreport", MG.m_reportFacade, Locale.Lookup( city:GetName() ) .. " report", function() m_reportCity = nil; end );
end

local function OnNotificationsReceived( list:table )
	m_notifData = list or {};
	m_notifAnswered = true;
end

-- Active notifications, newest first (ids grow with time). Rebuilt from the panel's own list at key time.
local function BuildNotificationItems()
	m_notifData = {};
	m_notifAnswered = false;
	LuaEvents.SRA_RequestNotifications();
	table.sort( m_notifData, function( a, b ) return a.id > b.id; end );
	local items:table = {};
	for _, n in ipairs( m_notifData ) do
		local title:string = CleanTextForSpeech( n.message );
		local summary:string = CleanTextForSpeech( n.summary );
		local detail:string = title;
		if summary ~= "" and summary ~= title then detail = detail .. ". " .. summary; end
		detail = string.gsub( detail, "[%.%s]+$", "" );
		if n.blocking then detail = detail .. ". Blocks ending the turn"; end
		if not n.dismissable then detail = detail .. ". Can't be dismissed"; end
		table.insert( items, {
			key = "n:" .. n.id, text = title, detail = detail, note = n,
			choosable = n.activatable, reason = "Can't activate this now",
		} );
	end
	return items;
end

-- Enter: what a click on the notification does (the panel's own Activate: look at the plot, select the unit,
-- open the chooser or screen). When nothing was selected or opened, the cursor goes to its plot and says it.
local m_activateReply		:table = nil;		-- answer of the panel to the last SRA_ActivateNotification: { found, lookOnly }

local function OnNotificationActivated( id:number, found:boolean, lookOnly:boolean )
	m_activateReply = { id = id, found = found, lookOnly = lookOnly };
end

local function ActivateNotification( item:table )
	local n:table = item.note;
	CloseMode( false, false );
	local started:number = UI.GetElapsedTime();
	m_activateReply = nil;
	LuaEvents.SRA_ActivateNotification( n.id );		-- answered synchronously through SRA_NotificationActivated
	local reply:table = m_activateReply;
	if reply ~= nil and reply.id == n.id and not reply.found then
		OutputMessageToScreenReader( "Notification no longer available" );
		return;
	end
	local lookOnly:boolean = ( reply ~= nil and reply.lookOnly );
	local player:number = Game.GetLocalPlayer();
	local turn:number = Game.GetCurrentGameTurn();
	After( 0.5, function()
		if m_lastSelectionSpeech >= started or m_mode ~= nil then return; end		-- a selection or screen spoke for itself
		-- the world may have moved on in half a second (turn change, hotseat, a popup or a target mode opened)
		if Game.GetLocalPlayer() ~= player or Game.GetCurrentGameTurn() ~= turn or not IsLocalPlayerActive() then return; end
		if not Players[ player ]:IsTurnActive() or UI.GetInterfaceMode() ~= InterfaceModeTypes.SELECTION then return; end
		if IsGamePopupOpen() then return; end
		if n.x >= 0 and n.y >= 0 then
			SetCursor( n.x, n.y, true, false );
		elseif lookOnly then
			local title:string = CleanTextForSpeech( n.message );
			local summary:string = CleanTextForSpeech( n.summary );
			local text:string = title;
			if summary ~= "" and summary ~= title then text = text .. ". " .. summary; end
			text = string.gsub( text, "[%.%s]+$", "" );
			local gone:boolean = true;
			for _, other in ipairs( BuildNotificationItems() ) do
				if other.note.id == n.id then gone = false; end
			end
			if gone then text = text .. ". Dismissed"; end
			OutputMessageToScreenReader( text );
		end
	end );
end

local function DismissNotification()
	local items:table = BuildNotificationItems();
	local focus = m_notifList.GetFocusKey();
	local index:number = nil;
	for i, item in ipairs( items ) do
		if item.key == focus then index = i; end
	end
	if index == nil then
		OutputMessageToScreenReader( "Nothing selected" );
		return;
	end
	local item:table = items[ index ];
	if not item.note.dismissable then
		OutputMessageToScreenReader( "Can't dismiss this one" );
		return;
	end
	local neighbor = ( items[ index + 1 ] or items[ index - 1 ] );
	local neighborKey = ( neighbor ~= nil ) and neighbor.key or nil;
	LuaEvents.SRA_DismissNotification( item.note.id );
	After( 0.3, function()
		if not IsModeOpen( "notifications" ) then return; end
		local rest:table = BuildNotificationItems();
		if #rest == 0 then
			CloseMode( false, false );
			OutputMessageToScreenReader( "Dismissed. No more notifications" );
			return;
		end
		for _, other in ipairs( rest ) do
			if other.key == item.key then
				OutputMessageToScreenReader( "Could not dismiss" );
				return;
			end
		end
		m_notifList.Focus( neighborKey, "Dismissed" );
	end );
end

m_notifList = KeyNavList_Create{
	build		= BuildNotificationItems,
	isActive	= function() return IsModeOpen( "notifications" ); end,
	onActivate	= ActivateNotification,
	onClose		= function() CloseMode( true, false ); end,
	extraKeys	= { [Keys.VK_DELETE] = DismissNotification },
};

local function ToggleNotifications()
	if IsModeOpen( "notifications" ) then CloseMode( true, false ); return; end
	if not CanOpenMode() then return; end
	if #BuildNotificationItems() == 0 then
		OutputMessageToScreenReader( m_notifAnswered and "No notifications" or "Notifications are not available" );
		return;
	end
	OpenMode( "notifications", m_notifList, "Notifications" );
end

-- New notifications are announced when they arrive, without interrupting; a burst (turn start) becomes one sentence.
-- "Barbarians sighted" is left out only when the hub itself said "X spotted ..." for a hostile unit around that time
-- (the notification also covers sightings farther than 4 tiles from our cities and units, and the spotting is capped).
local m_lastSpotSpeech		:number = -100;		-- UI.GetElapsedTime() of the last "X spotted" announcement

local function OnNotificationAdded( id:number, message:string, summary:string, typeName:string, blocking:boolean )
	if not m_ready then return; end
	local text:string = CleanTextForSpeech( message );
	if text == "" then text = CleanTextForSpeech( summary ); end
	if text == "" then return; end
	table.insert( m_arrivals, { text = text, time = UI.GetElapsedTime(), spotType = ( typeName == "NOTIFICATION_BARBARIANS_SIGHTED" ) } );
	if m_arrivalTimer < 0 then m_arrivalTimer = 0.8; end		-- flush 0.8 s after the first one: a trickle must not postpone the burst
end

local function FlushArrivals()
	local entries:table = m_arrivals;
	m_arrivals = {};
	local texts:table = {};
	for _, entry in ipairs( entries ) do
		if not ( entry.spotType and math.abs( m_lastSpotSpeech - entry.time ) < 3 ) then table.insert( texts, entry.text ); end
	end
	if #texts == 0 then return; end
	if #texts == 1 then
		OutputMessageToScreenReader( "Notification: " .. texts[1], true );
	else
		OutputMessageToScreenReader( #texts .. " new notifications: " .. KeyNavList_ShortList( texts, 3 ), true );
	end
end

-- ===========================================================================
--	RESULTS of the player's orders and what happens around the player's units
-- ===========================================================================
local function OnUnitOperationStarted( ownerID:number, unitID:number, operationID:number )
	if ownerID ~= Game.GetLocalPlayer() or not m_ready then return; end
	local row:table = GameInfo.UnitOperations[ operationID ];
	if row == nil then return; end
	local text:string = OPERATION_RESULTS[ row.OperationType ];
	if text ~= nil then SayResult( text ); end
end

-- Automate Exploration starts no operation event (UnitOperationStarted); the game only adds the operation.
local function OnUnitOperationAdded( ownerID:number, unitID:number, hOperation:number, operationIndex:number )
	if ownerID ~= Game.GetLocalPlayer() or not m_ready then return; end
	local row:table = GameInfo.UnitOperations[ operationIndex ];
	if row ~= nil and row.OperationType == "UNITOPERATION_HEAL" then
		-- Fortify Until Healed only adds the operation (no UnitOperationStarted, like Automate Exploration)
		if UI.GetElapsedTime() - m_lastKeyTime <= 2.0 then SayResult( OPERATION_RESULTS.UNITOPERATION_HEAL ); end
		return;
	end
	if row == nil or row.OperationType ~= "UNITOPERATION_AUTOMATE_EXPLORE" then return; end
	-- The game also re-adds the operation of units that are already exploring (every turn, after a load): only the
	-- order the player just gave is told. (The old "it has not moved" check after 1 s was dropped: unreliable.)
	if UI.GetElapsedTime() - m_lastKeyTime > 2.0 then return; end
	SayResult( OPERATION_RESULTS.UNITOPERATION_AUTOMATE_EXPLORE );
end

local function OnUnitCommandStarted( ownerID:number, unitID:number, commandID:number )
	if ownerID ~= Game.GetLocalPlayer() or not m_ready then return; end
	local row:table = GameInfo.UnitCommands[ commandID ];
	if row == nil then return; end
	local text:string = OPERATION_RESULTS[ row.CommandType ];
	if text ~= nil then SayResult( text ); end
end

-- The trade choosers hide their contexts (and so stop their update loops) when they close; they ask the hub to tell the
-- outcome a moment later. kind "route": a trade route was requested (unit, origin city owner and id, destination name);
-- kind "move": a trader was moved to another city (unit, plot it left, city name).
local function OnTradeResult( kind:string, unitID:number, a, b, c, d )
	local owner:number = Game.GetLocalPlayer();
	if kind == "route" then
		After( 1.0, function()
			local origin:table = CityManager.GetCity( a, b );
			local started:boolean = false;
			if origin ~= nil then
				for _, route in ipairs( origin:GetTrade():GetOutgoingRoutes() ) do
					if route.TraderUnitID == unitID then started = true; end
				end
			end
			if started then
				SayResult( "Trade route to " .. c .. " started" );
			else
				SayResult( "Trade route to " .. c .. " requested, but the trader has no route yet" );
			end
		end );
	elseif kind == "move" then
		After( 0.5, function()
			local unit:table = Players[ owner ]:GetUnits():FindID( unitID );
			if unit ~= nil and ( unit:GetX() ~= a or unit:GetY() ~= b ) then
				SayResult( "Trader moved to " .. c );
			else
				SayResult( "Trader not moved" );
			end
		end );
	end
end

local function MovesText( unit:table )
	return FormatNumber( unit:GetMovesRemaining() ) .. " of " .. FormatNumber( unit:GetMaxMoves() ) .. " moves";
end

-- A move ordered with Enter in the move-to mode: arrived, still on the way, or stopped short.
local function OnUnitMoveComplete( playerID:number, unitID:number, x:number, y:number )
	if playerID ~= Game.GetLocalPlayer() then return; end
	local record:table = m_movers[ unitID ];
	if record == nil then return; end
	local unit:table = Players[ playerID ]:GetUnits():FindID( unitID );
	if unit == nil then
		m_movers[ unitID ] = nil;
		return;
	end
	local plot:table = Map.GetPlot( x, y );
	if plot ~= nil and plot:GetIndex() == record.dest then
		m_movers[ unitID ] = nil;
		local text:string = "Arrived, " .. MovesText( unit );
		if IsSettler( unit ) then
			local ok:boolean, extra = SettleScan_CanFound( unit, plot );
			if not ok then
				text = text .. ", " .. SettleScan_CannotText( extra );
			elseif extra ~= true then
				text = text .. ", B to found the city";
			else
				text = text .. ", can settle, B to found next turn";
			end
		end
		SayResult( text );
		return;
	end
	local queued = UnitManager.GetQueuedDestination( unit );
	if queued == nil then
		m_movers[ unitID ] = nil;
		local destPlot:table = Map.GetPlotByIndex( record.dest );
		local text:string = "Stopped";
		if destPlot ~= nil and plot ~= nil then
			text = text .. ", " .. Plural( Map.GetPlotDistance( x, y, destPlot:GetX(), destPlot:GetY() ), "tile", "tiles" ) .. " from the destination";
		end
		SayResult( text );
		return;
	end
	-- still on the way: only said right after the order (not again every turn of a long move)
	if UI.GetElapsedTime() - ( record.issued or -100 ) > 3 then return; end
	local path:table = UnitManager.GetMoveToPathEx( unit, queued );
	local text:string = "Moving";
	if path ~= nil and path.turns ~= nil and #path.turns > 0 then
		text = text .. ", " .. Plural( path.turns[ #path.turns ], "turn", "turns" ) .. " left";
	end
	SayResult( text );
end

-- Who fights whom: the game announces a fight (CombatVisBegin) just before the damage events of both sides.
local m_combat:table = nil;

-- Spoken name of one side of a fight (unit or city).
function H.CombatSide( data:table )
	if data == nil or data.playerID == nil or data.playerID < 0 or Players[ data.playerID ] == nil then return nil; end
	local player:table = Players[ data.playerID ];
	local side:table = { player = data.playerID, id = data.componentID };
	if data.componentType == ComponentType.UNIT then
		local unit:table = player:GetUnits():FindID( data.componentID );
		if unit == nil then return nil; end
		side.name = PlotDescription_GetUnitName( unit );
		side.short = Locale.Lookup( unit:GetName() );
		side.x, side.y = unit:GetX(), unit:GetY();
		-- never name a unit the player cannot see (or an unmet civ behind it)
		if data.playerID ~= Game.GetLocalPlayer() and not ( IsPlotVisibleToLocal( Map.GetPlot( side.x, side.y ) ) and PlotDescription_IsUnitVisible( unit ) ) then
			side.name, side.short, side.unseen = "An unseen unit", "The unseen unit", true;
		end
	else
		local city:table = nil;
		if data.componentType == ComponentType.DISTRICT then
			local district:table = player:GetDistricts():FindID( data.componentID );
			if district == nil then return nil; end
			city = district:GetCity();
			if city == nil then return nil; end
			side.x, side.y = district:GetX(), district:GetY();
		elseif data.componentType == ComponentType.CITY then
			city = player:GetCities():FindID( data.componentID );
			if city == nil then return nil; end
			side.x, side.y = city:GetX(), city:GetY();
		else
			return nil;
		end
		side.name = Locale.Lookup( city:GetName() );
		side.short = side.name;
	end
	if data.playerID == Game.GetLocalPlayer() and not side.unseen then side.name = "Your " .. side.name; end
	return side;
end

function H.OnCombatVisBegin( data:table )
	m_combat = nil;
	if not m_ready or data == nil then return; end
	local attacker:table, defender:table = H.CombatSide( data[ CombatVisType.ATTACKER ] ), H.CombatSide( data[ CombatVisType.DEFENDER ] );
	if attacker == nil or defender == nil then return; end
	m_combat = { attacker = attacker, defender = defender, time = UI.GetElapsedTime(), told = false };
end

-- "3 tiles north-east of Rome": where a plot is, seen from the nearest own city (else the selected unit).
function H.PlaceFromOwn( x:number, y:number )
	local localPlayer:number = Game.GetLocalPlayer();
	local bestDistance:number, bestName:string, bestPlot:table = 99, nil, nil;
	for _, city in Players[ localPlayer ]:GetCities():Members() do
		local distance:number = Map.GetPlotDistance( x, y, city:GetX(), city:GetY() );
		if distance < bestDistance then
			bestDistance, bestName, bestPlot = distance, Locale.Lookup( city:GetName() ), Map.GetPlot( city:GetX(), city:GetY() );
		end
	end
	if bestName == nil then
		local selected:table = UI.GetHeadSelectedUnit();
		if selected ~= nil and selected:GetOwner() == localPlayer then
			bestName, bestPlot = "your " .. Locale.Lookup( selected:GetName() ), Map.GetPlot( selected:GetX(), selected:GetY() );
		end
	end
	if bestName == nil then return nil; end
	local relative:string = PlotDescription_GetRelative( bestPlot, Map.GetPlot( x, y ) );
	if relative == nil then return "at " .. bestName; end
	return relative .. " of " .. bestName;
end

function H.OnUnitDamageChanged( playerID:number, unitID:number, newDamage:number, oldDamage:number )
	if not m_ready or newDamage <= oldDamage then return; end
	local player:table = Players[ playerID ];
	if player == nil then return; end
	local unit:table = player:GetUnits():FindID( unitID );
	if unit == nil then return; end
	if not IsPlotVisibleToLocal( Map.GetPlot( unit:GetX(), unit:GetY() ) ) or not PlotDescription_IsUnitVisible( unit ) then return; end
	RememberUnit( unit );
	-- only fights that concern the player: their own units, or anything close to their units and cities
	if playerID ~= Game.GetLocalPlayer() and not IsNearLocal( unit:GetX(), unit:GetY(), 3 ) then return; end
	local name:string = PlotDescription_GetUnitName( unit );
	if playerID == Game.GetLocalPlayer() then name = "Your " .. name; end
	local maxDamage:number = unit:GetMaxDamage();
	if newDamage >= maxDamage then return; end		-- H.OnUnitKilledInCombat tells it
	local text:string = name .. " takes " .. ( newDamage - oldDamage ) .. " damage, " .. ( maxDamage - newDamage ) .. " of " .. maxDamage .. " left";
	-- the first damage line of a fight says who attacked whom (and where, when it is not our fight)
	local fight:table = m_combat;
	if fight ~= nil and not fight.told and UI.GetElapsedTime() - fight.time < 10
			and ( ( fight.attacker.player == playerID and fight.attacker.id == unitID ) or ( fight.defender.player == playerID and fight.defender.id == unitID ) ) then
		fight.told = true;
		local localPlayer:number = Game.GetLocalPlayer();
		local ours:boolean = fight.attacker.player == localPlayer or fight.defender.player == localPlayer;
		local victim:table = ( fight.defender.player == playerID and fight.defender.id == unitID ) and fight.defender or fight.attacker;
		local who:string = ( victim.player == localPlayer ) and victim.name or victim.short;
		local place:string = nil;
		if not ours then place = H.PlaceFromOwn( fight.defender.x, fight.defender.y ); end
		text = fight.attacker.name .. " attacks " .. fight.defender.name .. ( place ~= nil and ( ", " .. place ) or "" ) .. ": "
			.. who .. " takes " .. ( newDamage - oldDamage ) .. " damage, " .. ( maxDamage - newDamage ) .. " of " .. maxDamage .. " left";
	end
	OutputMessageToScreenReader( text, true );
	LuaEvents.SRA_CombatSpoken();		-- StatusMessagePanel drops its duplicate of this fight
end

-- (killed player, killed unit, killer player, killer unit): told when the local player is on either side.
function H.OnUnitKilledInCombat( killedPlayer:number, killedId:number, killerPlayer:number, killerId:number )
	if not m_ready then return; end
	local localPlayer:number = Game.GetLocalPlayer();
	if killedPlayer ~= localPlayer and killerPlayer ~= localPlayer then return; end
	local function NameOf( playerID:number, unitID:number )
		local player:table = Players[ playerID ];
		local unit:table = ( player ~= nil ) and player:GetUnits():FindID( unitID ) or nil;
		if unit ~= nil then return PlotDescription_GetUnitName( unit ); end
		-- the unit is gone by now: the name remembered while it was alive
		return m_unitNames[ playerID .. ":" .. unitID ];
	end
	local killed:string = NameOf( killedPlayer, killedId ) or "unit";
	local killer:string = NameOf( killerPlayer, killerId );
	local text:string;
	if killedPlayer == localPlayer then
		text = "Your " .. killed .. " was killed";
	else
		text = killed .. " killed";
	end
	if killer ~= nil then
		if killerPlayer == localPlayer then killer = "your " .. killer; end
		text = text .. " by " .. killer;
	end
	OutputMessageToScreenReader( text, true );
	LuaEvents.SRA_CombatSpoken();		-- StatusMessagePanel drops its duplicate of this fight
end

function H.OnCityAddedToMap( ownerID:number, cityID:number, x:number, y:number )
	if ownerID ~= Game.GetLocalPlayer() or not m_ready then return; end
	local city:table = Players[ ownerID ]:GetCities():FindID( cityID );
	local name:string = ( city ~= nil ) and Locale.Lookup( city:GetName() ) or "City";
	SayResult( name .. " founded" );
end

-- A builder finished an improvement on its own plot.
function H.OnImprovementAddedToMap( x:number, y:number, improvementType:number, owner:number )
	if owner ~= Game.GetLocalPlayer() or not m_ready then return; end
	local unit:table = UI.GetHeadSelectedUnit();
	if unit == nil or unit:GetX() ~= x or unit:GetY() ~= y then return; end
	local row:table = GameInfo.Improvements[ improvementType ];
	if row == nil then return; end
	local name:string = Locale.Lookup( row.Name );
	local unitID:number = unit:GetID();
	After( 0.4, function()	-- the charges are counted down a moment later
		local builder:table = Players[ owner ]:GetUnits():FindID( unitID );
		local text:string = name .. " built";
		if builder ~= nil then
			text = text .. ", " .. Plural( builder:GetBuildCharges(), "charge", "charges" ) .. " left";
		else
			text = text .. ", the builder is used up";
		end
		SayResult( text );
	end );
end

-- "Barbarian Warrior spotted, 2 tiles north of Rome": hostile soldiers that come into view near our cities and units.
function H.OnUnitVisibilityChanged( playerID:number, unitID:number, visibility:number )
	local localPlayer:number = Game.GetLocalPlayer();
	if not m_ready or playerID == localPlayer or visibility ~= RevealedState.VISIBLE or not IsHostile( playerID ) then return; end
	local unit:table = Players[ playerID ]:GetUnits():FindID( unitID );
	if unit == nil or ( unit:GetCombat() <= 0 and unit:GetRangedCombat() <= 0 ) then return; end
	if not PlotDescription_IsUnitVisible( unit ) then return; end
	RememberUnit( unit );
	local turn:number = Game.GetCurrentGameTurn();
	local key:string = playerID .. ":" .. unitID;
	if m_spotted[ key ] ~= nil and turn - m_spotted[ key ] < 10 then return; end
	if m_spottedTurn ~= turn then m_spottedTurn = turn; m_spottedCount = 0; end
	if m_spottedCount >= 4 then return; end
	local x:number, y:number = unit:GetX(), unit:GetY();
	local bestDistance:number, bestName:string, bestPlot:table = 99, nil, nil;
	for _, city in Players[ localPlayer ]:GetCities():Members() do
		local distance:number = Map.GetPlotDistance( x, y, city:GetX(), city:GetY() );
		if distance < bestDistance then
			bestDistance, bestName, bestPlot = distance, Locale.Lookup( city:GetName() ), Map.GetPlot( city:GetX(), city:GetY() );
		end
	end
	for _, mine in Players[ localPlayer ]:GetUnits():Members() do
		local distance:number = Map.GetPlotDistance( x, y, mine:GetX(), mine:GetY() );
		if distance < bestDistance then
			bestDistance, bestName, bestPlot = distance, "your " .. Locale.Lookup( mine:GetName() ), Map.GetPlot( mine:GetX(), mine:GetY() );
		end
	end
	if bestName == nil or bestDistance > 4 then return; end
	m_spotted[ key ] = turn;
	m_spottedCount = m_spottedCount + 1;
	local relative:string = PlotDescription_GetRelative( bestPlot, Map.GetPlot( x, y ) );
	local text:string = PlotDescription_GetUnitName( unit ) .. " spotted";
	if relative ~= nil then text = text .. ", " .. relative .. " of " .. bestName; else text = text .. " at " .. bestName; end
	m_lastSpotSpeech = UI.GetElapsedTime();
	OutputMessageToScreenReader( text, true );
end

-- ===========================================================================
--	ENTER (Next Action) must always say something
-- ===========================================================================
function H.IsUnitOrdersLabel( text:string )
	return text == Locale.Lookup( "LOC_ACTION_PANEL_NEEDS_ORDERS" ) or text == Locale.Lookup( "LOC_ACTION_PANEL_STACKED_UNIT" )
		or text == Locale.Lookup( "LOC_ACTION_PANEL_UNIT_MOVES_REMAINING" );
end

function H.ArmEnterWatch()
	local label:table = ContextPtr:LookUpControl( "/InGame/HUD/ActionPanel/EndTurnText" );
	m_enterLabel = ( label ~= nil ) and label:GetText() or "";
	m_enterWatch = 0.8;
end

-- Enter was pressed, nothing announced a new selection, turn end or mode: the game re-selected the same unit
-- (or none could be selected). Say what is going on.
function H.EnterFallback()
	if not H.IsUnitOrdersLabel( m_enterLabel ) then return; end
	local unit:table = UI.GetHeadSelectedUnit();
	if unit ~= nil then
		SayResult( UnitText( unit ) .. ", needs orders. Tab for its actions" );
	else
		SayResult( Capitalize( CleanTextForSpeech( m_enterLabel ) ) );
	end
end

-- ===========================================================================
--	INPUT HANDLER: runs before WorldInput and ActionPanel (see docs/ingame-plan.md, Input order)
-- ===========================================================================
function H.HandleInput( input:table )
	if not IsLocalPlayerActive() then return false; end
	local msg:number = input:GetMessageType();
	if msg ~= KeyEvents.KeyDown and msg ~= KeyEvents.KeyUp then return false; end
	m_lastKeyTime = UI.GetElapsedTime();
	if m_mode ~= nil then return m_mode.list.HandleInput( input ); end
	if input:IsShiftDown() or input:IsControlDown() or input:IsAltDown() then return false; end
	local key:number = input:GetKey();
	if GetTargetMode() ~= nil then
		-- Enter and Escape belong to the mode; both KeyDown and KeyUp are consumed, so ActionPanel never sees Enter
		if UI.GetHeadSelectedUnit() == nil and UI.GetHeadSelectedCity() == nil then
			ResetStaleMode();		-- nothing left to act: the keys go to the game again
			return false;
		end
		if key == Keys.VK_RETURN or key == Keys.VK_ESCAPE then
			-- consumed even when the handler fails, so that Enter never falls through to Next Action mid-mode
			if msg == KeyEvents.KeyUp then
				local ok:boolean, err = xpcall( function() if key == Keys.VK_RETURN then ConfirmTarget(); else CancelTarget(); end end, KeyNavErrorHandler );
				if not ok then
					print( "InGameAccess target mode error: " .. tostring( err ) );
					OutputMessageToScreenReader( "Something went wrong, Escape to cancel" );
				end
			end
			return true;
		end
		return false;
	end
	if key == Keys.VK_RETURN and msg == KeyEvents.KeyUp and not IsGamePopupOpen() then H.ArmEnterWatch(); end		-- an open screen (City-States, governors) takes Enter itself
	return false;
end

function H.OnInput( input:table )
	local ok:boolean, consumed = xpcall( function() return H.HandleInput( input ); end, KeyNavErrorHandler );
	if not ok then
		print( "InGameAccess input error: " .. tostring( consumed ) );
		return false;
	end
	return consumed == true;
end

function H.OnUpdate( deltaTime:number )
	UpdateMouse( deltaTime );
	if m_arrivalTimer >= 0 then
		m_arrivalTimer = m_arrivalTimer - deltaTime;
		if m_arrivalTimer < 0 then
			m_arrivalTimer = -1;
			local ok:boolean, err = xpcall( FlushArrivals, KeyNavErrorHandler );
			if not ok then print( "InGameAccess FlushArrivals error: " .. tostring(err) ); end
		end
	end
	local i:number = 1;
	while i <= #m_delayed do
		local entry:table = m_delayed[i];
		entry.time = entry.time - deltaTime;
		if entry.time <= 0 then
			table.remove( m_delayed, i );
			local ok:boolean, err = xpcall( entry.fn, KeyNavErrorHandler );
			if not ok then print( "InGameAccess delayed call error: " .. tostring( err ) ); end
		else
			i = i + 1;
		end
	end
	if m_enterWatch >= 0 then
		m_enterWatch = m_enterWatch - deltaTime;
		if m_enterWatch < 0 then
			m_enterWatch = -1;
			H.EnterFallback();
		end
	end
end

-- ===========================================================================
--	INPUT ACTIONS
-- ===========================================================================
function H.OnInputActionTriggered( actionId:number )
	local handler = m_actions[ actionId ];
	if handler ~= nil then handler(); end
end

function H.RegisterAction( name:string, handler )
	local id:number = Input.GetActionId( name );
	if id == nil then
		print( "InGameAccess: unknown input action " .. name );
		return;
	end
	m_actions[ id ] = Safe( name, handler );
end

-- ===========================================================================
function Initialize()
	-- Contexts added with AddUserInterfaces start hidden, and a hidden context gets no input actions or updates.
	ContextPtr:SetHide( false );

	-- A hot reload (civctl deploy) happens in the middle of a game: LoadScreenClose will not come again, so the hub would
	-- stay "not ready" (no event announcements) with a fresh state. Start it as it would be after the load, without
	-- repeating the turn announcement.
	if ContextPtr:IsHotLoad() and IsLocalPlayerActive() then
		m_ready = true;
		m_cursorPlayer = Game.GetLocalPlayer();
		m_lastAnnouncedTurn = Game.GetLocalPlayer() .. ":" .. Game.GetCurrentGameTurn();
		for _, unit in Players[ Game.GetLocalPlayer() ]:GetUnits():Members() do RememberUnit( unit ); end
	end

	H.RegisterAction( "KeyNavMoveCellLeft",		function() MoveCursor( -1, 0 ); end );
	H.RegisterAction( "KeyNavMoveCellRight",		function() MoveCursor( 1, 0 ); end );
	H.RegisterAction( "KeyNavMoveCellUp",			function() MoveCursor( 0, 1 ); end );
	H.RegisterAction( "KeyNavMoveCellDown",		function() MoveCursor( 0, -1 ); end );
	H.RegisterAction( "KeyNavPlotDetails",		SpeakPlotDetails );
	H.RegisterAction( "KeyNavCursorToSelection",	CursorToSelection );
	H.RegisterAction( "KeyNavWhatsNext",			SpeakWhatsNext );
	H.RegisterAction( "KeyNavUnitActions",		ToggleUnitMenu );
	H.RegisterAction( "KeyNavSelectAtCursor",		SelectAtCursor );
	H.RegisterAction( "KeyNavCycleAllUnits",		CycleAllUnits );
	H.RegisterAction( "KeyNavScanUnits",			ScanKey );
	H.RegisterAction( "KeyNavDiplomacy",			ToggleCivMenu );
	H.RegisterAction( "KeyNavTopPanel",			ToggleTopPanel );
	H.RegisterAction( "KeyNavNotifications",		ToggleNotifications );
	H.RegisterAction( "KeyNavYields",				SpeakYields );
	H.RegisterAction( "KeyNavCityReport",			ToggleCityReport );
	Listen( Events.InputActionTriggered, H.OnInputActionTriggered );

	Listen( Events.UnitSelectionChanged, Safe( "UnitSelectionChanged", OnUnitSelectionChanged ) );
	Listen( Events.CitySelectionChanged, Safe( "CitySelectionChanged", OnCitySelectionChanged ) );
	Listen( Events.LocalPlayerTurnBegin, Safe( "LocalPlayerTurnBegin", AnnounceTurn ) );
	Listen( Events.LoadScreenClose, Safe( "LoadScreenClose", OnLoadScreenClose ) );
	Listen( Events.LocalPlayerTurnEnd, Safe( "LocalPlayerTurnEnd", OnLocalPlayerTurnEnd ) );

	AddEvent( "InterfaceModeChanged",		OnInterfaceModeChanged );
	AddEvent( "UnitOperationStarted",		OnUnitOperationStarted );
	AddEvent( "UnitOperationAdded",			OnUnitOperationAdded );
	AddEvent( "UnitCommandStarted",			OnUnitCommandStarted );
	AddEvent( "UnitMoveComplete",			OnUnitMoveComplete );
	AddEvent( "CombatVisBegin",				H.OnCombatVisBegin );
	AddEvent( "UnitDamageChanged",			H.OnUnitDamageChanged );
	AddEvent( "CityAddedToMap",				H.OnCityAddedToMap );
	AddEvent( "ImprovementAddedToMap",		H.OnImprovementAddedToMap );
	AddEvent( "UnitVisibilityChanged",		H.OnUnitVisibilityChanged );
	-- "Promoted: X" is spoken by the UnitPromotionPopup override (the only keyboard way to promote)
	AddEvent( "UnitUpgraded",				function( player:number, unitID:number, unitType:number )
		local row:table = GameInfo.Units[ unitType ];
		if player == Game.GetLocalPlayer() and m_ready and row ~= nil then SayResult( "Upgraded to " .. Locale.Lookup( row.Name ) ); end
	end );
	AddEvent( "UnitKilledInCombat",			H.OnUnitKilledInCombat );
	Listen( LuaEvents.SRA_UnitActions, OnUnitActionsReceived );
	Listen( LuaEvents.SRA_Notifications, OnNotificationsReceived );
	Listen( LuaEvents.SRA_NotificationAdded, Safe( "NotificationAdded", OnNotificationAdded ) );
	Listen( LuaEvents.SRA_NotificationActivated, Safe( "NotificationActivated", OnNotificationActivated ) );
	Listen( LuaEvents.SRA_AttackKey, Safe( "AttackKey", AttackKey ) );
	Listen( LuaEvents.SRA_TradeResult, Safe( "TradeResult", OnTradeResult ) );		-- trade choosers: outcome of the route / move
	Listen( LuaEvents.SRA_CursorTo, Safe( "CursorTo", function( x:number, y:number ) SetCursor( x, y, false, false, true ); end ) );		-- City-States screen: Show on map
	AddEvent( "UnitRemovedFromMap",			function() After( 0.3, ResetStaleMode ); end );
	AddEvent( "UnitAddedToMap",				function( playerID:number, unitID:number )
		local player:table = Players[ playerID ];
		if player ~= nil then RememberUnit( player:GetUnits():FindID( unitID ) ); end
	end );

	ContextPtr:SetInputHandler( H.OnInput, true );
	ContextPtr:SetUpdate( Safe( "Update", H.OnUpdate ) );
	ContextPtr:SetShutdown( OnShutdown );
end
Initialize();
