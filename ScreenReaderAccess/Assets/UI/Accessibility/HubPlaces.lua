-- ===========================================================================
--	HubPlaces: the places list (J) and "send a unit here" (M), unit activity words.
--	Part of the InGameAccess hub (see docs/features.md, Architecture): included by
--	UI/Additions/InGameAccess.lua. State and functions other hub modules use are fields of HubPlaces.
--
--	J opens a keyboard list in categories (empty ones are skipped), every item sorted by distance from the reference plot
--	(the selected unit or city, else the map cursor): your cities, your units (all of them, also automated ones),
--	points of interest (tribal villages, barbarian camps, natural wonders), notifications with a place, foreign cities.
--	Tab / Control+Tab change the category, Up/Down/Home/End move, Space reads the plot, Enter acts, M sends a unit there,
--	Escape closes. Inside a target mode (move to, attack ...) Enter only moves the target cursor and the list closes.
--
--	Huts, camps and foreign cities are remembered from what was VISIBLE (m_seen): when the list is built, and as they are
--	seen (ImprovementVisibilityChanged, ImprovementAddedToMap / RemovedFromMap, UnitMoveComplete, turn begin): a scout that
--	passes a village and moves on is remembered. The live state of a fogged plot must not leak (a camp that spawned in the
--	fog). The memory is lost on a hot reload or a load; the first scan afterwards accepts the tribal villages on revealed
--	plots (they only appear at map creation and vanish when entered; no "last seen" accessor exists); camps on revealed plots out of view are accepted as well, without guards.
--	Remembered ones in the fog say "last seen". Natural wonders are read live (revealed is enough, they never change).
--	"Civilians to capture": visible Builders / Settlers (GameInfo.UnitCaptures) of barbarians and of civs at war with us.
--	"Blind spots" (after Points of interest): clusters of land 4 to 8 tiles from our cities that are revealed but out of view, and of
--	unexplored plots within 6 tiles (BlindSpots.lua): barbarian camps only appear where no one sees.
--	A camp remembers what stood on it when it was last in view (guards, turn): "guarded by Spearman (last seen 2 turns ago)". M on a camp
--	offers an "Attack party" first: the two fastest military land units. A camp destroyed in view is announced with the gold gained.
-- ===========================================================================
include( "BlindSpots" );

HubPlaces = {};

HubPlaces.m_hintUnit = -1;		-- unit id picked from the list: its selection announcement says how to cancel its orders
HubPlaces.m_hintTime = -100;

local CANCEL_HINT_SECONDS	:number = 3;
local MAX_SEND_PATHS		:number = 30;		-- units tried with path finding, nearest first
local MAX_PATH_CALLS		:number = 120;		-- path finding calls for one chooser (the neighbour fallback multiplies them)
local POINT_IMPROVEMENTS	:table = { IMPROVEMENT_GOODY_HUT = true, IMPROVEMENT_BARBARIAN_CAMP = true };

local m_seen				:table = {};		-- plot index -> { kind = "point" | "foreign", name, owner, id }: what was last seen there
local m_primed				:boolean = false;	-- the first scan since the memory was empty has run (see Prime)
local m_explorers			:table = {};		-- unit id -> true: the game added the explore operation to it (see OnOperationAdded)
local m_data				:table = nil;		-- the open list: { cats = { { name, items } }, ctx = { plot, unit }, focusKey }
local m_cat					:number = 1;		-- the category shown
local m_send				:table = nil;		-- the open unit chooser: { name, x, y, back, key, items }
local m_return				:table = nil;		-- { cat, key }: where the places list goes back to from the unit chooser
local m_list				:table;
local m_sendList			:table;

-- ===========================================================================
--	UNIT ACTIVITY ("exploring", "fortified", "moving to Rome, 3 turns" ...)
-- ===========================================================================
local function QueuedDestination( unit:table )
	local ok:boolean, a, b = pcall( UnitManager.GetQueuedDestination, unit );
	if not ok or a == nil or a < 0 then return nil; end
	if b ~= nil then return Map.GetPlot( a, b ); end
	return Map.GetPlotByIndex( a );
end

local function PlaceName( plot:table )
	if plot:IsCity() then
		local city:table = Cities.GetCityInPlot( plot:GetX(), plot:GetY() );
		if city ~= nil then return Locale.Lookup( city:GetName() ); end
	end
	local position:string = HubAnnounce.PositionText( plot );
	if position ~= nil then return position; end
	return "a tile";
end

