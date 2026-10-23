-- ===========================================================================
--	HubCore: shared helpers, state and the keyboard mode plumbing (OpenMode/CloseMode).
--	Part of the InGameAccess hub (see docs/ingame-plan.md, Architecture): included by
--	UI/Additions/InGameAccess.lua. State and functions other hub modules use are fields of HubCore.
-- ===========================================================================
HubCore = {};

HubCore.m_mode = nil;		-- the active keyboard mode { name, list, onClose }, see MODES below; nil: none
HubCore.m_delayed = {};		-- { time = seconds left, fn = function }
HubCore.m_lastResultTime = -100;		-- UI.GetElapsedTime() of the last announced result of a player's action
HubCore.m_lastKeyTime = -100;		-- UI.GetElapsedTime() of the last key press seen by the input handler
HubCore.m_unitNames = {};		-- "player:unit" -> spoken name, remembered while the unit is alive (it is gone when its death is reported)

-- ===========================================================================
--	HELPERS
-- ===========================================================================

-- Runs f, printing any error instead of silently losing it. The error handler is captured at load: after a hot reload a
-- stale instance must not look the global up again (it is gone there) and fail with a second error.
local m_errorHandler = KeyNavErrorHandler;
function HubCore.Safe( name:string, f )
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
function HubCore.Listen( event, fn )
	event.Add( fn );
	table.insert( m_listeners, { event = event, fn = fn } );
end

