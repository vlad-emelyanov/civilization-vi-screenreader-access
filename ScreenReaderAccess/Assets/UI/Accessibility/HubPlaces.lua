-- ===========================================================================
--	HubPlaces: the places list (J) and "send a unit here" (M), unit activity words.
--	Part of the InGameAccess hub (see docs/ingame-plan.md, Architecture): included by
--	UI/Additions/InGameAccess.lua. State and functions other hub modules use are fields of HubPlaces.
--
--	J opens a keyboard list in categories (empty ones are skipped), every item sorted by distance from the reference plot
--	(the selected unit or city, else the map cursor): your cities, your units (all of them, also automated ones),
--	points of interest (tribal villages, barbarian camps, natural wonders), notifications with a place, foreign cities.
--	Tab / Control+Tab change the category, Up/Down/Home/End move, Space reads the plot, Enter acts, M sends a unit there,
--	Escape closes. Inside a target mode (move to, attack ...) Enter only moves the target cursor and the list closes.
-- ===========================================================================
HubPlaces = {};

HubPlaces.m_hintUnit = -1;		-- unit id picked from the list: its selection announcement says how to cancel its orders
HubPlaces.m_hintTime = -100;

local CANCEL_HINT_SECONDS	:number = 3;
local MAX_SEND_PATHS		:number = 30;		-- units tried with path finding, nearest first
local POINT_IMPROVEMENTS	:table = { IMPROVEMENT_GOODY_HUT = true, IMPROVEMENT_BARBARIAN_CAMP = true };

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
	if Is( "ACTIVITY_SLEEP" ) then return "sleeping"; end
	if Is( "ACTIVITY_HEAL" ) then return "healing"; end
	if activity ~= nil and not awake and unit:GetFortifyTurns() > 0 then return "fortified"; end
	if Is( "ACTIVITY_SENTRY" ) then return "on alert"; end
	if Is( "ACTIVITY_INTERCEPT" ) then return "intercepting"; end
	if Is( "ACTIVITY_HOLD" ) then return "turn skipped"; end
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
		return "exploring";
	end
	if forList and ( awake or activity == nil ) then
		if unit:GetMaxMoves() > 0 and unit:GetMovesRemaining() <= 0 then return "no moves left"; end
		return "needs orders";
	end
	return nil;
end

-- True once for a unit that was just picked from the places list: the selection announcement adds how to cancel its orders.
function HubPlaces.TakeCancelHint( unit:table )
	if HubPlaces.m_hintUnit ~= unit:GetID() then return false; end
	local fresh:boolean = UI.GetElapsedTime() - HubPlaces.m_hintTime < CANCEL_HINT_SECONDS;
	HubPlaces.m_hintUnit = -1;
	return fresh;
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
			local detail:string = PlotDescription_GetShort( plot, {} );
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
		table.insert( items, item );
	end
	return SortItems( items );
end

-- Revealed tribal villages, barbarian camps and natural wonders (a wonder of several plots is listed once).
local function PointItems( ctx:table )
	local items:table = {};
	local vis:table = PlayersVisibility[ Game.GetLocalPlayer() ];
	if vis == nil then return items; end
	local width:number, height:number = Map.GetGridSize();
	local found:table = {};
	for y = 0, height - 1 do
		for x = 0, width - 1 do
			local plot:table = Map.GetPlot( x, y );
			if plot ~= nil and vis:IsRevealed( plot:GetIndex() ) then
				local name:string = nil;
				local feature:number = nil;
				local improvement:number = plot:GetImprovementType();
				if improvement ~= nil and improvement >= 0 then
					local row:table = GameInfo.Improvements[ improvement ];
					if row ~= nil and POINT_IMPROVEMENTS[ row.ImprovementType ] then name = Locale.Lookup( row.Name ); end
				end
				if name == nil then
					local featureType:number = plot:GetFeatureType();
					local row:table = ( featureType ~= nil and featureType >= 0 ) and GameInfo.Features[ featureType ] or nil;
					if row ~= nil and row.NaturalWonder then name, feature = Locale.Lookup( row.Name ), featureType; end
				end
				if name ~= nil then
					local item:table = MakeItem( "p:" .. plot:GetIndex(), "point", name, "", plot, ctx );
					item.feature = feature;
					table.insert( found, item );
				end
			end
		end
	end
	SortItems( found );
	for _, item in ipairs( found ) do
		local duplicate:boolean = false;
		if item.feature ~= nil then
			for _, other in ipairs( items ) do
				if other.feature == item.feature and Map.GetPlotDistance( item.x, item.y, other.x, other.y ) <= 2 then duplicate = true; break; end
			end
		end
		if not duplicate then
			item.text = item.name .. ", " .. Where( Map.GetPlot( item.x, item.y ), ctx );
			table.insert( items, item );
		end
	end
	return items;
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