-- What a unit of the local player is doing, or nil when it is awake and idle (forList: also "needs orders" /
-- "no moves left"; the selection announcement leaves those out, the action panel says them).
function HubPlaces.UnitActivity( unit:table, forList:boolean )
	if unit == nil or unit:GetOwner() ~= Game.GetLocalPlayer() then return nil; end
	local okType:boolean, activity = pcall( UnitManager.GetActivityType, unit );
	if not okType then activity = nil; end
	local kinds:table = ActivityTypes or {};
	local function Is( name:string ) return activity ~= nil and activity == kinds[ name ]; end
	local awake:boolean = Is( "ACTIVITY_AWAKE" ) or Is( "NO_ACTIVITY" );
	-- the order of UnitPanel (4055-4059): sleep, hold (skip), then fortified
	if Is( "ACTIVITY_SLEEP" ) then return "sleeping"; end
	if Is( "ACTIVITY_HOLD" ) then return "turn skipped"; end
	if Is( "ACTIVITY_HEAL" ) then return "healing"; end
	if activity ~= nil and not awake and unit:GetFortifyTurns() > 0 then return "fortified"; end
	if Is( "ACTIVITY_SENTRY" ) then return "on alert"; end
	if Is( "ACTIVITY_INTERCEPT" ) then return "intercepting"; end
	if m_explorers[ unit:GetID() ] then return "exploring"; end
	local dest:table = QueuedDestination( unit );
	if dest ~= nil and ( dest:GetX() ~= unit:GetX() or dest:GetY() ~= unit:GetY() ) then
		local text:string = "moving to " .. PlaceName( dest );
		local path:table = UnitManager.GetMoveToPathEx( unit, dest:GetIndex() );
		if path ~= nil and path.turns ~= nil and #path.turns > 0 then
			text = text .. ", " .. HubCore.Plural( path.turns[ #path.turns ] or 1, "turn", "turns" );
		end
		return text;
	end
	if Is( "ACTIVITY_OPERATION" ) then
		local row:table = GameInfo.Units[ unit:GetUnitType() ];
		if row ~= nil and row.Spy then return "on a mission"; end
		if row ~= nil and row.MakeTradeRoute then return "on a trade route"; end
		if row ~= nil and row.BuildCharges ~= nil and row.BuildCharges > 0 then return "building"; end
		return "busy";
	end
	if forList and ( awake or activity == nil ) then
		if unit:GetMaxMoves() > 0 and unit:GetMovesRemaining() <= 0 then return "no moves left"; end
		return "needs orders";
	end
	return nil;
end

-- The game adds the explore operation to a unit that is told to explore, and again every turn and after a load, so the flag
-- survives a hot reload. An order the player gives that unit (cancel, wake, move ...) ends it; the game's own events within
-- half a second of the flag do not (the explore order may start a move of its own).
function HubPlaces.OnOperationAdded( owner:number, unitID:number, hOperation:number, operationIndex:number )
	if owner ~= Game.GetLocalPlayer() then return; end
	local row:table = GameInfo.UnitOperations[ operationIndex ];
	if row ~= nil and row.OperationType == "UNITOPERATION_AUTOMATE_EXPLORE" then m_explorers[ unitID ] = UI.GetElapsedTime(); end
end

function HubPlaces.OnOrderStarted( owner:number, unitID:number )
	local since:number = m_explorers[ unitID ];
	if owner ~= Game.GetLocalPlayer() or since == nil then return; end
	local now:number = UI.GetElapsedTime();
	if now - since > 0.5 and now - HubCore.m_lastKeyTime < 1.5 then m_explorers[ unitID ] = nil; end
end

-- True once for a unit that was just picked from the places list: the selection announcement adds how to cancel its orders.
function HubPlaces.TakeCancelHint( unit:table )
	if HubPlaces.m_hintUnit ~= unit:GetID() then return false; end
	local fresh:boolean = UI.GetElapsedTime() - HubPlaces.m_hintTime < CANCEL_HINT_SECONDS;
	HubPlaces.m_hintUnit = -1;
	return fresh;
end

-- What to tell a unit that was just picked from the places list about its orders (nil: nothing to say). Auto-explore has no
-- cancel (Shift+C and the Tab menu refuse); the game's own CanStartCommand says whether Wake / Cancel apply.
function HubPlaces.OrderHint( unit:table )
	local activity:string = HubPlaces.UnitActivity( unit, false );
	if activity == nil then return nil; end
	if activity == "exploring" then return "Any order stops exploring, " .. SRKey( "Tab" ) .. " for actions"; end
	local function Can( name:string )
		local command = ( UnitCommandTypes ~= nil ) and UnitCommandTypes[ name ] or nil;
		if command == nil then return false; end
		local ok:boolean, can = pcall( UnitManager.CanStartCommand, unit, command, true );
		return ok and can == true;
	end
	if activity:find( "^moving to" ) and Can( "CANCEL" ) then return "Shift+C cancels the move"; end
	if activity == "sleeping" or activity == "fortified" or activity == "on alert" or activity == "turn skipped" or activity == "healing" then
		-- a sleeping unit can be woken; a fortified one only cancelled (the game offers Cancel, WAKE is refused for it)
		if Can( "WAKE" ) then return "Shift+W wakes it"; end
		if Can( "CANCEL" ) then return "Shift+C cancels it"; end
	end
	return "Any order replaces it, " .. SRKey( "Tab" ) .. " for actions";
end

-- ===========================================================================
--	THE CATEGORIES
-- ===========================================================================
local function LocalPlayer()
	return Players[ Game.GetLocalPlayer() ];
end

-- The reference of the distances: the selected unit's plot, a selected city's, else the map cursor.
local function MakeContext()
	local plot:table, unit:table = HubCore.GetSelectionPlot();
	if plot == nil then
		local x:number, y:number = HubCursor.GetCursor();
		plot = Map.GetPlot( x, y );
	end
	return { plot = plot, unit = unit };
end

-- Where a plot is: from the nearest own city, and from the selected unit when there is one.
local function Where( plot:table, ctx:table )
	local parts:table = {};
	local position:string = HubAnnounce.PositionText( plot );
	if position ~= nil then table.insert( parts, position ); end
	if ctx.unit ~= nil then
		local relative:string = PlotDescription_GetRelative( ctx.plot, plot );
		local name:string = Locale.Lookup( ctx.unit:GetName() );
		table.insert( parts, relative ~= nil and ( relative .. " of " .. name ) or ( "at " .. name ) );
	elseif position == nil then
		table.insert( parts, PlotDescription_GetRelative( ctx.plot, plot ) or "here" );
	end
	return table.concat( parts, ", " );
end

local function MakeItem( key:string, kind:string, name:string, text:string, plot:table, ctx:table )
	return {
		key = key, kind = kind, name = name, text = text, x = plot:GetX(), y = plot:GetY(),
		distance = Map.GetPlotDistance( ctx.plot:GetX(), ctx.plot:GetY(), plot:GetX(), plot:GetY() ),
		-- Space: the plot as the cursor would say it, and where it is
		detail = function()
			local detail:string = PlotDescription_GetShort( plot, { resourceFirst = true } );
			local where:string = Where( plot, ctx );
			if where ~= "" then detail = detail .. ". " .. where; end
			return detail;
		end,
	};
end

local function SortItems( items:table )
	table.sort( items, function( a, b )
		if a.distance ~= b.distance then return a.distance < b.distance; end
		return a.key < b.key;
	end );
	return items;
end

local function CityItems( ctx:table )
	local items:table = {};
	for _, city in LocalPlayer():GetCities():Members() do
		local plot:table = Map.GetPlot( city:GetX(), city:GetY() );
		local name:string = Locale.Lookup( city:GetName() );
		local text:string = name .. ( city:IsCapital() and ", capital" or "" ) .. ", " .. ( PlotDescription_GetRelative( ctx.plot, plot ) or "here" );
		table.insert( items, MakeItem( "c:" .. city:GetID(), "city", name, text, plot, ctx ) );
	end
	return SortItems( items );
end

local function UnitItems( ctx:table )
	local items:table = {};
	for _, unit in LocalPlayer():GetUnits():Members() do
		local plot:table = Map.GetPlot( unit:GetX(), unit:GetY() );
		local name:string = Locale.Lookup( unit:GetName() );
		local text:string = name;
		local activity:string = HubPlaces.UnitActivity( unit, true );
		if activity ~= nil then text = text .. ", " .. activity; end
		local position:string = HubAnnounce.PositionText( plot );
		if position ~= nil then text = text .. ", " .. position; end
		local item:table = MakeItem( "u:" .. unit:GetID(), "unit", name, text, plot, ctx );
		item.unitId = unit:GetID();
		item.section = name;		-- the unit type: PageUp / PageDown (a held bumper plus up / down) jump from type to type
		table.insert( items, item );
	end
	-- by type name, then as everywhere (nearest first)
	table.sort( items, function( a, b )
		if a.section ~= b.section then return a.section < b.section; end
		if a.distance ~= b.distance then return a.distance < b.distance; end
		return a.key < b.key;
	end );
	return items;
end

-- The names of the visible barbarian soldiers on a (visible) plot: the guards of a camp.
local function CampGuards( plot:table )
	local names:table = {};
	local ok:boolean, units = pcall( Units.GetUnitsInPlot, plot );
	if not ok or units == nil then return names; end
	for _, unit in ipairs( units ) do
		local owner:table = Players[ unit:GetOwner() ];
		if owner ~= nil and owner:IsBarbarian() and ( unit:GetCombat() > 0 or unit:GetRangedCombat() > 0 ) and PlotDescription_IsUnitVisible( unit ) then
			table.insert( names, Locale.Lookup( unit:GetName() ) );
		end
	end
	return names;
end

-- What is on a VISIBLE plot is remembered (see ScanSeen); nil forgets it.
local function RememberPlot( plot:table, index:number, improvementOverride:number )
	local localID:number = Game.GetLocalPlayer();
	local entry:table = nil;
	local improvement:number = improvementOverride;
	if improvement == nil then improvement = plot:GetImprovementType(); end
	if improvement ~= nil and improvement >= 0 then
		local row:table = GameInfo.Improvements[ improvement ];
		if row ~= nil and POINT_IMPROVEMENTS[ row.ImprovementType ] then
			entry = { kind = "point", name = Locale.Lookup( row.Name ), camp = ( row.ImprovementType == "IMPROVEMENT_BARBARIAN_CAMP" ) };
			-- the plot is in view (the callers check): who stands on a camp is remembered with the turn
			if entry.camp then entry.guards, entry.turn = CampGuards( plot ), Game.GetCurrentGameTurn(); end
		end
	end
	if entry == nil and plot:IsCity() then
		local city:table = Cities.GetCityInPlot( plot:GetX(), plot:GetY() );
		local owner:table = ( city ~= nil ) and Players[ city:GetOwner() ] or nil;
		if owner ~= nil and city:GetOwner() ~= localID and not owner:IsBarbarian() then
			entry = { kind = "foreign", name = Locale.Lookup( city:GetName() ), owner = city:GetOwner(), id = city:GetID() };
		end
	end
	m_seen[ index ] = entry;
end

-- For SettleScan (X): the settle browser must know about the same camps as the places list. A camp on a plot that is
-- in the fog counts only when we saw it there (m_seen), never its live state.
function HubPlaces.RefreshSeen()
	local vis:table = PlayersVisibility[ Game.GetLocalPlayer() ];
	if vis == nil then return; end
	HubPlaces.Prime();
	local width:number, height:number = Map.GetGridSize();
	for y = 0, height - 1 do
		for x = 0, width - 1 do
			local plot:table = Map.GetPlot( x, y );
			if plot ~= nil and vis:IsVisible( plot:GetIndex() ) then RememberPlot( plot, plot:GetIndex() ); end
		end
	end
end

-- After a load or a hot reload the memory is empty: the tribal villages on revealed plots in the fog are accepted once (they
-- only exist from the map creation and vanish when entered, so the live state is almost always what was seen). Camps on revealed plots out of view are accepted too
-- (one that spawned in the fog after the reveal leaks once: no accessor tells; no guards known). Runs once; the plots in view are remembered by the caller's scan anyway.
function HubPlaces.Prime()
	if m_primed then return; end
	m_primed = true;
	local vis:table = PlayersVisibility[ Game.GetLocalPlayer() ];
	if vis == nil then return; end
	local width:number, height:number = Map.GetGridSize();
	for y = 0, height - 1 do
		for x = 0, width - 1 do
			local plot:table = Map.GetPlot( x, y );
			local index:number = ( plot ~= nil ) and plot:GetIndex() or -1;
			if plot ~= nil and m_seen[ index ] == nil and vis:IsRevealed( index ) then
				local improvement:number = plot:GetImprovementType();
				local row:table = ( improvement ~= nil and improvement >= 0 ) and GameInfo.Improvements[ improvement ] or nil;
				if row ~= nil and row.ImprovementType == "IMPROVEMENT_GOODY_HUT" then
					m_seen[ index ] = { kind = "point", name = Locale.Lookup( row.Name ), camp = false };
				elseif row ~= nil and row.ImprovementType == "IMPROVEMENT_BARBARIAN_CAMP" and not vis:IsVisible( index ) then
					-- No revealed-improvement accessor exists (the UI state's plot reports the live improvement even on unrevealed
					-- plots, as the fogged cursor text does). A camp on a revealed plot out of view is accepted once as "last seen":
					-- unknown guards and turn. The plots in view are remembered by the caller's scan with their guards.
					m_seen[ index ] = { kind = "point", name = Locale.Lookup( row.Name ), camp = true };
				end
			end
		end
	end
end

-- Remembers one plot if it is in view now (event handlers; improvement: the type the event reports, else the live one).
local function RememberIfVisible( x:number, y:number, improvement:number )
	local vis:table = PlayersVisibility[ Game.GetLocalPlayer() ];
	local plot:table = Map.GetPlot( x, y );
	if vis == nil or plot == nil or not vis:IsVisible( plot:GetIndex() ) then return; end
	HubPlaces.Prime();
	RememberPlot( plot, plot:GetIndex(), improvement );
end

-- Events.ImprovementVisibilityChanged( x, y, improvementType, visibility ): a village or camp comes into view
-- Read-only: a foreign city remembered from when it was in view (name, owner id), for plots now out of sight. Nil: none known.
function HubPlaces.SeenCity( index:number )
	HubPlaces.Prime();
	local entry:table = m_seen[ index ];
	if entry ~= nil and entry.kind == "foreign" then return entry.name, entry.owner; end
	return nil;
end

function HubPlaces.OnImprovementVisibilityChanged( x:number, y:number, improvementType:number, visibility:number )
	if RevealedState ~= nil and visibility ~= RevealedState.VISIBLE then return; end
	RememberIfVisible( x, y, improvementType );
end

-- Events.ImprovementAddedToMap( x, y, improvementType, owner ... ): a camp spawned in view
function HubPlaces.OnImprovementAddedToMap( x:number, y:number, improvementType:number )
	RememberIfVisible( x, y, improvementType );
end

-- Events.ImprovementRemovedFromMap( x, y ... ): a village entered or a camp destroyed in view (the plot is updated a moment later)
local m_lastGold		:number = nil;		-- the treasury as the last poll saw it: the baseline of the gold a destroyed camp gives
local m_campsGone		:number = 0;		-- camps removed since the pending announcement was armed
local m_campsOurs		:boolean = false;	-- one of our units took part in one of them
local m_campPosition	:string = nil;		-- where the first one was
local m_goldFrozen		:number = 0;		-- no sampling until this UI time (a camp was just destroyed)

local function ReadGold()
	return Players[ Game.GetLocalPlayer() ]:GetTreasury():GetGoldBalance();
end

local function GoldBalance()
	local ok:boolean, gold = pcall( ReadGold );
	if ok then return gold; end
	return nil;
end

local m_ourMoves		:table = {};		-- where our units ended a move this turn: { turn = n, spots = { {x, y} ... } }

-- One of our units is on or next to the plot, or ended a move there this turn: it took part in the camp's end.
local function OurUnitNear( x:number, y:number )
	local player:table = Players[ Game.GetLocalPlayer() ];
	if player ~= nil then
		for _, unit in player:GetUnits():Members() do
			if Map.GetPlotDistance( unit:GetX(), unit:GetY(), x, y ) <= 1 then return true; end
		end
	end
	if m_ourMoves.turn == Game.GetCurrentGameTurn() then
		for _, spot in ipairs( m_ourMoves.spots ) do
			if Map.GetPlotDistance( spot.x, spot.y, x, y ) <= 1 then return true; end
		end
	end
	return false;
end

-- A remembered camp that was in view and is now gone: "Barbarian camp destroyed, 50 gold" when one of our units took part and the
-- treasury grew, else "Barbarian camp gone, 2 tiles north of Rome" (no gold claimed for another unit's work, e.g. a city-state's).
-- The event carries no reward; the gold is the treasury growth since the last poll (the dispersal gold arrives with the removal).
function HubPlaces.OnImprovementRemovedFromMap( x:number, y:number )
	local plot:table = Map.GetPlot( x, y );
	local entry:table = ( plot ~= nil ) and m_seen[ plot:GetIndex() ] or nil;
	local vis:table = PlayersVisibility[ Game.GetLocalPlayer() ];
	if entry ~= nil and entry.camp == true and HubCore.m_ready and vis ~= nil and vis:IsVisible( plot:GetIndex() ) then
		-- Several camps can go at once (a new city's borders disperse every camp inside them): one announcement for all of them,
		-- with the total gold (each camp's removal event would otherwise repeat the same total).
		m_campsGone = m_campsGone + 1;
		if OurUnitNear( x, y ) then m_campsOurs = true; end
		if m_campsGone == 1 then m_campPosition = HubAnnounce.PositionText( plot ); end
		m_seen[ plot:GetIndex() ] = nil;
		if m_campsGone == 1 then
			local before:number = m_lastGold or GoldBalance();
			local turn:number = Game.GetCurrentGameTurn();
			m_goldFrozen = UI.GetElapsedTime() + 1.5;
			HubCore.After( 1.0, function()
				local count:number = m_campsGone;
				local ours:boolean = m_campsOurs;
				local position:string = m_campPosition;
				m_campsGone = 0;
				m_campsOurs = false;
				m_campPosition = nil;
				if Game.GetCurrentGameTurn() ~= turn then return; end
				local now:number = GoldBalance();
				HubCore.Announce( BlindSpots.DestroyedText( ( now ~= nil and before ~= nil ) and ( now - before ) or nil, count, ours, position ), true );
			end );
		end
	end
	HubCore.After( 0.3, function() RememberIfVisible( x, y, nil ); end );
end

-- Events.UnitMoveComplete( player, unit, x, y ): the plots around our own unit are in view; remember them. Moves are collected
-- and scanned once, 0.2 s later, only around the plots where units ended a move.
local m_moved:table = {};
local m_moveScanArmed:boolean = false;
function HubPlaces.OnUnitMoveComplete( playerID:number, unitID:number, x:number, y:number )
	if playerID ~= Game.GetLocalPlayer() then return; end
	m_moved[ unitID ] = { x = x, y = y };
	local turn:number = Game.GetCurrentGameTurn();
	if m_ourMoves.turn ~= turn then m_ourMoves = { turn = turn, spots = {} }; end
	table.insert( m_ourMoves.spots, { x = x, y = y } );
	if m_moveScanArmed then return; end
	m_moveScanArmed = true;
	HubCore.After( 0.2, HubPlaces.ScanMoved );
end

function HubPlaces.ScanMoved()
	m_moveScanArmed = false;
	local moved:table = m_moved;
	m_moved = {};
	for _, spot in pairs( moved ) do
		for dy = -3, 3 do
			for dx = -3, 3 do
				RememberIfVisible( spot.x + dx, spot.y + dy, nil );
			end
		end
	end
end

function HubPlaces.IsCampRemembered( index:number )
	local entry:table = m_seen[ index ];
	return entry ~= nil and entry.camp == true;
end

-- The plots of the barbarian camps we have seen and not seen gone (from the memory, never a live look at the fog).
function HubPlaces.RememberedCampPlots()
	local plots:table = {};
	for index, entry in pairs( m_seen ) do
		if entry.camp == true then
			local plot:table = Map.GetPlotByIndex( index );
			if plot ~= nil then table.insert( plots, plot ); end
		end
	end
	return plots;
end

-- Looks at every revealed plot: what is on a VISIBLE plot is remembered (tribal villages, barbarian camps, foreign cities)
-- and forgotten once seen gone; fogged plots keep the memory. Returns the natural wonders (read live, once per wonder).
local function ScanSeen( ctx:table )
	local vis:table = PlayersVisibility[ Game.GetLocalPlayer() ];
	local wonders:table = {};
	if vis == nil then return wonders; end
	HubPlaces.Prime();
	local localID:number = Game.GetLocalPlayer();
	local width:number, height:number = Map.GetGridSize();
	local found:table = {};
	local owned:table = {};		-- owner id -> { count, plot (the revealed tile nearest to the reference), distance }
	ctx.owned = owned;
	local refX:number, refY:number = ctx.plot:GetX(), ctx.plot:GetY();
	for y = 0, height - 1 do
		for x = 0, width - 1 do
			local plot:table = Map.GetPlot( x, y );
			local index:number = ( plot ~= nil ) and plot:GetIndex() or -1;
			if plot ~= nil and vis:IsRevealed( index ) then
				if vis:IsVisible( index ) then
					RememberPlot( plot, index );
				end
				local owner:number = plot:GetOwner();
				if owner ~= nil and owner >= 0 and owner ~= localID then
					local d:number = Map.GetPlotDistance( refX, refY, x, y );
					local o:table = owned[ owner ];
					if o == nil then
						owned[ owner ] = { count = 1, plot = plot, distance = d };
					else
						o.count = o.count + 1;
						if d < o.distance then o.plot = plot; o.distance = d; end
					end
				end
				local featureType:number = plot:GetFeatureType();
				local row:table = ( featureType ~= nil and featureType >= 0 ) and GameInfo.Features[ featureType ] or nil;
				if row ~= nil and row.NaturalWonder then
					local item:table = MakeItem( "p:" .. index, "point", Locale.Lookup( row.Name ), "", plot, ctx );
					item.feature = featureType;
					table.insert( found, item );
				end
			end
		end
	end
	SortItems( found );
	for _, item in ipairs( found ) do
		local duplicate:boolean = false;
		for _, other in ipairs( wonders ) do
			if other.feature == item.feature and Map.GetPlotDistance( item.x, item.y, other.x, other.y ) <= 2 then duplicate = true; break; end
		end
		if not duplicate then table.insert( wonders, item ); end
	end
	return wonders;
end

local function IsFogged( index:number )
	local vis:table = PlayersVisibility[ Game.GetLocalPlayer() ];
	return vis ~= nil and not vis:IsVisible( index );
end

-- The gold a destroyed camp gives at the base difficulty: the Improvements row's DispersalGold (nil: unknown, no amount is stated).
local function CampGold()
	local ok:boolean, gold = pcall( function() return GameInfo.Improvements[ "IMPROVEMENT_BARBARIAN_CAMP" ].DispersalGold; end );
	if ok and gold ~= nil and gold > 0 then return gold; end
	return nil;
end

-- Remembered tribal villages and barbarian camps, and the natural wonders ScanSeen found.
local function PointItems( ctx:table )
	local items:table = {};
	for index, entry in pairs( m_seen ) do
		local plot:table = Map.GetPlotByIndex( index );
		if entry.kind == "point" and plot ~= nil then
			local item:table = MakeItem( "p:" .. index, "point", entry.name, "", plot, ctx );
			local fogged:boolean = IsFogged( index );
			if entry.camp and entry.guards ~= nil then
				item.text = BlindSpots.CampText( entry.name, Where( plot, ctx ), entry.guards, fogged, Game.GetCurrentGameTurn() - ( entry.turn or Game.GetCurrentGameTurn() ) );
			else
				item.text = entry.name .. ( fogged and ", last seen, " or ", " ) .. Where( plot, ctx );
			end
			if entry.camp then
				local base = item.detail;
				item.detail = function() return base() .. ". " .. BlindSpots.CampAdvice( CampGold() ); end
				item.camp = true;
			end
			-- Barbarian Clans mode: the camp's clan leads the line, T opens the treat-with-clan popup while the camp is in view
			local clan:string = PlotDescription_GetClanPhrase( plot );
			if clan ~= nil then
				item.text = clan .. ", " .. item.text;
				item.clan = true;
				if PlotDescription_CanTreatWithClan( plot ) then
					item.text = item.text .. ", " .. SRKey( "T" ) .. " to treat with the clan";
				else
					item.text = item.text .. ", out of sight";
				end
			end
			table.insert( items, item );
		end
	end
	for _, item in ipairs( ctx.wonders or {} ) do
		item.text = item.name .. ", " .. Where( Map.GetPlot( item.x, item.y ), ctx );
		table.insert( items, item );
	end
	return SortItems( items );
end

-- A value of the game's GlobalParameters (nil when the row is missing).
local function GlobalParam( name:string )
	local ok:boolean, value = pcall( function() return tonumber( GameInfo.GlobalParameters[ name ].Value ); end );
	if ok then return value; end
	return nil;
end

-- Clusters of land that is out of sight or unexplored near our cities (BlindSpots): where a barbarian camp could appear unseen.
local function BlindSpotItems( ctx:table )
	local items:table = {};
	local vis:table = PlayersVisibility[ Game.GetLocalPlayer() ];
	local cities:table = {};
	for _, city in LocalPlayer():GetCities():Members() do
		table.insert( cities, { x = city:GetX(), y = city:GetY(), id = city:GetID() } );
	end
	if vis == nil or #cities == 0 then return items; end
	local blind:table, unexplored:table = BlindSpots.Candidates( cities, vis );
	local clusters:table = {};
	for _, c in ipairs( BlindSpots.Clusters( blind, BlindSpots.MIN_SIZE, BlindSpots.MAX_CLUSTERS ) ) do c.unexplored = false; table.insert( clusters, c ); end
	for _, c in ipairs( BlindSpots.Clusters( unexplored, BlindSpots.MIN_SIZE, BlindSpots.MAX_CLUSTERS ) ) do c.unexplored = true; table.insert( clusters, c ); end
	table.sort( clusters, function( a, b )
		if a.size ~= b.size then return a.size > b.size; end
		if a.unexplored ~= b.unexplored then return not a.unexplored; end
		return a.index < b.index;
	end );
	local advice:string = BlindSpots.Advice( GlobalParam( "BARBARIAN_CAMP_MINIMUM_DISTANCE_CITY" ), GlobalParam( "BARBARIAN_CAMP_MINIMUM_DISTANCE_ANOTHER_CAMP" ) );
	for i = 1, math.min( #clusters, BlindSpots.MAX_CLUSTERS ) do
		local c:table = clusters[i];
		local plot:table = Map.GetPlot( c.x, c.y );
		if plot ~= nil then
			local position:string = HubAnnounce.PositionText( plot ) or Where( plot, ctx );
			local text:string = c.unexplored and BlindSpots.UnexploredText( c.size, position ) or BlindSpots.SpotText( c.size, position );
			local item:table = MakeItem( "b:" .. ( c.unexplored and "u" or "v" ) .. ":" .. c.index, "blind", c.unexplored and "Unexplored area" or "Blind spot", text, plot, ctx );
			item.text = text;
			item.detail = function() return text .. ". " .. advice; end
			table.insert( items, item );
		end
	end
	return SortItems( items );
end

local function NotificationItems( ctx:table )
	local items:table = {};
	for _, note in ipairs( HubRegions.GetLocatedNotifications() ) do
		local plot:table = Map.GetPlot( note.x, note.y );
		if plot ~= nil then
			table.insert( items, MakeItem( "n:" .. note.id, "note", note.text, note.text .. ", " .. Where( plot, ctx ), plot, ctx ) );
		end
	end
	return SortItems( items );
end

-- Cities and city-states of others that we have seen (remembered, see ScanSeen).
local function ForeignItems( ctx:table )
	local items:table = {};
	for index, entry in pairs( m_seen ) do
		local plot:table = Map.GetPlotByIndex( index );
		local player:table = Players[ entry.owner or -1 ];
		if entry.kind == "foreign" and plot ~= nil and player ~= nil then
			local civ:string = PlotDescription_GetCivName( entry.owner );
			local text:string = entry.name;
			if not player:IsMajor() then
				text = text .. ", city-state";
			elseif civ ~= "" and civ ~= entry.name then
				text = text .. ", " .. civ;
			end
			if IsFogged( index ) then text = text .. ", last seen"; end
			text = text .. ", " .. Where( plot, ctx );
			table.insert( items, MakeItem( "f:" .. entry.owner .. ":" .. entry.id, "foreign", entry.name, text, plot, ctx ) );
		end
	end
	return SortItems( items );
end

-- One item per met civ and city-state with a revealed tile of its territory, at the revealed tile nearest to the reference
-- (the borders are known long before a city is: they show where to march). ScanSeen collected ctx.owned.
function HubPlaces.ForeignLandsItems( ctx:table )
	local items:table = {};
	local localID:number = Game.GetLocalPlayer();
	local me:table = Players[ localID ];
	local diplomacy:table = ( me ~= nil ) and me:GetDiplomacy() or nil;
	local hasCity:table = {};
	for _, entry in pairs( m_seen ) do
		if entry.kind == "foreign" and entry.owner ~= nil then hasCity[ entry.owner ] = true; end
	end
	for owner, o in pairs( ctx.owned or {} ) do
		local player:table = Players[ owner ];
		if player ~= nil and not player:IsBarbarian() and not ( player.IsFreeCities ~= nil and player:IsFreeCities() ) and ( diplomacy == nil or diplomacy:HasMet( owner ) ) then
			local text:string = PlotDescription_GetCivName( owner ) .. ( player:IsMajor() and ", border, " or ", city-state border, " ) .. Where( o.plot, ctx );
			if not hasCity[ owner ] then text = text .. ", no city known"; end
			local item:table = MakeItem( "l:" .. owner, "land", PlotDescription_GetCivName( owner ), text, o.plot, ctx );
			local base = item.detail;
			local count:number = o.count;
			item.detail = function() return base() .. ". " .. HubCore.Plural( count, "tile", "tiles" ) .. " of their territory revealed"; end
			table.insert( items, item );
		end
	end
	return SortItems( items );
end

-- Types a unit can be captured as (GameInfo.UnitCaptures: Settler and Builder), as a set of UnitType names.
local function CapturableTypes()
	local set:table = {};
	local ok:boolean = pcall( function()
		for row in GameInfo.UnitCaptures() do set[ row.CapturedUnitType ] = true; end
	end );
	if not ok then set = {}; end
	return set;
end

-- The visible military units of others on the plot (what stands between the capturers and a civilian).
local function Escorts( plot:table, civilian:table )
	local names:table = {};
	local ok:boolean, units = pcall( Units.GetUnitsInPlot, plot );
	if not ok or units == nil then return names; end
	for _, other in ipairs( units ) do
		if other:GetOwner() ~= Game.GetLocalPlayer() and not ( other:GetOwner() == civilian:GetOwner() and other:GetID() == civilian:GetID() )
			and ( other:GetCombat() > 0 or other:GetRangedCombat() > 0 ) and PlotDescription_IsUnitVisible( other ) then
			table.insert( names, Locale.Lookup( other:GetName() ) );
		end
	end
	return names;
end

-- Visible Builders / Settlers of barbarians and of civs at war with us: a military land unit that moves onto one captures it,
-- unless a military unit stands on the same plot ("escorted by ...": it must be killed first).
local function CaptureItems( ctx:table )
	local items:table = {};
	local types:table = CapturableTypes();
	local localID:number = Game.GetLocalPlayer();
	for playerID = 0, 63 do
		local player:table = Players[ playerID ];
		if player ~= nil and playerID ~= localID and player:IsAlive() and HubCore.IsHostile( playerID ) then
			for _, unit in player:GetUnits():Members() do
				local row:table = GameInfo.Units[ unit:GetUnitType() ];
				if row ~= nil and types[ row.UnitType ] and PlotDescription_IsUnitVisible( unit ) then
					local plot:table = Map.GetPlot( unit:GetX(), unit:GetY() );
					if plot ~= nil then
						local name:string = PlotDescription_GetUnitName( unit );
						local text:string = name .. ", " .. Where( plot, ctx );
						local escorts:table = Escorts( plot, unit );
						if #escorts > 0 then text = text .. ", escorted by " .. table.concat( escorts, " and " ); end
						local item:table = MakeItem( "k:" .. playerID .. ":" .. unit:GetID(), "capture", name, text, plot, ctx );
						item.escorted = #escorts > 0;
						table.insert( items, item );
					end
				end
			end
		end
	end
	return SortItems( items );
end

-- Alarmed scouts, raiders and the enemies next to a civilian of ours (HubEnemies): the first category while any is active.
local function ThreatItems( ctx:table )
	local items:table = {};
	if HubEnemies == nil then return items; end
	for _, threat in ipairs( HubEnemies.ThreatItems() ) do
		local plot:table = Map.GetPlot( threat.x, threat.y );
		if plot ~= nil then
			local item:table = MakeItem( threat.key, "threat", threat.name, threat.text .. ", " .. Where( plot, ctx ), plot, ctx );
			table.insert( items, item );
		end
	end
	return SortItems( items );
end

-- Move To with a ship: keeps the items a ship could sail to. An item stays when its plot is water of the ship's body of water
-- (area ids: a set), or some plot within 2 tiles is (the radius MoveTargetNear searches), or when its plot is not revealed (no leak).
-- plotAt( x, y ) -> plot or nil; isRevealed( plot ) -> boolean (nil: everything counts as revealed). Returns kept, number left out.
function HubPlaces.ReachableByShip( items:table, areaIds:table, plotAt, isRevealed )
	local kept:table, left:number = {}, 0;
	for _, item in ipairs( items ) do
		local keep:boolean = false;
		local own = plotAt( item.x, item.y );
		if own == nil or ( isRevealed ~= nil and not isRevealed( own ) ) then
			keep = true;
		else
			for dy = -2, 2 do
				for dx = -2, 2 do
					local plot = plotAt( item.x + dx, item.y + dy );
					if not keep and plot ~= nil and Map.GetPlotDistance( item.x, item.y, plot:GetX(), plot:GetY() ) <= 2
						and plot:IsWater() and areaIds[ plot:GetAreaID() ] then
						keep = true;
					end
				end
			end
		end
		if keep then table.insert( kept, item ); else left = left + 1; end
	end
	return kept, left;
end

-- Drops from the categories what the ship cannot reach (see ReachableByShip); a category left empty goes.
function HubPlaces.FilterForShip( cats:table, areaIds:table )
	local vis:table = PlayersVisibility[ Game.GetLocalPlayer() ];
	local isRevealed = function( plot:table ) return vis == nil or vis:IsRevealed( plot:GetIndex() ); end;
	local result:table, gone:table = {}, {};
	for _, cat in ipairs( cats ) do
		local kept:table, left:number = HubPlaces.ReachableByShip( cat.items, areaIds, Map.GetPlot, isRevealed );
		if #kept > 0 then
			table.insert( result, { name = cat.name, items = kept, left = left } );
		else
			table.insert( gone, cat.name .. ( ( left == 1 ) and ": 1 out of this ship's reach" or ( ": all " .. left .. " out of this ship's reach" ) ) );
		end
	end
	return result, table.concat( gone, ". " );
end

-- The set of area ids of the selected unit's water (its own plot, or all water next to its port city) when the Move To mode is open with a ship, else nil.
local function ShipAreaInMoveTo()
	local mode = HubTargets.GetTargetMode();
	local unit:table = UI.GetHeadSelectedUnit();
	if mode == nil or mode ~= InterfaceModeTypes.MOVE_TO or unit == nil then return nil; end
	local row:table = GameInfo.Units[ unit:GetUnitType() ];
	if row == nil or row.Domain ~= "DOMAIN_SEA" then return nil; end
	local plot:table = Map.GetPlot( unit:GetX(), unit:GetY() );
	if plot == nil then return nil; end
	if plot:IsWater() then return { [ plot:GetAreaID() ] = true }; end
	-- a ship in a port city: all the water next to it (a lake and the ocean both count)
	local ids:table, any:boolean = {}, false;
	for dy = -1, 1 do
		for dx = -1, 1 do
			local near = Map.GetPlot( plot:GetX() + dx, plot:GetY() + dy );
			if near ~= nil and near:IsWater() then ids[ near:GetAreaID() ] = true; any = true; end
		end
	end
	return any and ids or nil;
end

-- The categories that have something in them, in this order.
function HubPlaces.BuildCategories( ctx:table )
	local cats:table = {};
	local okScan:boolean, wonders = xpcall( function() return ScanSeen( ctx ); end, KeyNavErrorHandler );
	if not okScan then print( "HubPlaces scan error: " .. tostring( wonders ) ); end
	ctx.wonders = okScan and wonders or {};
	local sources:table = {
		{ name = "Threats", build = ThreatItems },
		{ name = "Your cities", build = CityItems }, { name = "Your units", build = UnitItems },
		{ name = "Points of interest", build = PointItems }, { name = "Blind spots", build = BlindSpotItems },
			{ name = "Notifications", build = NotificationItems },
		{ name = "Foreign cities", build = ForeignItems }, { name = "Foreign lands", build = HubPlaces.ForeignLandsItems },
		{ name = "Civilians to capture", build = CaptureItems },
	};
	for _, source in ipairs( sources ) do
		local ok:boolean, items = xpcall( function() return source.build( ctx ); end, KeyNavErrorHandler );
		if not ok then
			print( "HubPlaces " .. source.name .. " error: " .. tostring( items ) );
		elseif #items > 0 then
			table.insert( cats, { name = source.name, items = items } );
		end
	end
	return cats;
end

-- ===========================================================================
--	THE PLACES LIST (J)
-- ===========================================================================
local function CategoryHead( cat:table )
	local head:string = cat.name .. ", " .. m_cat .. " of " .. #m_data.cats .. " categories, " .. HubCore.Plural( #cat.items, "item", "items" );
	if cat.left ~= nil and cat.left > 0 then head = head .. ", " .. cat.left .. " out of this ship's reach left out"; end
	return head;
end

-- Says the focused item as "text, i of n", after the prefix.
local function SpeakFocus( prefix:string )
	local items:table = m_data.cats[ m_cat ].items;
	local focus = m_list.GetFocusKey();
	for i, item in ipairs( items ) do
		if item.key == focus then
			OutputMessageToScreenReader( prefix .. item.text .. ", " .. i .. " of " .. #items );
			return;
		end
	end
end

-- The item a category opens on: the first, except Your units (sorted by type) with a unit selected: that unit.
local function DefaultFocusKey( cat:table )
	if cat.name == "Your units" and m_data ~= nil and m_data.ctx ~= nil and m_data.ctx.unit ~= nil then
		local key:string = "u:" .. m_data.ctx.unit:GetID();
		for _, item in ipairs( cat.items ) do
			if item.key == key then return key; end
		end
	end
	return cat.items[1].key;
end

local function SwitchCategory( delta:number )
	if m_data == nil then return; end
	m_cat = ( m_cat - 1 + delta ) % #m_data.cats + 1;
	local cat:table = m_data.cats[ m_cat ];
	m_list.Open( "Places", DefaultFocusKey( cat ), true, true );
	SpeakFocus( CategoryHead( cat ) .. ". " );
end

local function FocusedItem()
	if m_data == nil then return nil; end
	local focus = m_list.GetFocusKey();
	for _, item in ipairs( m_data.cats[ m_cat ].items ) do
		if item.key == focus then return item; end
	end
	return nil;
end

local function SelectUnit( unit:table )
	UI.DeselectAllCities();
	UI.DeselectUnit( unit );
	UI.SelectUnit( unit );
	if UI.RebuildSelectionList ~= nil then UI.RebuildSelectionList( unit ); end
end

-- Turns of the unit's path to the plot, nil without a path (a budget table { left } caps the path finding calls).
local function PathTurns( unit:table, plot:table, budget:table )
	if budget.left <= 0 then return nil; end
	budget.left = budget.left - 1;
	local path:table = UnitManager.GetMoveToPathEx( unit, plot:GetIndex() );
	if path ~= nil and path.plots ~= nil and #path.plots >= 2 then return path.turns[ #path.turns ] or 1; end
	return nil;
end

-- The plots 1 and 2 tiles from (x, y): { [1] = { plots }, [2] = { plots } }. Computed once per chooser.
local function RingPlots( x:number, y:number )
	local rings:table = { {}, {} };
	for dy = -2, 2 do
		for dx = -2, 2 do
			local plot:table = Map.GetPlot( x + dx, y + dy );
			if plot ~= nil then
				local distance:number = Map.GetPlotDistance( x, y, plot:GetX(), plot:GetY() );
				if distance == 1 or distance == 2 then table.insert( rings[ distance ], plot ); end
			end
		end
	end
	return rings;
end

-- The plot next to the place (then 2 tiles away) that the unit reaches in the fewest turns: plot, turns, ring (1 or 2).
local function BestNear( unit:table, rings:table, budget:table )
	for ring = 1, 2 do
		local best:table, bestTurns:number = nil, nil;
		for _, plot in ipairs( rings[ ring ] ) do
			if not ( plot:GetX() == unit:GetX() and plot:GetY() == unit:GetY() ) then
				local turns:number = PathTurns( unit, plot, budget );
				if turns ~= nil and ( bestTurns == nil or turns < bestTurns ) then best, bestTurns = plot, turns; end
			end
		end
		if best ~= nil then return best, bestTurns, ring; end
	end
	return nil;
end

-- In the Move To mode: the nearest reachable plot next to an item whose own plot the selected unit cannot reach (nil: the item
-- itself is fine, or no neighbour works either).
local function MoveTargetNear( item:table )
	local mode = HubTargets.GetTargetMode();
	local unit:table = UI.GetHeadSelectedUnit();
	if mode == nil or mode ~= InterfaceModeTypes.MOVE_TO or unit == nil then return nil; end
	local plot:table = Map.GetPlot( item.x, item.y );
	if plot == nil or Map.GetPlotDistance( unit:GetX(), unit:GetY(), item.x, item.y ) == 0 then return nil; end
	local budget:table = { left = MAX_PATH_CALLS };
	if PathTurns( unit, plot, budget ) ~= nil or HubTargets.WarTargets( unit, plot ) ~= nil then return nil; end
	if Map.GetPlotDistance( unit:GetX(), unit:GetY(), item.x, item.y ) <= 1 then return nil; end
	return ( BestNear( unit, RingPlots( item.x, item.y ), budget ) );
end

-- Enter: the cursor goes to the item (in a target mode this is all it does: the target is moved, Enter confirms it as
-- usual); a unit of yours is selected, which announces it with what it is doing.
local function ActivateItem( item:table )
	local inTarget:boolean = HubTargets.GetTargetMode() ~= nil;
	if item.kind == "unit" and not inTarget then
		local unit:table = LocalPlayer():GetUnits():FindID( item.unitId );
		if unit == nil then
			OutputMessageToScreenReader( "Unit no longer available" );
			return;
		end
		HubCore.CloseMode( false, false );
		HubPlaces.m_hintUnit, HubPlaces.m_hintTime = unit:GetID(), UI.GetElapsedTime();
		SelectUnit( unit );
		return;
	end
	local x:number, y:number = item.x, item.y;
	local interrupt:boolean = true;
	if inTarget and item.kind ~= "unit" then
		local near:table = MoveTargetNear( item );
		if near ~= nil then
			x, y, interrupt = near:GetX(), near:GetY(), false;
			OutputMessageToScreenReader( "Next to " .. item.name );
		end
	end
	HubCore.CloseMode( false, false );
	HubCursor.SetCursor( x, y, true, interrupt, false, true );
end

local function SendKey()
	local item:table = FocusedItem();
	if item == nil then return; end
	if HubTargets.GetTargetMode() ~= nil then
		OutputMessageToScreenReader( SRKey( "Enter" ) .. " moves the target there. " .. SRKey( "Escape" ) .. " closes the list" );
		return;
	end
	if item.kind == "unit" then
		-- a settler or builder of ours: send it an escort (a soldier moves onto its tile)
		local civilian:table = item.unitId ~= nil and LocalPlayer():GetUnits():FindID( item.unitId ) or nil;
		if civilian ~= nil and HubEnemies ~= nil and HubEnemies.IsCivilian( civilian ) then
			HubPlaces.OpenSend( HubPlaces.EscortPlace( civilian, "places", item.key ) );
			return;
		end
		OutputMessageToScreenReader( "That is a unit of yours. " .. SRKey( "Enter" ) .. " selects it" );
		return;
	end
	HubPlaces.OpenSend( { name = item.name, x = item.x, y = item.y, back = "places", key = item.key, capture = ( item.kind == "capture" ), soldiers = ( item.kind == "threat" ), camp = ( item.camp == true ) } );
end

-- T on a clan camp: the banner's own call opens the DLC's Treat With Clan popup (our keyboard copy of it speaks)
local function TreatKey()
	local item:table = FocusedItem();
	if item == nil then return; end
	if item.kind ~= "point" or not item.clan then
		OutputMessageToScreenReader( "Only a clan camp can be treated with" );
		return;
	end
	local plot:table = Map.GetPlot( item.x, item.y );
	if plot == nil or not PlotDescription_CanTreatWithClan( plot ) then
		OutputMessageToScreenReader( "The clan camp is out of sight. Move a unit near it first" );
		return;
	end
	HubCore.CloseMode( false, false );
	LuaEvents.CityBannerManager_OpenTreatWithTribePopup( plot:GetIndex() );
end

-- T on the map (the game's ToggleTechTree), push model: the hub tells LaunchBar (LuaEvents.SRA_ClanCampUnderCursor( bool )) whether
-- a T press would belong to a clan camp: true only while no list / mode / target mode / screen is open and the map cursor plot has
-- a clan. LaunchBar then skips the tech tree and fires LuaEvents.SRA_TechTreeKeyOnCamp(), which treats with the clan (the same call
-- as T in the places list) or, out of sight, only says so. Polled every 0.1 s from the hub update; false is pushed on shutdown.
local CAMP_POLL_SECONDS	:number = 0.1;
local m_campPushed		:boolean = nil;		-- last value sent (nil: nothing sent yet, so the first poll always sends)
local m_campTimer		:number = 0;

local function CampPlotUnderCursor()
	if HubCore.m_mode ~= nil or HubTargets.GetTargetMode() ~= nil or HubCore.IsGamePopupOpen() then return nil; end
	local x:number, y:number = HubCursor.GetCursor();
	local plot:table = Map.GetPlot( x, y );
	if plot == nil or PlotDescription_GetClan( plot ) == nil then return nil; end
	return plot;
end

function HubPlaces.PushCampState( force:boolean )
	local on:boolean = CampPlotUnderCursor() ~= nil;
	if force or on ~= m_campPushed then
		m_campPushed = on;
		LuaEvents.SRA_ClanCampUnderCursor( on );
	end
end

function HubPlaces.Update( deltaTime:number )
	m_campTimer = m_campTimer - deltaTime;
	if m_campTimer > 0 then return; end
	m_campTimer = CAMP_POLL_SECONDS;
	HubPlaces.PushCampState( false );
	-- remembered camps in view: their guards are refreshed, and only then is the treasury sampled (the baseline of a destroyed camp's gold)
	local campInView:boolean = false;
	local vis:table = PlayersVisibility[ Game.GetLocalPlayer() ];
	for index, entry in pairs( m_seen ) do
		if entry.camp == true and vis ~= nil and vis:IsVisible( index ) then
			campInView = true;
			local plot:table = Map.GetPlotByIndex( index );
			if plot ~= nil then RememberPlot( plot, index ); end
		end
	end
	if campInView and UI.GetElapsedTime() >= m_goldFrozen then m_lastGold = GoldBalance() or m_lastGold; end
end

-- Shutdown / reload of the hub: a stale true must not block the tech tree
function HubPlaces.ResetCampState()
	m_campPushed = false;
	LuaEvents.SRA_ClanCampUnderCursor( false );
end

function HubPlaces.OnTechTreeKeyOnCamp()
	local plot:table = CampPlotUnderCursor();
	if plot == nil then return; end
	if not PlotDescription_CanTreatWithClan( plot ) then
		OutputMessageToScreenReader( "The clan camp is out of sight. Move a unit near it first" );
		return;
	end
	LuaEvents.CityBannerManager_OpenTreatWithTribePopup( plot:GetIndex() );
end

local m_facade:table = {
	-- the places were built before OpenMode (an empty list is not opened); this announces them
	Open = function( title:string )
		local cat:table = m_data.cats[ m_cat ];
		local key = m_data.focusKey;
		local found:boolean = false;
		for _, item in ipairs( cat.items ) do
			if item.key == key then found = true; end
		end
		if not found then key = DefaultFocusKey( cat ); end
		m_list.Open( title, key, true );
		SpeakFocus( title .. ". " .. CategoryHead( cat ) .. ". " .. ( ( m_data.gone ~= nil and m_data.gone ~= "" ) and ( m_data.gone .. ". " ) or "" ) );
		if HubTargets.GetTargetMode() ~= nil then OutputMessageToScreenReader( SRKey( "Enter" ) .. " moves the target there", true ); end
	end,
	Reset = function() m_list.Reset(); end,
	HandleInput = function( input:table ) return m_list.HandleInput( input ); end,
	HasTabs = function() return m_list.HasTabs(); end,
	AtTabEdge = function( step:number ) return m_list.AtTabEdge( step ); end,
};

-- X on the controller sends a unit there (what M does)
local m_placesKeys:table = { [Keys.VK_TAB] = function() SwitchCategory( 1 ); end, [Keys.M] = SendKey, [Keys.T] = TreatKey };
if Gamepad.Key( "X" ) ~= nil then m_placesKeys[ Gamepad.Key( "X" ) ] = SendKey; end

m_list = KeyNavList_Create{
	build		= function() return ( m_data ~= nil and m_data.cats[ m_cat ] ~= nil ) and m_data.cats[ m_cat ].items or {}; end,
	isActive	= function() return HubCore.IsModeOpen( "places" ); end,
	onActivate	= ActivateItem,
	onClose		= function() HubCore.CloseMode( true, false ); end,
	extraKeys	= m_placesKeys,
	ctrlKeys	= { [Keys.VK_TAB] = function() SwitchCategory( -1 ); end },
	sectionCounts = true,		-- "Builder, 3: ..." when the focus enters a unit type of Your units
	-- LB / RB: the categories are sub-stops of the ring; past the last / first one the ring continues (HubPad.BumperAction)
	tabEdge		= function( step:number ) return m_data == nil or ( step > 0 and m_cat >= #m_data.cats ) or ( step < 0 and m_cat <= 1 ); end,
};

-- restore: { cat, key } to come back to a category and item (from the unit chooser)
function HubPlaces.Open( restore:table )
	if not HubTargets.CanOpenMode( true ) then return; end
	local cats:table = HubPlaces.BuildCategories( MakeContext() );
	if #cats == 0 then
		OutputMessageToScreenReader( "No places known yet" );
		return;
	end
	local shipArea = ShipAreaInMoveTo();
	local goneText:string = "";
	if shipArea ~= nil then
		cats, goneText = HubPlaces.FilterForShip( cats, shipArea );
		if #cats == 0 then
			OutputMessageToScreenReader( "No places this ship can reach" );
			return;
		end
	end
	m_data = { cats = cats, ctx = MakeContext(), gone = goneText };
	m_cat = 1;
	if restore ~= nil and cats[ restore.cat ] ~= nil then
		m_cat = restore.cat;
		m_data.focusKey = restore.key;
	end
	HubCore.OpenMode( "places", m_facade, "Places" );
end

function HubPlaces.TogglePlaces()
	if HubCore.IsModeOpen( "places" ) then HubCore.CloseMode( true, false ); return; end
	HubPlaces.Open( nil );
end

-- City-States / espionage screens, Show on map: the cursor goes there (the screen speaks); the position follows.
function HubPlaces.OnCursorTo( x:number, y:number )
	HubCursor.SetCursor( x, y, false, false, true );
	HubCore.After( 0.8, function()
		local cx:number, cy:number = HubCursor.GetCursor();
		local position:string = ( cx == x and cy == y ) and HubAnnounce.PositionText( Map.GetPlot( x, y ) ) or nil;
		if position ~= nil then HubRegions.Announce( position ); end
	end );
end

-- ===========================================================================
--	SEND A UNIT HERE (M)
-- ===========================================================================
-- place: { name, x, y, back = "places" | "notifications", key }. Your units that can get there, fastest first.
-- A place a unit cannot enter (a city that is occupied or foreign, water) is approached: the item says "next to Rome" and
-- carries the landing plot (nearX, nearY).
-- A military land unit captures a civilian by moving onto it (GameInfo.Units.CanCapture is false for civilians).
function HubPlaces.CanCapture( unit:table )
	local row:table = GameInfo.Units[ unit:GetUnitType() ];
	return row ~= nil and row.Domain == "DOMAIN_LAND" and row.CanCapture ~= false and unit:GetCombat() > 0;
end

-- A land unit that fights (an attack party is made of these).
function HubPlaces.IsMilitaryLand( unit:table )
	local row:table = GameInfo.Units[ unit:GetUnitType() ];
	return row ~= nil and row.Domain == "DOMAIN_LAND" and ( unit:GetCombat() > 0 or unit:GetRangedCombat() > 0 );
end

-- The name of the civilian of ours that the unit escorts (both in a formation on one tile), else nil. Sending the soldier drags it along.
local function EscortedCivilian( unit:table )
	local ok:boolean, count = pcall( function() return unit:GetFormationUnitCount(); end );
	if not ok or count == nil or count <= 1 then return nil; end
	local plot:table = Map.GetPlot( unit:GetX(), unit:GetY() );
	if plot == nil then return nil; end
	local okUnits:boolean, inPlot = pcall( Units.GetUnitsInPlot, plot );
	if not okUnits or inPlot == nil then return nil; end
	for _, other in ipairs( inPlot ) do
		if other:GetOwner() == unit:GetOwner() and other:GetID() ~= unit:GetID() and HubEnemies ~= nil and HubEnemies.IsCivilian( other ) then
			local okOther:boolean, otherCount = pcall( function() return other:GetFormationUnitCount(); end );
			if okOther and otherCount ~= nil and otherCount > 1 then return Locale.Lookup( other:GetName() ); end
		end
	end
	return nil;
end

-- Pure: "Heavy Chariot, escorting a Builder (Shift+E on it ends the escort)" for the skipped members of an attack party
function HubPlaces.PartySkippedText( skipped:table, formationKey:string )
	local parts:table = {};
	for _, s in ipairs( skipped ) do table.insert( parts, s.name .. ", escorting a " .. s.escorting ); end
	return table.concat( parts, "; " ) .. " (" .. formationKey .. " on it ends the escort)";
end

-- Pure: "No free unit for an attack party: Heavy Chariot is escorting a Builder"
function HubPlaces.PartyNoneText( skipped:table )
	local parts:table = {};
	for _, s in ipairs( skipped ) do table.insert( parts, s.name .. " is escorting a " .. s.escorting ); end
	return "No free unit for an attack party: " .. table.concat( parts, "; " );
end

-- "Attack party, send 2 units: Warrior 3 turns, Slinger 4 turns": the two fastest military land units (nil when fewer than two).
-- Enter orders both; each keeps its own path (members are the single items, with their landing plot). A unit escorting a
-- civilian never joins (the civilian would be dragged along): it is named as skipped; with no free unit left a notice item stands in.
local function PartyItem( items:table, place:table )
	-- soldiers without queued orders; scouts only when too few others; a city's only defender only when too few others
	local pool:table = {};
	local skipped:table = {};
	for _, item in ipairs( items ) do
		if item.military and not item.busy then
			if item.escorting ~= nil then table.insert( skipped, item ); else table.insert( pool, item ); end
		end
	end
	local function Without( list:table, drop:string )
		local kept:table = {};
		for _, item in ipairs( list ) do if not item[ drop ] then table.insert( kept, item ); end end
		return kept;
	end
	if #Without( pool, "recon" ) >= 2 then pool = Without( pool, "recon" ); end
	local free:table = Without( pool, "defends" );
	local members:table = {};
	for _, item in ipairs( free ) do if #members < 2 then table.insert( members, item ); end end
	for _, item in ipairs( pool ) do
		if item.defends and #members < 2 then table.insert( members, item ); end
	end
	if #members < 2 then
		if #members == 0 and #skipped > 0 then
			return { key = "party-none", name = "Attack party", notice = true, turns = 0, text = HubPlaces.PartyNoneText( skipped ) };
		end
		return nil;
	end
	table.sort( members, function( a, b ) return a.turns < b.turns; end );
	local parts:table = {};
	for _, member in ipairs( members ) do
		local label:string = member.name .. ( member.defends and ( " (leaves " .. member.defends .. " undefended)" ) or "" );
		table.insert( parts, label .. " " .. HubCore.Plural( member.turns, "turn", "turns" ) );
	end
	return {
		key = "party", name = "Attack party", turns = members[1].turns, members = members,
		text = "Attack party, send 2 units: " .. table.concat( parts, ", " ) .. ( #skipped > 0 and (
			". Skipped: " .. HubPlaces.PartySkippedText( skipped, ( HubEnemies ~= nil and HubEnemies.KeyText ~= nil ) and HubEnemies.KeyText( "ExtraHotkeysEnterFormation", "Shift+E" ) or "Shift+E" ) ) or "" ),
		detail = function() return members[1].name .. " and " .. members[2].name .. " both go to " .. place.name .. ", each by its own path. Attack with more than one unit"; end,
	};
end

-- M on a settler or builder in the places list: the chooser of soldiers that can walk onto its tile.
function HubPlaces.EscortPlace( civilian:table, back:string, key:string )
	return { name = Locale.Lookup( civilian:GetName() ), x = civilian:GetX(), y = civilian:GetY(), back = back, key = key,
		escort = true, escortId = civilian:GetID(), title = "Send an escort to " .. Locale.Lookup( civilian:GetName() ) };
end

-- "Warrior reaches the Settler this turn. Shift+E forms the escort" / "Warrior arrives in 2 turns" (pure)
function HubPlaces.EscortOrderText( soldier:string, civilian:string, turns:number, formationKey:string )
	if turns <= 1 then
		return soldier .. " reaches the " .. civilian .. " this turn. " .. formationKey .. " forms the escort";
	end
	return soldier .. " arrives in " .. HubCore.Plural( turns, "turn", "turns" );
end

local function InFormationAlready( unit:table )
	local ok:boolean, count = pcall( function() return unit:GetFormationUnitCount(); end );
	return ok and count ~= nil and count > 1;
end

function HubPlaces.BuildSendItems( place:table )
	local plot:table = Map.GetPlot( place.x, place.y );
	local items:table = {};
	if plot == nil then return items; end
	local candidates:table = {};
	for _, unit in LocalPlayer():GetUnits():Members() do
		if unit:GetMaxMoves() > 0 and not ( unit:GetX() == place.x and unit:GetY() == place.y ) and ( not place.capture or HubPlaces.CanCapture( unit ) )
				and ( not place.soldiers or unit:GetCombat() > 0 or unit:GetRangedCombat() > 0 )
					and ( not place.escort or ( HubPlaces.IsMilitaryLand( unit ) and not InFormationAlready( unit ) ) ) then
			table.insert( candidates, { unit = unit, distance = Map.GetPlotDistance( unit:GetX(), unit:GetY(), place.x, place.y ) } );
		end
	end
	table.sort( candidates, function( a, b )
		if a.distance ~= b.distance then return a.distance < b.distance; end
		return a.unit:GetID() < b.unit:GetID();
	end );
	local names:table = {};
	local budget:table = { left = MAX_PATH_CALLS };
	local rings:table = nil;
	for i = 1, math.min( MAX_SEND_PATHS, #candidates ) do
		local unit:table = candidates[i].unit;
		-- an unexplored target: no path finding (the answer would tell land from water); listed by distance, the game decides on Enter
		local turns:number = place.unexplored and 0 or PathTurns( unit, plot, budget );
		local near:table, ring:number = nil, 0;
		if turns == nil and not place.escort and candidates[i].distance > 1 and budget.left > 0 and not place.unexplored then
			if rings == nil then rings = RingPlots( place.x, place.y ); end
			near, turns, ring = BestNear( unit, rings, budget );
		end
		if turns ~= nil then
			local name:string = Locale.Lookup( unit:GetName() );
			names[ name ] = ( names[ name ] or 0 ) + 1;
			local item:table = { key = "s:" .. unit:GetID(), unitId = unit:GetID(), name = name, turns = turns, distance = candidates[i].distance, unit = unit };
			item.escorting = EscortedCivilian( unit );
			if place.camp then
				item.military = HubPlaces.IsMilitaryLand( unit );
				if item.military then
					item.busy = QueuedDestination( unit ) ~= nil;
					local row:table = GameInfo.Units[ unit:GetUnitType() ];
					item.recon = ( row ~= nil and row.PromotionClass == "PROMOTION_CLASS_RECON" ) or nil;
					local here:table = Map.GetPlot( unit:GetX(), unit:GetY() );
					if here ~= nil and here:IsCity() then
						local soldiers:number = 0;
						local okUnits:boolean, inPlot = pcall( Units.GetUnitsInPlot, here );
						for _, other in ipairs( okUnits and inPlot or {} ) do
							if other:GetOwner() == unit:GetOwner() and HubPlaces.IsMilitaryLand( other ) then soldiers = soldiers + 1; end
						end
						local city:table = Cities.GetCityInPlot( here:GetX(), here:GetY() );
						if soldiers <= 1 and city ~= nil then item.defends = Locale.Lookup( city:GetName() ); end
					end
				end
			end
			if near ~= nil then item.nearX, item.nearY, item.ring = near:GetX(), near:GetY(), ring; end
			table.insert( items, item );
		end
	end
	table.sort( items, function( a, b )
		if a.turns ~= b.turns then return a.turns < b.turns; end
		if a.distance ~= b.distance then return a.distance < b.distance; end
		return a.unitId < b.unitId;
	end );
	for _, item in ipairs( items ) do
		item.text = item.name .. ", " .. ( place.unexplored and ( HubCore.Plural( item.distance, "tile", "tiles" ) .. " away" ) or HubCore.Plural( item.turns, "turn", "turns" ) );
		if item.ring ~= nil then item.text = item.text .. ", " .. ( item.ring == 1 and "stops next to it" or "stops near it" ); end
		local activity:string = HubPlaces.UnitActivity( item.unit, false );
		if activity ~= nil then item.text = item.text .. ", " .. activity; end
		if item.escorting ~= nil then item.text = item.text .. ", escorting " .. item.escorting; end
		if names[ item.name ] > 1 then
			local position:string = HubAnnounce.PositionText( Map.GetPlot( item.unit:GetX(), item.unit:GetY() ) );
			if position ~= nil then item.text = item.text .. ", " .. position; end
		end
		local unitPlot:table = Map.GetPlot( item.unit:GetX(), item.unit:GetY() );
		item.detail = function() return PlotDescription_GetShort( unitPlot, {} ); end
		item.unit = nil;
	end
	if place.camp then
		local party:table = PartyItem( items, place );
		if party ~= nil then table.insert( items, 1, party ); end
	end
	return items;
end

function HubPlaces.OpenSend( place:table )
	if not HubTargets.CanOpenMode() then return; end
	local items:table = HubPlaces.BuildSendItems( place );
	if #items == 0 then
		OutputMessageToScreenReader( place.escort and "No soldier can reach it" or ( place.capture and "No military unit can reach it" or "No unit can reach it" ) );
		return;
	end
	m_return = nil;
	if place.back == "places" and m_data ~= nil then m_return = { cat = m_cat, key = place.key }; end
	place.items = items;
	m_send = place;
	HubCore.OpenMode( "send", m_sendList, place.title or ( "Send a unit to " .. place.name ) );
end

-- Shift+M (KeyNavSendHere): the send list for the map cursor's plot, any tile. Named by the city, the visible foreign
-- unit (a capturable civilian of an enemy opens the capture list: military units only) or the terrain; an unexplored tile
-- is allowed (Move To works into the fog).
function HubPlaces.SendHere()
	if not HubTargets.CanOpenMode() then return; end
	local x:number, y:number = HubCursor.GetCursor();
	local plot:table = Map.GetPlot( x, y );
	if plot == nil then
		OutputMessageToScreenReader( "Edge of the map" );
		return;
	end
	local name:string = "unexplored tile";
	local capture:boolean = false;
	if PlotDescription_GetVisibility( plot ) ~= "unexplored" then
		local localID:number = Game.GetLocalPlayer();
		local types:table = CapturableTypes();
		local ok:boolean, units = pcall( Units.GetUnitsInPlot, plot );
		local foreign:table = nil;
		for _, unit in ipairs( ( ok and units ) or {} ) do
			if unit:GetOwner() ~= localID and PlotDescription_IsUnitVisible( unit ) then
				foreign = foreign or unit;
				local row:table = GameInfo.Units[ unit:GetUnitType() ];
				if row ~= nil and types[ row.UnitType ] and HubCore.IsHostile( unit:GetOwner() ) then capture = true; foreign = unit; end
			end
		end
		local city:table = plot:IsCity() and Cities.GetCityInPlot( x, y ) or nil;
		if city ~= nil then
			name = Locale.Lookup( city:GetName() );
		elseif foreign ~= nil then
			name = PlotDescription_GetUnitName( foreign );
		else
			local parts:table = {};
			if plot:IsLake() then
				table.insert( parts, "lake" );
			else
				local terrain:table = GameInfo.Terrains[ plot:GetTerrainType() ];
				if terrain ~= nil then table.insert( parts, string.lower( Locale.Lookup( terrain.Name ) ) ); end
			end
			local featureType:number = plot:GetFeatureType();
			local feature:table = ( featureType ~= nil and featureType >= 0 ) and GameInfo.Features[ featureType ] or nil;
			if feature ~= nil then
				local featureName:string = string.lower( Locale.Lookup( feature.Name ) );
				if #parts > 0 and string.find( featureName, parts[#parts], 1, true ) then parts[#parts] = featureName;
				else table.insert( parts, "with " .. featureName ); end
			end
			name = table.concat( parts, " " ) .. " tile";
		end
	end
	HubPlaces.OpenSend( { name = name, x = x, y = y, key = "cursor:" .. plot:GetIndex(), capture = capture, escort = false,
		unexplored = ( PlotDescription_GetVisibility( plot ) == "unexplored" ),
		title = "Send a unit to " .. name } );
end

-- Escape: back to the list the chooser came from.
local function CloseSend()
	local back:string = m_send ~= nil and m_send.back or nil;
	local restore:table = m_return;
	HubCore.CloseMode( false, false );
	if back == "places" and restore ~= nil then
		HubPlaces.Open( restore );
	elseif back == "notifications" then
		HubRegions.ToggleNotifications();
	else
		OutputMessageToScreenReader( "Closed" );
	end
end

-- Gives one unit the move order toward the place through the game's own path (the war check included); the sentence to say.
local function OrderUnit( unitID:number, place:table, item:table )
	local mover:table = LocalPlayer():GetUnits():FindID( unitID );
	local plot:table = Map.GetPlot( place.x, place.y );
	if mover == nil then return "Order not given, the unit is gone"; end
	if plot == nil then return "Order not given, the place is not on the map"; end
	local name:string = Locale.Lookup( mover:GetName() );
	local nearby:boolean = item.nearX ~= nil;
	if nearby then
		plot = Map.GetPlot( item.nearX, item.nearY );
		if plot == nil then return "Order not given, the place is not on the map"; end
	end
	local war:table = HubTargets.WarTargets( mover, plot );
	local enemy:boolean = HubTargets.EnemyVisibleAt( plot );
	local path:table = UnitManager.GetMoveToPathEx( mover, plot:GetIndex() );
	local reachable:boolean = path ~= nil and path.plots ~= nil and #path.plots >= 2;
	if war == nil and not reachable and not place.unexplored then
		return name .. " cannot reach " .. ( nearby and "the area of " or "" ) .. place.name;
	end
	HubTargets.IssueMoveOrder( mover, plot, war, enemy );
	local turns:string = reachable and ( ", " .. HubCore.Plural( path.turns[ #path.turns ] or 1, "turn", "turns" ) ) or "";
	if war ~= nil then
		return name .. " to " .. place.name .. ": the game asks to declare war first";
	end
	if place.escort and reachable then
		local key:string = ( HubEnemies ~= nil and HubEnemies.KeyHint ~= nil ) and HubEnemies.KeyHint( "ExtraHotkeysEnterFormation", "Shift+E", "D-pad right, Create Escort Formation," ) or "Shift+E";
		return HubPlaces.EscortOrderText( name, place.name, path.turns[ #path.turns ] or 1, key );
	end
	return name .. ( enemy and " moving to attack " or ( nearby and " moving next to " or " moving to " ) ) .. place.name .. turns;
end

-- Enter: select the unit (the first one of an attack party) and give the move order(s).
local function SendActivate( item:table )
	local place:table = m_send;
	if item.notice then
		OutputMessageToScreenReader( item.text );
		return;
	end
	local firstId:number = ( item.members ~= nil ) and item.members[1].unitId or item.unitId;
	local unit:table = LocalPlayer():GetUnits():FindID( firstId );
	if unit == nil or place == nil then
		OutputMessageToScreenReader( "Unit no longer available" );
		return;
	end
	HubCore.CloseMode( false, false );
	SelectUnit( unit );
	local turn:number = Game.GetCurrentGameTurn();
	HubCore.After( 0.3, function()
		-- the selection announcement is out; the world may have moved on in the meantime
		local function Refuse( reason:string ) HubCore.SayResult( "Order not given, " .. reason ); end
		if not HubCore.IsLocalPlayerActive() then return; end
		if Game.GetCurrentGameTurn() ~= turn then Refuse( "the turn changed" ); return; end
		if HubTargets.GetTargetMode() ~= nil then Refuse( "a target mode is open" ); return; end
		local sentences:table = {};
		for _, member in ipairs( item.members or { item } ) do
			table.insert( sentences, OrderUnit( member.unitId, place, member ) );
		end
		HubCore.SayResult( table.concat( sentences, ". " ) );
	end );
end

m_sendList = KeyNavList_Create{
	build		= function() return m_send ~= nil and m_send.items or {}; end,
	isActive	= function() return HubCore.IsModeOpen( "send" ); end,
	onActivate	= SendActivate,
	onClose		= CloseSend,
};
