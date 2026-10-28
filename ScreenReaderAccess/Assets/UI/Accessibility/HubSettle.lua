-- ===========================================================================
--	HubSettle: settle spot browser (X with a settler), tile browser (X with a builder) and action tile browser
--	(X with a great person, archaeologist, naturalist or rock band).
--	Part of the InGameAccess hub (see docs/ingame-plan.md, Architecture): included by
--	UI/Additions/InGameAccess.lua. State and functions other hub modules use are fields of HubSettle.
-- ===========================================================================
HubSettle = {};

include( "BuildScan" );		-- builder: tiles of a city that can be improved

local m_settleItems			:table = {};		-- its items, from the scan made when it opened

-- ===========================================================================
--	SETTLE SPOT BROWSER (X with a settler selected): candidates from SettleScan, best first
-- ===========================================================================
local m_settleList:table;

-- Browsing moved the cursor over the candidates: back to the settler (not when the mode went stale).
local function SettleClosed( quiet:boolean )
	if quiet then return; end
	local unit:table = UI.GetHeadSelectedUnit();
	if unit ~= nil then HubCursor.SetCursor( unit:GetX(), unit:GetY(), false ); end
end

local function BuildSettleItems()
	return m_settleItems;
end

-- "2 tiles north-east, 1 turn, river, coast, silk, recommended, 4 tiles from Rome, 7 from Kyoto (Japan)" / "Here, river, wine"
local function SettleItemText( c:table )
	local text:string = c.here and "Here" or ( c.relative .. ", " .. HubCore.Plural( c.turns, "turn", "turns" ) );
	text = text .. HubCore.SettleReasons( c, 3, 2 );
	if c.recommended then text = text .. ", recommended"; end
	return text .. SettleScan_DistanceText( c );
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
	HubCore.OpenMode( "settle", m_settleList, "Settle spots", SettleClosed );
end