-- Cities and city-states of others that we have seen.
local function ForeignItems( ctx:table )
	local items:table = {};
	local localID:number = Game.GetLocalPlayer();
	for playerID = 0, 63 do
		local player:table = Players[ playerID ];
		if playerID ~= localID and player ~= nil and player:IsAlive() and not player:IsBarbarian() then
			local civ:string = PlotDescription_GetCivName( playerID );
			for _, city in player:GetCities():Members() do
				local plot:table = Map.GetPlot( city:GetX(), city:GetY() );
				if plot ~= nil and PlotDescription_GetVisibility( plot ) ~= "unexplored" then
					local name:string = Locale.Lookup( city:GetName() );
					local text:string = name;
					if not player:IsMajor() then
						text = text .. ", city-state";
					elseif civ ~= "" and civ ~= name then
						text = text .. ", " .. civ;
					end
					text = text .. ", " .. Where( plot, ctx );
					table.insert( items, MakeItem( "f:" .. playerID .. ":" .. city:GetID(), "foreign", name, text, plot, ctx ) );
				end
			end
		end
	end
	return SortItems( items );
end

-- The categories that have something in them, in this order.
function HubPlaces.BuildCategories( ctx:table )
	local cats:table = {};
	local sources:table = {
		{ name = "Your cities", build = CityItems }, { name = "Your units", build = UnitItems },
		{ name = "Points of interest", build = PointItems }, { name = "Notifications", build = NotificationItems },
		{ name = "Foreign cities", build = ForeignItems },
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
	return cat.name .. ", " .. m_cat .. " of " .. #m_data.cats .. " categories, " .. HubCore.Plural( #cat.items, "item", "items" );
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

local function SwitchCategory( delta:number )
	if m_data == nil then return; end
	m_cat = ( m_cat - 1 + delta ) % #m_data.cats + 1;
	local cat:table = m_data.cats[ m_cat ];
	m_list.Open( "Places", cat.items[1].key, true, true );
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
	HubCore.CloseMode( false, false );
	HubCursor.SetCursor( item.x, item.y, true, true, false, true );
end

local function SendKey()
	local item:table = FocusedItem();
	if item == nil then return; end
	if HubTargets.GetTargetMode() ~= nil then
		OutputMessageToScreenReader( "Enter moves the target there. Escape closes the list" );
		return;
	end
	if item.kind == "unit" then
		OutputMessageToScreenReader( "That is a unit of yours. Enter selects it" );
		return;
	end
	HubPlaces.OpenSend( { name = item.name, x = item.x, y = item.y, back = "places", key = item.key } );
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
		if not found then key = cat.items[1].key; end
		m_list.Open( title, key, true );
		SpeakFocus( title .. ". " .. CategoryHead( cat ) .. ". " );
		if HubTargets.GetTargetMode() ~= nil then OutputMessageToScreenReader( "Enter moves the target there", true ); end
	end,
	Reset = function() m_list.Reset(); end,
	HandleInput = function( input:table ) return m_list.HandleInput( input ); end,
};

m_list = KeyNavList_Create{
	build		= function() return ( m_data ~= nil and m_data.cats[ m_cat ] ~= nil ) and m_data.cats[ m_cat ].items or {}; end,
	isActive	= function() return HubCore.IsModeOpen( "places" ); end,
	onActivate	= ActivateItem,
	onClose		= function() HubCore.CloseMode( true, false ); end,
	extraKeys	= { [Keys.VK_TAB] = function() SwitchCategory( 1 ); end, [Keys.M] = SendKey },
	ctrlKeys	= { [Keys.VK_TAB] = function() SwitchCategory( -1 ); end },
};