function HubCore.OnShutdown()
	print( "InGameAccess: shutdown, removing " .. #m_listeners .. " listeners" );
	for _, l in ipairs( m_listeners ) do l.event.Remove( l.fn ); end
	m_listeners = {};
end

function HubCore.Capitalize( text:string )
	text = string.lower( text );
	return string.upper( string.sub(text, 1, 1) ) .. string.sub( text, 2 );
end

function HubCore.IsLocalPlayerActive()
	local localPlayer:number = Game.GetLocalPlayer();
	return localPlayer ~= nil and localPlayer ~= -1 and Players[localPlayer] ~= nil;
end

-- The selected unit or city: what "relative to me" refers to.
function HubCore.GetSelectionPlot()
	local unit:table = UI.GetHeadSelectedUnit();
	if unit ~= nil then return Map.GetPlot( unit:GetX(), unit:GetY() ), unit; end
	local city:table = UI.GetHeadSelectedCity();
	if city ~= nil then return Map.GetPlot( city:GetX(), city:GetY() ), nil; end
	return nil, nil;
end

function HubCore.FormatNumber( value:number )
	return tostring( math.floor( value * 10 + 0.5 ) / 10 );
end

-- Is one of the game's popups or screens open (the options menu included)? Contexts that are always shown are skipped.
local ALWAYS_SHOWN:table = { TopPanel = true, DiplomacyRibbon = true, PartialScreenHooks = true, InGameAccess = true };

function HubCore.IsGamePopupOpen()
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
function HubCore.After( seconds:number, fn )
	table.insert( HubCore.m_delayed, { time = seconds, fn = fn } );
end

-- Speaks the result of something the player just did. Selection announcements that follow within a moment (the
-- game selects the next unit) do not cut it off. Only results that follow the player's own key press interrupt;
-- the ones that happen on their own (a multi-turn move at the start of a turn, auto-explore) wait their turn.
function HubCore.SayResult( text:string )
	local now:number = UI.GetElapsedTime();
	local own:boolean = now - HubCore.m_lastKeyTime < 1.0;
	if own then HubCore.m_lastResultTime = now; end
	OutputMessageToScreenReader( text, not own );
end

function HubCore.IsPlotVisibleToLocal( plot:table )
	local vis:table = PlayersVisibility[ Game.GetLocalPlayer() ];
	return vis ~= nil and plot ~= nil and vis:IsVisible( plot:GetIndex() );
end

-- Is this player an enemy of the local player: barbarians and civilizations at war with us.
function HubCore.IsHostile( playerID:number )
	local player:table = Players[ playerID ];
	if player == nil or playerID == Game.GetLocalPlayer() then return false; end
	if player:IsBarbarian() then return true; end
	local localPlayer:table = Players[ Game.GetLocalPlayer() ];
	if localPlayer == nil then return false; end
	local diplomacy:table = localPlayer:GetDiplomacy();
	return diplomacy ~= nil and diplomacy:IsAtWarWith( playerID );
end

-- A foreign unit the local player can really see (not fogged, not an invisible submarine ...).
function HubCore.IsForeignUnitVisible( unit:table )
	return unit:GetOwner() ~= Game.GetLocalPlayer() and PlotDescription_IsUnitVisible( unit );
end

-- Remembers a unit's spoken name while it is alive: when it dies the unit object is already gone.
function HubCore.RememberUnit( unit:table )
	if unit ~= nil then HubCore.m_unitNames[ unit:GetOwner() .. ":" .. unit:GetID() ] = PlotDescription_GetUnitName( unit ); end
end

-- Is (x, y) within the distance of one of the local player's units or cities?
function HubCore.IsNearLocal( x:number, y:number, distance:number )
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

function HubCore.Plural( n:number, one:string, many:string )
	if n == 1 then return n .. " " .. one; end
	return n .. " " .. many;
end

-- Is this one of the local player's units that can found a city?
function HubCore.IsSettler( unit:table )
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
function HubCore.BuilderBuildText( unit:table, plot:table )
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
function HubCore.SettleReasons( candidate:table, n:number, m:number )
	local text:string = SettleReasonList( candidate, n, m or 2 );
	if text == "" then return ""; end
	return ", " .. text;
end

-- One sentence about the settler's plot and the best spot nearby, said when a settler is selected.
-- The terrain and river of the settler's plot are in the unit announcement already: only "can settle" and what is
-- wrong with the plot are said about it.
function HubCore.SettleSentence( unit:table )
	local scan:table = SettleScan_Scan( unit );
	local here:table, best:table = scan.here, scan.best;
	local text:string;
	if here ~= nil then
		text = "Can settle here" .. HubCore.SettleReasons( { reasons = {}, negatives = here.negatives }, 0, 2 );
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
	text = text .. ". Best: " .. best.relative .. ", " .. HubCore.Plural( best.turns, "turn", "turns" ) .. HubCore.SettleReasons( best, 3 );
	if best.recommended then text = text .. ", recommended"; end
	return text .. ". X to browse.";
end

-- Adds a handler to an event when the game has that event.
function HubCore.AddEvent( name:string, handler )
	if Events[name] == nil then
		print( "InGameAccess: unknown event " .. name );
		return;
	end
	HubCore.Listen( Events[name], HubCore.Safe( name, handler ) );
end

-- ===========================================================================
--	MODES: the keyboard lists of the hub (unit actions menu, diplomacy list, settle spot browser, top panel,
--	notifications). Exactly one can be active: m_mode holds it, opening one closes the one before, and the input handler
--	gives keys to m_mode.list only. Whatever makes a mode stale (selection change, turn end, load, player change,
--	entering a target mode) closes it through CloseMode, which also resets the list so that it reopens fresh.
--	The engine's target modes (move to, attacks ...) are the other kind of state: they are exclusive with m_mode by
--	CanOpenMode (refuses to open a mode in a target mode) and OnInterfaceModeChanged (entering one closes the mode).
-- ===========================================================================

function HubCore.IsModeOpen( name:string )
	return HubCore.m_mode ~= nil and HubCore.m_mode.name == name;
end

-- speak: say "Closed" (the player closed it). quiet: closed because it went stale, so a mode's restoring work (the
-- settle browser puts the cursor back on the settler) is not done.
function HubCore.CloseMode( speak:boolean, quiet:boolean )
	local mode:table = HubCore.m_mode;
	if mode == nil then return; end
	HubCore.m_mode = nil;
	mode.list.Reset();
	if mode.onClose ~= nil then
		local ok:boolean, err = xpcall( function() mode.onClose( quiet == true ); end, KeyNavErrorHandler );
		if not ok then print( "InGameAccess mode close error: " .. tostring( err ) ); end
	end
	if speak then OutputMessageToScreenReader( "Closed" ); end
end

-- Makes the list the active mode (closing the previous one) and announces it.
function HubCore.OpenMode( name:string, list:table, title:string, onClose )
	HubCore.CloseMode( false, false );
	HubCore.m_mode = { name = name, list = list, onClose = onClose };
	list.Open( title );
end