-- Enter on a spot: the settler walks there (the same path as the move-to mode), or on the spot it stands on: B founds.
local function SettleGo( item:table )
	local unit:table = UI.GetHeadSelectedUnit();
	HubCore.CloseMode( false, false );
	if not HubCore.IsSettler( unit ) then
		HubCore.SayResult( "No settler selected" );
		return;
	end
	local c:table = item.candidate;
	local plot:table = Map.GetPlotByIndex( c.plotIndex );
	local ok:boolean, extra = SettleScan_CanFound( unit, plot );
	if c.here or ( unit:GetX() == c.x and unit:GetY() == c.y ) then
		if not ok then
			HubCore.SayResult( "Cannot settle here" .. ( ( extra ~= nil and extra ~= "" ) and ( ": " .. extra ) or "" ) );
		elseif extra == true then
			HubCore.SayResult( SRKey( "B", "D-pad right, Found City," ) .. " to found next turn" );
		else
			HubCore.SayResult( SRKey( "B", "D-pad right, Found City," ) .. " to found the city here" );
		end
		return;
	end
	if not ok then
		HubCore.SayResult( "Cannot settle there any more" .. ( ( extra ~= nil and extra ~= "" ) and ( ": " .. extra ) or "" ) );
		return;
	end
	local war:table = HubTargets.WarTargets( unit, plot );
	local path:table = UnitManager.GetMoveToPathEx( unit, plot:GetIndex() );
	if war == nil and ( path == nil or path.plots == nil or #path.plots < 2 ) then
		local why:string = HubTargets.UnreachableReason( unit, plot );
		HubCore.SayResult( "Unreachable" .. ( why ~= "" and ( ": " .. why ) or "" ) );
		return;
	end
	HubTargets.IssueMoveOrder( unit, plot, war, false );
end

m_settleList = KeyNavList_Create{
	build		= BuildSettleItems,
	isActive	= function() return HubCore.IsModeOpen( "settle" ); end,
	onActivate	= SettleGo,
	onClose		= function() HubCore.CloseMode( true, false ); end,
	onFocus		= function( item ) HubCursor.SetCursor( item.candidate.x, item.candidate.y, false, nil, true ); end,
};

-- ===========================================================================
--	TILE BROWSER (X with a builder selected): the tiles of one city the builder can improve, from BuildScan.
--	Left/Right switch to the next/previous own city (nearest to the builder first).
-- ===========================================================================
local m_buildList:table;
local DANGER_RADIUS:number = 2;			-- a visible hostile soldier this close to a target tile marks it dangerous
local m_dangerGuard:table = { turn = -1, warnSig = nil, warnTime = 0, confirmSig = nil };		-- two-step Enter on a dangerous tile
HubSettle.m_pending = nil;		-- { unitId, plotIndex, type, name, keepOnKeys }: the improvement chosen with the order, built by Enter on arrival
local m_build:table = { cities = {}, index = 1, items = {}, unitId = nil, nowCount = 0, laterCount = 0 };

-- Browsing moved the cursor over the tiles: back to the builder (not when the mode went stale).
local function BuildClosed( quiet:boolean )
	if quiet then return; end
	local unit:table = UI.GetHeadSelectedUnit();
	if unit ~= nil then HubCursor.SetCursor( unit:GetX(), unit:GetY(), false ); end
end

-- "Mine plus 1 production" / "pillaged Farm, repair"
local function BuildImprovementText( improvement:table )
	if improvement.repair then return improvement.name .. ", repair"; end
	return improvement.name .. ( improvement.yieldText ~= "" and ( " " .. improvement.yieldText ) or "" );
end

-- "Mine plus 1 production, or Farm plus 1 food, and 1 more" (two named at most)
local function BuildImprovementsText( entry:table )
	local parts:table = {};
	for i, improvement in ipairs( entry.improvements ) do
		if i > 2 then
			table.insert( parts, "and " .. ( #entry.improvements - 2 ) .. " more" );
			break;
		end
		local text:string = BuildImprovementText( improvement );
		table.insert( parts, ( i == 2 ) and ( "or " .. text ) or text );
	end
	return table.concat( parts, ", " );
end

-- Pure: "danger: Barbarian Man-At-Arms 1 tile away" / "... on the tile"
function HubSettle.DangerItemText( enemyName:string, distance:number )
	if distance <= 0 then return "danger: " .. enemyName .. " on the tile"; end
	return "danger: " .. enemyName .. " " .. HubCore.Plural( distance, "tile", "tiles" ) .. " away";
end

-- Pure: "Danger: Barbarian Man-At-Arms 1 tile from Wheat. Enter again sends it anyway"
function HubSettle.DangerGuardText( enemyName:string, distance:number, tileName:string )
	local where:string = ( distance <= 0 ) and ( "on " .. tileName ) or ( HubCore.Plural( distance, "tile", "tiles" ) .. " from " .. tileName );
	return "Danger: " .. enemyName .. " " .. where .. ". " .. SRKey( "Enter" ) .. " again sends it anyway";
end

-- Pure: said on arrival of a builder that was sent to build. hasMoves false: the build waits for the next turn.
-- selected false: the builder is not the selected unit.
function HubSettle.ArrivalBuildText( improvement:string, hasMoves:boolean, selected:boolean )
	if not selected then return "Select it and press " .. SRKey( "Enter" ) .. " to build " .. improvement; end
	if not hasMoves then return improvement .. " can be built next turn: select it and press " .. SRKey( "Enter" ); end
	return SRKey( "Enter" ) .. " builds " .. improvement;
end

-- Visible hostile land soldiers (no scouts, no ships): { name, x, y, key }.
function HubSettle.VisibleHostileSoldiers()
	local list:table = {};
	local localID:number = Game.GetLocalPlayer();
	if localID == nil or localID == -1 then return list; end
	for id = 0, 63 do
		if id ~= localID and Players[ id ] ~= nil and HubCore.IsHostile( id ) then
			for _, unit in Players[ id ]:GetUnits():Members() do
				if ( unit:GetCombat() > 0 or unit:GetRangedCombat() > 0 ) and PlotDescription_IsUnitVisible( unit )
						and not HubEnemies.IsBarbarianScout( unit ) and not HubEnemies.IsNaval( unit ) then
					table.insert( list, { name = PlotDescription_GetUnitName( unit ), x = unit:GetX(), y = unit:GetY(), key = id .. ":" .. unit:GetID() } );
				end
			end
		end
	end
	return list;
end

-- The nearest hostile soldier within radius tiles of the plot, as { name, distance, key } or nil (hostiles: optional, from the above).
function HubSettle.DangerAt( plot:table, radius:number, hostiles:table )
	if plot == nil or HubEnemies == nil then return nil; end
	local best:table = nil;
	for _, h in ipairs( hostiles or HubSettle.VisibleHostileSoldiers() ) do
		local d:number = Map.GetPlotDistance( plot:GetX(), plot:GetY(), h.x, h.y );
		if d <= radius and ( best == nil or d < best.distance ) then best = { name = h.name, distance = d, key = h.key }; end
	end
	return best;
end

-- Pure: the item starts with what tells it apart (the improvement and its yield), then where, then the tile, then turns and status:
-- "Farm plus 1 food, 2 tiles north-east, Wheat, 1 turn, worked" / "Farm plus 1 food, here, Wheat"
function HubSettle.BuildItemTextOf( entry:table, improvements:string, dangerText:string )
	local tile:string = string.gsub( entry.name, ", ", " " );
	local text:string = improvements;
	if entry.here then
		text = text .. ", here, " .. tile;
	else
		text = text .. ", " .. entry.relative .. ", " .. tile .. ", " .. HubCore.Plural( entry.turns or 0, "turn", "turns" );
	end
	if entry.worked then text = text .. ", worked"; end
	if dangerText ~= nil then text = text .. ", " .. dangerText; end
	return text;
end

local function BuildItemText( entry:table )
	local danger:string = nil;
	if entry.danger ~= nil then danger = HubSettle.DangerItemText( entry.danger.name, entry.danger.distance ); end
	return HubSettle.BuildItemTextOf( entry, BuildImprovementsText( entry ), danger );
end

local function BuildItemDetail( entry:table )
	local all:table = {};
	for _, improvement in ipairs( entry.improvements ) do table.insert( all, BuildImprovementText( improvement ) ); end
	return PlotDescription_GetShort( entry.plot ) .. ". Can build: " .. table.concat( all, "; " );
end

-- "Later: Iron near Rome, Mine needs Bronze Working" (G1)
local function LaterItemText( tile:table, cityName:string )
	return "Later: " .. tile.name .. " near " .. cityName .. ", " .. tile.improvement .. " needs " .. tile.needName;
end

local function LaterItemDetail( tile:table )
	local text:string = PlotDescription_GetShort( tile.plot ) .. ". Later: " .. tile.improvement .. " needs " .. tile.needName;
	if tile.turns ~= nil then text = text .. ", " .. HubCore.Plural( tile.turns, "turn", "turns" ) .. " of research"; end
	return text;
end

-- Scans the city at m_build.index and fills m_build.items: the tiles to improve now, then the "Later" tiles
-- (m_build.nowCount / m_build.laterCount say how many of each).
local function LoadBuildItems( unit:table, force:boolean )
	m_build.items = {};
	m_build.nowCount, m_build.laterCount = 0, 0;
	local entry:table = m_build.cities[ m_build.index ];
	if entry == nil then return; end
	local scan:table = BuildScan_Scan( unit, entry.city, force );
	local okHostiles:boolean, hostiles = pcall( HubSettle.VisibleHostileSoldiers );
	if not okHostiles then hostiles = {}; end
	for _, tile in ipairs( scan.list ) do
		tile.danger = nil;
		if not tile.here and #hostiles > 0 then
			local okDanger:boolean, danger = pcall( HubSettle.DangerAt, tile.plot, DANGER_RADIUS, hostiles );
			if okDanger then tile.danger = danger; end
		end
		table.insert( m_build.items, { key = tile.key, text = BuildItemText( tile ), detail = BuildItemDetail( tile ), entry = tile } );
	end
	m_build.nowCount = #m_build.items;
	for _, tile in ipairs( scan.later or {} ) do
		table.insert( m_build.items, { key = tile.key, text = LaterItemText( tile, entry.name ), detail = LaterItemDetail( tile ), entry = tile } );
	end
	m_build.laterCount = #m_build.items - m_build.nowCount;
end

-- "3 tiles" / "2 tiles, 1 later"
local function BuildCountText()
	local text:string = HubCore.Plural( m_build.nowCount, "tile", "tiles" );
	if m_build.laterCount > 0 then text = text .. ", " .. m_build.laterCount .. " later"; end
	return text;
end

local function OpenBuildBrowser( unit:table )
	if unit:GetMovesRemaining() <= 0 then
		OutputMessageToScreenReader( Locale.Lookup( unit:GetName() ) .. " has no moves left" );
		return;
	end
	m_build.cities = BuildScan_Cities( unit );
	if #m_build.cities == 0 then
		OutputMessageToScreenReader( "No city to improve tiles for" );
		return;
	end
	local default:table = BuildScan_DefaultCity( unit );
	m_build.index = 1;
	for i, entry in ipairs( m_build.cities ) do
		if default ~= nil and entry.city:GetID() == default:GetID() then m_build.index = i; end
	end
	m_build.unitId = unit:GetID();
	LoadBuildItems( unit, true );		-- the player asked: look again
	local city:table = m_build.cities[ m_build.index ];
	if #m_build.items == 0 then
		-- the nearest city has nothing: open anyway when another city has something (Left/Right), else say so
		local other:boolean = false;
		for i, entry in ipairs( m_build.cities ) do
			if i ~= m_build.index and #BuildScan_Scan( unit, entry.city, true ).list > 0 then other = true; break; end
		end
		if not other then
			OutputMessageToScreenReader( "Nothing to improve near your cities" );
			return;
		end
		HubCore.CloseMode( false, false );
		HubCore.m_mode = { name = "build", list = m_buildList, onClose = BuildClosed };
		m_buildList.Reset();
		OutputMessageToScreenReader( city.name .. ", nothing to improve. " .. SRKey( "Left and Right" ) .. " for other cities" );
		return;
	end
	HubCore.CloseMode( false, false );
	HubCore.m_mode = { name = "build", list = m_buildList, onClose = BuildClosed };
	m_buildList.Reset();
	m_buildList.Open( "", nil, true );		-- silent: only puts the focus on the first tile
	m_buildList.Focus( m_build.items[1].key, "Tiles to improve near " .. city.name .. ", " .. BuildCountText() );
end

-- Left/Right: the next / previous city.
local function SwitchBuildCity( delta:number )
	if not HubCore.IsModeOpen( "build" ) then return; end
	local unit:table = UI.GetHeadSelectedUnit();
	local count:number = #m_build.cities;
	if unit == nil or unit:GetID() ~= m_build.unitId or BuildScan_Improvements( unit ) == nil then
		HubCore.CloseMode( false, true );
		HubCore.SayResult( "Builder no longer selected" );
		return;
	end
	if count <= 1 then
		OutputMessageToScreenReader( "Only one city" );
		return;
	end
	m_build.index = ( m_build.index - 1 + delta ) % count + 1;
	LoadBuildItems( unit );
	m_buildList.Reset();
	local city:table = m_build.cities[ m_build.index ];
	if #m_build.items == 0 then
		OutputMessageToScreenReader( city.name .. ", nothing to improve" );
		return;
	end
	m_buildList.Focus( m_build.items[1].key, city.name .. ", " .. BuildCountText() .. " to improve" );
end

-- A visible hostile soldier near the target: the first Enter only warns (the list stays open), the second sends the unit.
-- Returns true when it warned (the caller returns).
local function DangerWarned( unit:table, plotIndex:number, tileName:string )
	local okDanger:boolean, danger = pcall( HubSettle.DangerAt, Map.GetPlotByIndex( plotIndex ), DANGER_RADIUS );
	if not ( okDanger and danger ~= nil ) then return false; end
	local sig:string = unit:GetID() .. ":" .. plotIndex .. ":" .. danger.key;
	if HubEnemies.GuardDecision( m_dangerGuard, Game.GetCurrentGameTurn(), sig, UI.GetElapsedTime() ) == "warn" then
		HubCore.SayResult( HubSettle.DangerGuardText( danger.name, danger.distance, tileName ) );
		return true;
	end
	return false;
end

-- Enter: on the builder's own tile the unit actions menu (it lists the build actions), elsewhere the builder walks there
-- (the same path as the move-to mode).
local function BuildGo( item:table )
	local unit:table = UI.GetHeadSelectedUnit();
	if item.entry.later then
		-- the cursor is already there (onFocus); the tile cannot be improved yet
		local actionName:string = ( item.entry.needKind == "civic" ) and "ToggleCivicsTree" or "ToggleTechTree";
		local id = Input.GetActionId( actionName );
		local key = ( id ~= nil ) and Input.GetGestureDisplayString( id, 0 ) or nil;
		local hint:string = ( key ~= nil and key ~= "" ) and ( ". " .. key .. " opens the " .. ( item.entry.needKind == "civic" and "civics" or "tech" ) .. " tree" ) or "";
		OutputMessageToScreenReader( "Not yet: needs " .. item.entry.needName .. hint );
		return;
	end
	local tile:table = item.entry;
	if unit ~= nil and unit:GetID() == m_build.unitId and BuildScan_Improvements( unit ) ~= nil
			and not ( tile.here or ( unit:GetX() == tile.x and unit:GetY() == tile.y ) ) then
		if DangerWarned( unit, tile.plotIndex, tile.name ) then return; end
	end
	HubCore.CloseMode( false, false );
	if unit == nil or unit:GetID() ~= m_build.unitId or BuildScan_Improvements( unit ) == nil then
		HubCore.SayResult( "Builder no longer selected" );
		return;
	end
	if tile.here or ( unit:GetX() == tile.x and unit:GetY() == tile.y ) then
		HubMenus.ToggleUnitMenu();
		return;
	end
	local plot:table = Map.GetPlotByIndex( tile.plotIndex );
	local war:table = HubTargets.WarTargets( unit, plot );
	local path:table = UnitManager.GetMoveToPathEx( unit, plot:GetIndex() );
	if war == nil and ( path == nil or path.plots == nil or #path.plots < 2 ) then
		local why:string = HubTargets.UnreachableReason( unit, plot );
		HubCore.SayResult( "Unreachable" .. ( why ~= "" and ( ": " .. why ) or "" ) );
		return;
	end
	HubTargets.IssueMoveOrder( unit, plot, war, false );
	-- remember what to build on arrival (HubEvents.OnUnitMoveComplete says "Enter builds ...")
	local record:table = HubCore.m_movers[ unit:GetID() ];
	local first:table = tile.improvements ~= nil and tile.improvements[1] or nil;
	HubSettle.m_pending = nil;
	if record ~= nil and war == nil and first ~= nil and not first.repair then
		record.build = { type = first.type, name = first.name, hash = first.hash };
	end
end

-- Pure: the arrival sentence when the improvement chosen with the order is no longer possible on the tile.
function HubSettle.ArrivalStaleText( improvement:string, reason:string )
	local text:string = improvement .. " is no longer possible here";
	if reason ~= nil and reason ~= "" then text = text .. ": " .. reason; end
	return text .. ". " .. SRKey( "X", "X" ) .. " lists other tiles";
end

-- Why the improvement chosen with the order cannot be built now (nil: it can, or the check is not possible). A selected unit
-- is asked the way RunArmedBuild asks (its unit actions menu), else the build scan.
function HubSettle.ArmedBuildProblem( unit:table, plot:table, b:table, selected:boolean )
	-- A water tile (Fishing Boats, Offshore Platform) or an embarked builder: at the moment of arrival the unit actions and the build
	-- scan have not caught up with the embark state (the play-test saw "no longer possible" and then Tab offered and built it).
	-- Unknown counts as possible; the Enter path reports a real failure.
	local okWater:boolean, water = pcall( function() return plot:IsWater() or unit:IsEmbarked() == true; end );
	if okWater and water then return nil; end
	if selected and b.type ~= nil then
		local okMenu:boolean, items = pcall( HubMenus.FetchMenuItems, true );
		if okMenu and items ~= nil then
			for _, menuItem in ipairs( items ) do
				if menuItem.action ~= nil and menuItem.action.improvement == b.type then
					if menuItem.choosable == false then return menuItem.reason or ""; end
					return nil;
				end
			end
			return "";
		end
	end
	if b.hash ~= nil and not BuildScan_CanBuild( unit, plot, b ) then
		local district:number = plot:GetDistrictType();
		if district ~= nil and district >= 0 then return "a district stands there"; end
		return "";
	end
	return nil;
end

-- Called by HubEvents when a unit with a move order arrives: the sentence to append ("Enter builds Farm") or nil. Arms Enter.
function HubSettle.OnArrived( unit:table, plot:table, record:table )
	HubSettle.m_pending = nil;
	local b:table = record ~= nil and record.build or nil;
	if b == nil or unit == nil or plot == nil then return nil; end
	local head:table = UI.GetHeadSelectedUnit();
	local selected:boolean = head ~= nil and head:GetID() == unit:GetID();
	local hasMoves:boolean = unit:GetMovesRemaining() > 0;
	if hasMoves and b.hash ~= nil then
		local why:string = HubSettle.ArmedBuildProblem( unit, plot, b, selected );
		if why ~= nil then return HubSettle.ArrivalStaleText( b.name, why ); end
	end
	HubSettle.m_pending = { unitId = unit:GetID(), plotIndex = plot:GetIndex(), type = b.type, name = b.name, turn = Game.GetCurrentGameTurn(),
		keepOnKeys = not ( hasMoves and selected ), act = b.act };
	if b.act ~= nil then return HubSettle.ArrivalActionText( b.act, hasMoves, selected ); end
	return HubSettle.ArrivalBuildText( b.name, hasMoves, selected );
end

-- Any other key (not Enter, not a modifier) cancels the arming made on arrival; one armed for later (no moves, not selected) stays.
function HubSettle.OnOtherKey( key:number )
	local pending:table = HubSettle.m_pending;
	if pending ~= nil and not pending.keepOnKeys and key ~= Keys.VK_SHIFT and key ~= Keys.VK_CONTROL and key ~= Keys.VK_ALT then
		HubSettle.m_justCleared = { pending = pending, time = UI.GetElapsedTime() };
		HubSettle.m_pending = nil;
	end
	m_dangerGuard.warnSig = nil;
end

-- N (the Next Action question) is not an order: the input action fires after the raw key handler above has cleared the arming, so give it back.
function HubSettle.RestoreJustCleared()
	local j:table = HubSettle.m_justCleared;
	HubSettle.m_justCleared = nil;
	if j ~= nil and HubSettle.m_pending == nil and UI.GetElapsedTime() - j.time < 0.5 then HubSettle.m_pending = j.pending; end
end

-- Any other operation or command started for the pending unit (HubEvents calls this): the choice is stale.
function HubSettle.OnUnitOrder( ownerID:number, unitID:number )
	local p:table = HubSettle.m_pending;
	if p ~= nil and p.unitId == unitID and ownerID == Game.GetLocalPlayer() then HubSettle.m_pending = nil; end
end

-- Is Enter going to build? The pending builder is selected, stands on the tile and has moves.
function HubSettle.BuildEnterArmed()
	local p:table = HubSettle.m_pending;
	if p == nil then return false; end
	local unit:table = UI.GetHeadSelectedUnit();
	if unit == nil or unit:GetID() ~= p.unitId then return false; end
	-- the player's announced focus moved on to another unit (the head selection may lag behind): not this builder's build
	if HubCore.m_lastAnnouncedUnit ~= nil and HubCore.m_lastAnnouncedUnit ~= p.unitId then return false; end
	if p.turn ~= nil and Game.GetCurrentGameTurn() > p.turn + 1 then HubSettle.m_pending = nil; return false; end
	if UnitManager.GetQueuedDestination( unit ) ~= nil then HubSettle.m_pending = nil; return false; end
	local plot:table = Map.GetPlot( unit:GetX(), unit:GetY() );
	if plot == nil or plot:GetIndex() ~= p.plotIndex then HubSettle.m_pending = nil; return false; end
	return unit:GetMovesRemaining() > 0;
end

-- Pure: what N says while Enter is armed. unitName may be nil.
function HubSettle.ArmedTextFor( p:table, unitName:string )
	if p.act ~= nil then return SRKey( "Enter" ) .. " " .. HubSettle.ActionPhrase( p.act ); end
	return SRKey( "Enter" ) .. " builds " .. p.name .. ( ( unitName ~= nil and unitName ~= "" ) and ( " with the " .. unitName ) or "" );
end

function HubSettle.ArmedEnterText()
	local p:table = HubSettle.m_pending;
	if p == nil then return nil; end
	local unit:table = UI.GetHeadSelectedUnit();
	local name:string = nil;
	if unit ~= nil then
		local ok:boolean, n = pcall( PlotDescription_GetUnitName, unit );
		if ok then name = n; end
	end
	return HubSettle.ArmedTextFor( p, name );
end

-- Enter (armed): the same code path as the Tab menu item of that improvement (UnitPanel's own button callback).
function HubSettle.RunArmedBuild()
	local p:table = HubSettle.m_pending;
	HubSettle.m_pending = nil;
	local unit:table = UI.GetHeadSelectedUnit();
	if p == nil or unit == nil then return; end
	if p.act ~= nil then HubSettle.RunAction( unit, p.act ); return; end
	local found:table = nil;
	for _, menuItem in ipairs( HubMenus.FetchMenuItems( true ) ) do
		if menuItem.action.improvement == p.type then found = menuItem; end
	end
	if found == nil then
		HubCore.SayResult( "Cannot build " .. p.name .. " here" );
	elseif found.choosable == false then
		HubCore.SayResult( "Cannot build " .. p.name .. ": " .. found.reason );
	else
		LuaEvents.SRA_RunUnitAction( found.action.id, unit:GetID() );		-- the build announces itself (UnitOperationStarted)
	end
end

m_buildList = KeyNavList_Create{
	build		= function() return m_build.items; end,
	isActive	= function() return HubCore.IsModeOpen( "build" ); end,
	onActivate	= BuildGo,
	onClose		= function() HubCore.CloseMode( true, false ); end,
	onFocus		= function( item ) HubCursor.SetCursor( item.entry.x, item.entry.y, false, nil, true ); end,
	extraKeys	= {
		[ Keys.VK_LEFT ]	= function() SwitchBuildCity( -1 ); end,
		[ Keys.VK_RIGHT ]	= function() SwitchBuildCity( 1 ); end,
	},
};

-- ===========================================================================
--	ACTION TILE BROWSER (X with a great person, archaeologist, naturalist or rock band selected):
--	the tiles the game highlights for the unit's action (M6). Enter goes there, then Enter activates.
-- ===========================================================================
local m_actList:table;
local m_act:table = { items = {}, unitId = nil, act = nil };
local ACT_TURN_LIMIT:number = 15;		-- paths (turns to reach) are computed for the nearest tiles only; a big list (Galileo: 137) says distance
-- operation / command types the action runs as, in the Tab menu
local ACT_TYPES:table = { "ACTIVATE_GREAT_PERSON", "FOUND_RELIGION", "EXCAVATE", "DESIGNATE_PARK", "TOURISM_BOMB" };
local ACT_SILENT:table = { UNITOPERATION_FOUND_RELIGION = true };		-- opens a screen / notification that announces itself

-- Pure: "activates Euclid" / "excavates" / "designates a national park"
function HubSettle.ActionPhrase( a:table )
	return a.verb3 .. ( ( a.what ~= nil and a.what ~= "" ) and ( " " .. a.what ) or "" );
end

-- Pure: "activate Euclid"
function HubSettle.ActionInfinitive( a:table )
	return a.verb .. ( ( a.what ~= nil and a.what ~= "" ) and ( " " .. a.what ) or "" );
end

-- Pure: said on arrival of a unit that was sent to act. hasMoves false: the action waits for the next turn.
-- selected false: the unit is not the selected unit.
function HubSettle.ArrivalActionText( a:table, hasMoves:boolean, selected:boolean )
	if not selected then return "Select it and press " .. SRKey( "Enter" ) .. " to " .. HubSettle.ActionInfinitive( a ); end
	if not hasMoves then
		local text:string = HubSettle.ActionInfinitive( a ) .. " next turn: select it and press " .. SRKey( "Enter" );
		return string.upper( string.sub( text, 1, 1 ) ) .. string.sub( text, 2 );
	end
	return SRKey( "Enter" ) .. " " .. HubSettle.ActionPhrase( a );
end

-- Pure: "Rome's Campus, 3 tiles north-east, 2 turns, 1 tile north of Rome" / "here, Rome's Campus, Enter activates Euclid"
function HubSettle.ActItemText( e:table, a:table )
	if e.here then return "here, " .. e.name .. ", " .. SRKey( "Enter" ) .. " " .. HubSettle.ActionPhrase( a ); end
	local parts:table = { e.name };
	if e.relative ~= nil then table.insert( parts, e.relative ); end
	if e.turns ~= nil then table.insert( parts, HubCore.Plural( e.turns, "turn", "turns" ) ); end
	if e.position ~= nil then table.insert( parts, e.position ); end
	return table.concat( parts, ", " );
end

local function FlatPlots( list )
	local result:table = {};
	if type( list ) ~= "table" then return result; end
	for _, index in ipairs( list ) do table.insert( result, index ); end
	return result;
end

-- Plot indexes of the completed, unpillaged districts of a type (unique replacements count), as SRNearestDistrict in UnitPanel.
local function CompletedDistrictPlots( ownerID:number, districtRow:table )
	local accepted:table = { [ districtRow.Index ] = true };
	for replace in GameInfo.DistrictReplaces() do
		if replace.ReplacesDistrictType == districtRow.DistrictType and GameInfo.Districts[ replace.CivUniqueDistrictType ] ~= nil then
			accepted[ GameInfo.Districts[ replace.CivUniqueDistrictType ].Index ] = true;
		end
	end
	local result:table = {};
	for _, district in Players[ ownerID ]:GetDistricts():Members() do
		if accepted[ district:GetType() ] and district:IsComplete() then
			local pillaged:boolean = false;
			pcall( function() pillaged = district:IsPillaged(); end );
			local plot:table = Map.GetPlot( district:GetX(), district:GetY() );
			if not pillaged and plot ~= nil then table.insert( result, plot:GetIndex() ); end
		end
	end
	return result;
end

-- What the selected unit can act on: nil for a unit without such an ability (X keeps its old meaning), else
-- { kind, verb, verb3, what, plots = { plot index ... }, empty = "why there is nothing" }.
function HubSettle.ActivationPlots( unit:table )
	if unit == nil or unit:GetOwner() ~= Game.GetLocalPlayer() then return nil; end
	local result:table = nil;
	local ok:boolean, err = pcall( function()
		local row:table = GameInfo.Units[ unit:GetUnitType() ];
		if row == nil then return; end
		local owner:number = unit:GetOwner();
		if row.ExtractsArtifacts == true then
			result = { kind = "archaeologist", verb = "excavate", verb3 = "excavates", what = "", empty = "No antiquity sites revealed",
				plots = FlatPlots( unit:GetArchaeology():GetActivationHighlightPlots() ) };
		elseif row.ParkCharges ~= nil and row.ParkCharges > 0 and unit:GetParkCharges() > 0 then
			result = { kind = "naturalist", verb = "designate", verb3 = "designates", what = "a national park", empty = "No place for a national park",
				plots = FlatPlots( Game.GetNationalParks():GetPossibleParkTiles( owner ) ) };
		elseif row.UnitType == "UNIT_ROCK_BAND" then
			result = { kind = "rock band", verb = "perform", verb3 = "performs", what = "", empty = "No tile to perform on",
				plots = FlatPlots( unit:GetRockBand():GetActivationHighlightPlots() ) };
		else
			local gp = unit:GetGreatPerson();
			local individual:number = ( gp ~= nil ) and gp:GetIndividual() or -1;
			local gpRow:table = ( individual ~= nil and individual >= 0 ) and GameInfo.GreatPersonIndividuals[ individual ] or nil;
			if gpRow == nil then return; end
			local districtRow:table = ( gpRow.ActionRequiresCompletedDistrictType ~= nil ) and GameInfo.Districts[ gpRow.ActionRequiresCompletedDistrictType ] or nil;
			local highlight:boolean = gpRow.ActionEffectTileHighlighting == true;
			if not highlight and districtRow == nil then return; end		-- works anywhere: nothing to browse
			local name:string = Locale.Lookup( unit:GetName() );
			local retire:boolean = gpRow.ActionNameTextOverride == "LOC_GREATPERSON_ACTION_NAME_RETIRE";
			result = { kind = "great person", verb = retire and "retire" or "activate", verb3 = retire and "retires" or "activates", what = name,
				empty = "No tile to use " .. name .. " on", plots = {} };
			-- the game uses the highlighted tiles only when the flag is set
			if highlight then result.plots = FlatPlots( gp:GetActivationHighlightPlots() ); end
			if #result.plots == 0 and districtRow ~= nil then
				result.plots = CompletedDistrictPlots( owner, districtRow );
				result.empty = "No completed " .. Locale.Lookup( districtRow.Name );
			end
		end
	end );
	if not ok then print( "HubSettle.ActivationPlots error: " .. tostring( err ) ); return nil; end
	return result;
end

-- "Rome's Campus" for a district plot, the resource for an antiquity site or shipwreck, else the short plot description.
local function ActTileName( plot:table )
	local text:string = nil;
	pcall( function()
		local districtType = plot:GetDistrictType();
		local district:table = ( districtType ~= nil and districtType >= 0 ) and GameInfo.Districts[ districtType ] or nil;
		if district ~= nil and district.DistrictType ~= "DISTRICT_CITY_CENTER" then
			local city:table = Cities.GetPlotPurchaseCity( plot ) or Cities.GetCityInPlot( plot:GetX(), plot:GetY() );
			text = ( city ~= nil and ( Locale.Lookup( city:GetName() ) .. "'s " ) or "" ) .. Locale.Lookup( district.Name );
			return;
		end
		local resource:table = GameInfo.Resources[ plot:GetResourceType() ];
		if resource ~= nil and ( resource.ResourceType == "RESOURCE_ANTIQUITY_SITE" or resource.ResourceType == "RESOURCE_SHIPWRECK" ) then
			text = Locale.Lookup( resource.Name );
		end
	end );
	return text or PlotDescription_GetShort( plot );
end

local function BuildActItems( unit:table, a:table )
	local entries:table = {};
	local seen:table = {};
	local ux:number, uy:number = unit:GetX(), unit:GetY();
	for _, index in ipairs( a.plots ) do
		local plot:table = Map.GetPlotByIndex( index );
		if plot ~= nil and not seen[ index ] then
			seen[ index ] = true;
			local distance:number = Map.GetPlotDistance( ux, uy, plot:GetX(), plot:GetY() );
			table.insert( entries, { plot = plot, plotIndex = index, x = plot:GetX(), y = plot:GetY(), distance = distance, here = ( distance == 0 ) } );
		end
	end
	table.sort( entries, function( p, q )
		if p.distance ~= q.distance then return p.distance < q.distance; end
		return p.plotIndex < q.plotIndex;
	end );
	local from:table = Map.GetPlot( ux, uy );
	local items:table = {};
	local pathsDone:number = 0;
	for _, e in ipairs( entries ) do
		local keep:boolean = true;
		if not e.here and pathsDone < ACT_TURN_LIMIT then
			pathsDone = pathsDone + 1;
			local path:table = UnitManager.GetMoveToPathEx( unit, e.plotIndex );
			if path ~= nil and path.plots ~= nil and #path.plots >= 2 then
				e.turns = path.turns[ #path.turns ] or 1;
			else
				keep = false;		-- unreachable
			end
		end
		if keep then
			e.name = ActTileName( e.plot );
			e.relative = e.here and nil or PlotDescription_GetRelative( from, e.plot );
			if not e.here and string.find( e.name, "'s ", 1, true ) == nil then		-- a district plot already says its city
				local okP:boolean, position = pcall( HubAnnounce.PositionText, e.plot );
				if okP then e.position = position; end
			end
			table.insert( items, { key = tostring( e.plotIndex ), text = HubSettle.ActItemText( e, a ), detail = PlotDescription_GetShort( e.plot ), entry = e } );
		end
	end
	return items;
end

-- Browsing moved the cursor over the tiles: back to the unit (not when the mode went stale).
local function ActClosed( quiet:boolean )
	if quiet then return; end
	local unit:table = UI.GetHeadSelectedUnit();
	if unit ~= nil then HubCursor.SetCursor( unit:GetX(), unit:GetY(), false ); end
end

-- Runs the unit's action through the Tab menu path (UnitPanel's own button callback). a: the activation record.
function HubSettle.RunAction( unit:table, a:table )
	local found:table = nil;
	for _, menuItem in ipairs( HubMenus.FetchMenuItems( true ) ) do
		local typeName:string = menuItem.action.typeName or "";
		for _, word in ipairs( ACT_TYPES ) do
			if found == nil and string.find( typeName, word, 1, true ) ~= nil then found = menuItem; end
		end
	end
	local what:string = HubSettle.ActionInfinitive( a );
	if found == nil then
		HubCore.SayResult( "Cannot " .. what .. " here" );
	elseif found.choosable == false then
		HubCore.SayResult( "Cannot " .. what .. ": " .. found.reason );
	else
		local modeBefore:number = UI.GetInterfaceMode();
		LuaEvents.SRA_RunUnitAction( found.action.id, unit:GetID() );
		if UI.GetInterfaceMode() == modeBefore and not ACT_SILENT[ found.action.typeName ] and HubMenus.OPERATION_RESULTS[ found.action.typeName ] == nil then
			HubCore.SayResult( HubMenus.ActionResultText( found.action.name ) );
		end
	end
end

-- Enter on a tile: on the one the unit stands on the action runs, elsewhere the unit walks there and Enter acts on arrival.
local function ActGo( item:table )
	local unit:table = UI.GetHeadSelectedUnit();
	local tile:table = item.entry;
	local a:table = m_act.act;
	if unit == nil or unit:GetID() ~= m_act.unitId or HubSettle.ActivationPlots( unit ) == nil then
		HubCore.CloseMode( false, false );
		HubCore.SayResult( "Unit no longer selected" );
		return;
	end
	local here:boolean = tile.here or ( unit:GetX() == tile.x and unit:GetY() == tile.y );
	if not here and DangerWarned( unit, tile.plotIndex, tile.name ) then return; end
	HubCore.CloseMode( false, false );
	if here then
		HubSettle.RunAction( unit, a );
		return;
	end
	local plot:table = Map.GetPlotByIndex( tile.plotIndex );
	local war:table = HubTargets.WarTargets( unit, plot );
	local path:table = UnitManager.GetMoveToPathEx( unit, plot:GetIndex() );
	if war == nil and ( path == nil or path.plots == nil or #path.plots < 2 ) then
		local why:string = HubTargets.UnreachableReason( unit, plot );
		HubCore.SayResult( "Unreachable" .. ( why ~= "" and ( ": " .. why ) or "" ) );
		return;
	end
	HubTargets.IssueMoveOrder( unit, plot, war, false );
	-- remember the action for the arrival (HubEvents.OnUnitMoveComplete says "Enter activates ...")
	local record:table = HubCore.m_movers[ unit:GetID() ];
	HubSettle.m_pending = nil;
	if record ~= nil and war == nil then
		record.build = { type = "ACTION", name = HubSettle.ActionInfinitive( a ), act = a };
	end
end

m_actList = KeyNavList_Create{
	build		= function() return m_act.items; end,
	isActive	= function() return HubCore.IsModeOpen( "act" ); end,
	onActivate	= ActGo,
	onClose		= function() HubCore.CloseMode( true, false ); end,
	onFocus		= function( item ) HubCursor.SetCursor( item.entry.x, item.entry.y, false, nil, true ); end,
};

-- X with such a unit: opens the browser (or says why there is nothing). Returns false for a unit without the ability.
function HubSettle.OpenActBrowser( unit:table )
	local a:table = HubSettle.ActivationPlots( unit );
	if a == nil then return false; end
	local noMoves:string = ( unit:GetMovesRemaining() <= 0 ) and ( Locale.Lookup( unit:GetName() ) .. " has no moves left. " ) or "";
	local items:table = BuildActItems( unit, a );
	if #items == 0 then
		OutputMessageToScreenReader( #a.plots == 0 and a.empty or "No reachable tile to " .. HubSettle.ActionInfinitive( a ) .. " on" );
		return true;
	end
	m_act = { items = items, unitId = unit:GetID(), act = a };
	HubCore.OpenMode( "act", m_actList, noMoves .. "Tiles to " .. HubSettle.ActionInfinitive( a ) .. ", " .. HubCore.Plural( #items, "tile", "tiles" ), ActClosed );
	return true;
end

-- Hint for the announcement of a selected builder (costs nothing: no scan); nil for other units.
function HubSettle.BuilderHint( unit:table )
	if unit == nil or BuildScan_Improvements( unit ) == nil then return nil; end
	return SRKey( "X", "X" ) .. " lists tiles to improve";
end

-- The browser X opens for this unit, as { text, open } for the unit actions menu (the controller has no X on the map), or nil
-- when X would not open one (the scan for foreign units). Same order and tests as ScanKey; open() is ScanKey itself.
function HubSettle.BrowserFor( unit:table )
	if unit == nil then return nil; end
	local text:string = nil;
	if HubCore.IsSettler( unit ) then text = "Browse settle spots";
	elseif BuildScan_Improvements( unit ) ~= nil then text = "Browse tiles to improve";
	elseif HubSettle.ActivationPlots( unit ) ~= nil then text = "Browse tiles to act on"; end
	if text == nil then return nil; end
	return { text = text, open = function() HubSettle.ScanKey(); end };
end

-- X: with a settler selected the spot browser, with a builder the tile browser, otherwise the scan for foreign units.
function HubSettle.ScanKey()
	if not HubCore.IsLocalPlayerActive() then return; end
	if HubCore.IsModeOpen( "settle" ) or HubCore.IsModeOpen( "build" ) or HubCore.IsModeOpen( "act" ) then HubCore.CloseMode( true, false ); return; end
	local unit:table = UI.GetHeadSelectedUnit();
	if HubCore.IsSettler( unit ) and HubTargets.GetTargetMode() == nil then
		OpenSettleBrowser( unit );
		return;
	end
	if BuildScan_Improvements( unit ) ~= nil and HubTargets.GetTargetMode() == nil then
		OpenBuildBrowser( unit );
		return;
	end
	if HubTargets.GetTargetMode() == nil and HubSettle.OpenActBrowser( unit ) then return; end
	HubCursor.ScanUnits( true );
end