-- restore: { cat, key } to come back to a category and item (from the unit chooser)
function HubPlaces.Open( restore:table )
	if not HubTargets.CanOpenMode( true ) then return; end
	local cats:table = HubPlaces.BuildCategories( MakeContext() );
	if #cats == 0 then
		OutputMessageToScreenReader( "No places known yet" );
		return;
	end
	m_data = { cats = cats, ctx = MakeContext() };
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
function HubPlaces.BuildSendItems( place:table )
	local plot:table = Map.GetPlot( place.x, place.y );
	local items:table = {};
	if plot == nil then return items; end
	local candidates:table = {};
	for _, unit in LocalPlayer():GetUnits():Members() do
		if unit:GetMaxMoves() > 0 and not ( unit:GetX() == place.x and unit:GetY() == place.y ) then
			table.insert( candidates, { unit = unit, distance = Map.GetPlotDistance( unit:GetX(), unit:GetY(), place.x, place.y ) } );
		end
	end
	table.sort( candidates, function( a, b )
		if a.distance ~= b.distance then return a.distance < b.distance; end
		return a.unit:GetID() < b.unit:GetID();
	end );
	local names:table = {};
	for i = 1, math.min( MAX_SEND_PATHS, #candidates ) do
		local unit:table = candidates[i].unit;
		local path:table = UnitManager.GetMoveToPathEx( unit, plot:GetIndex() );
		if path ~= nil and path.plots ~= nil and #path.plots >= 2 then
			local turns:number = path.turns[ #path.turns ] or 1;
			local name:string = Locale.Lookup( unit:GetName() );
			names[ name ] = ( names[ name ] or 0 ) + 1;
			table.insert( items, { key = "s:" .. unit:GetID(), unitId = unit:GetID(), name = name, turns = turns, distance = candidates[i].distance, unit = unit } );
		end
	end
	table.sort( items, function( a, b )
		if a.turns ~= b.turns then return a.turns < b.turns; end
		if a.distance ~= b.distance then return a.distance < b.distance; end
		return a.unitId < b.unitId;
	end );
	for _, item in ipairs( items ) do
		item.text = item.name .. ", " .. HubCore.Plural( item.turns, "turn", "turns" );
		local activity:string = HubPlaces.UnitActivity( item.unit, false );
		if activity ~= nil then item.text = item.text .. ", " .. activity; end
		if names[ item.name ] > 1 then
			local position:string = HubAnnounce.PositionText( Map.GetPlot( item.unit:GetX(), item.unit:GetY() ) );
			if position ~= nil then item.text = item.text .. ", " .. position; end
		end
		local unitPlot:table = Map.GetPlot( item.unit:GetX(), item.unit:GetY() );
		item.detail = function() return PlotDescription_GetShort( unitPlot, {} ); end
		item.unit = nil;
	end
	return items;
end

function HubPlaces.OpenSend( place:table )
	if not HubTargets.CanOpenMode() then return; end
	local items:table = HubPlaces.BuildSendItems( place );
	if #items == 0 then
		OutputMessageToScreenReader( "No unit can reach it" );
		return;
	end
	m_return = nil;
	if place.back == "places" and m_data ~= nil then m_return = { cat = m_cat, key = place.key }; end
	place.items = items;
	m_send = place;
	HubCore.OpenMode( "send", m_sendList, "Send a unit to " .. place.name );
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

-- Enter: select the unit and give it the move order through the game's own path (the war check included).
local function SendActivate( item:table )
	local place:table = m_send;
	local unit:table = LocalPlayer():GetUnits():FindID( item.unitId );
	if unit == nil or place == nil then
		OutputMessageToScreenReader( "Unit no longer available" );
		return;
	end
	HubCore.CloseMode( false, false );
	SelectUnit( unit );
	local unitID:number = unit:GetID();
	local turn:number = Game.GetCurrentGameTurn();
	HubCore.After( 0.3, function()
		-- the selection announcement is out; the world may have moved on in the meantime
		if Game.GetCurrentGameTurn() ~= turn or not HubCore.IsLocalPlayerActive() or HubTargets.GetTargetMode() ~= nil then return; end
		local mover:table = LocalPlayer():GetUnits():FindID( unitID );
		local plot:table = Map.GetPlot( place.x, place.y );
		if mover == nil or plot == nil then return; end
		local name:string = Locale.Lookup( mover:GetName() );
		local war:table = HubTargets.WarTargets( mover, plot );
		local enemy:boolean = HubTargets.EnemyVisibleAt( plot );
		local path:table = UnitManager.GetMoveToPathEx( mover, plot:GetIndex() );
		local reachable:boolean = path ~= nil and path.plots ~= nil and #path.plots >= 2;
		if war == nil and not reachable then
			HubCore.SayResult( name .. " cannot reach " .. place.name );
			return;
		end
		HubTargets.IssueMoveOrder( mover, plot, war, enemy );
		local turns:string = reachable and ( ", " .. HubCore.Plural( path.turns[ #path.turns ] or 1, "turn", "turns" ) ) or "";
		if war ~= nil then
			HubCore.SayResult( name .. " to " .. place.name .. ": the game asks to declare war first" );
		else
			HubCore.SayResult( name .. ( enemy and " moving to attack " or " moving to " ) .. place.name .. turns );
		end
	end );
end

m_sendList = KeyNavList_Create{
	build		= function() return m_send ~= nil and m_send.items or {}; end,
	isActive	= function() return HubCore.IsModeOpen( "send" ); end,
	onActivate	= SendActivate,
	onClose		= CloseSend,
};
