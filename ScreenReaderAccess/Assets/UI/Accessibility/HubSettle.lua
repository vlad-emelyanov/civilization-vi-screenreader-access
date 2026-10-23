-- ===========================================================================
--	HubSettle: settle spot browser (X with a settler) and tile browser (X with a builder).
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

-- "2 tiles north-east, 1 turn, river, coast, silk, recommended" / "Here, river, wine"
local function SettleItemText( c:table )
	local text:string = c.here and "Here" or ( c.relative .. ", " .. HubCore.Plural( c.turns, "turn", "turns" ) );
	text = text .. HubCore.SettleReasons( c, 3, 2 );
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
			HubCore.SayResult( "B to found next turn" );
		else
			HubCore.SayResult( "B to found the city here" );
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
		HubCore.SayResult( "Unreachable" );
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
local m_build:table = { cities = {}, index = 1, items = {} };

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

-- "Wheat, Farm plus 1 food, 2 tiles north-east, 1 turn, worked" / "Here, Wheat, Farm plus 1 food"
local function BuildItemText( entry:table )
	local text:string = ( entry.here and "Here, " or "" ) .. entry.name .. ", " .. BuildImprovementsText( entry );
	if not entry.here then
		text = text .. ", " .. entry.relative .. ", " .. HubCore.Plural( entry.turns or 0, "turn", "turns" );
	end
	if entry.worked then text = text .. ", worked"; end
	return text;
end

local function BuildItemDetail( entry:table )
	local all:table = {};
	for _, improvement in ipairs( entry.improvements ) do table.insert( all, BuildImprovementText( improvement ) ); end
	return PlotDescription_GetShort( entry.plot ) .. ". Can build: " .. table.concat( all, "; " );
end

-- Scans the city at m_build.index and fills m_build.items.
local function LoadBuildItems( unit:table )
	m_build.items = {};
	local entry:table = m_build.cities[ m_build.index ];
	if entry == nil then return; end
	for _, tile in ipairs( BuildScan_Scan( unit, entry.city ).list ) do
		table.insert( m_build.items, { key = tile.key, text = BuildItemText( tile ), detail = BuildItemDetail( tile ), entry = tile } );
	end
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
	LoadBuildItems( unit );
	local city:table = m_build.cities[ m_build.index ];
	HubCore.CloseMode( false, false );
	HubCore.m_mode = { name = "build", list = m_buildList, onClose = BuildClosed };
	m_buildList.Reset();
	if #m_build.items == 0 then
		OutputMessageToScreenReader( "Tiles to improve near " .. city.name .. ", nothing to improve" );
		return;
	end
	m_buildList.Open( "", nil, true );		-- silent: only puts the focus on the first tile
	m_buildList.Focus( m_build.items[1].key, "Tiles to improve near " .. city.name .. ", " .. HubCore.Plural( #m_build.items, "tile", "tiles" ) );
end

-- Left/Right: the next / previous city.
local function SwitchBuildCity( delta:number )
	if not HubCore.IsModeOpen( "build" ) then return; end
	local unit:table = UI.GetHeadSelectedUnit();
	local count:number = #m_build.cities;
	if unit == nil or BuildScan_Improvements( unit ) == nil then HubCore.CloseMode( false, true ); return; end
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
	m_buildList.Focus( m_build.items[1].key, city.name .. ", " .. HubCore.Plural( #m_build.items, "tile", "tiles" ) .. " to improve" );
end

-- Enter: on the builder's own tile the unit actions menu (it lists the build actions), elsewhere the builder walks there
-- (the same path as the move-to mode).
local function BuildGo( item:table )
	local unit:table = UI.GetHeadSelectedUnit();
	HubCore.CloseMode( false, false );
	if unit == nil or BuildScan_Improvements( unit ) == nil then
		HubCore.SayResult( "No builder selected" );
		return;
	end
	local tile:table = item.entry;
	if tile.here or ( unit:GetX() == tile.x and unit:GetY() == tile.y ) then
		HubMenus.ToggleUnitMenu();
		return;
	end
	local plot:table = Map.GetPlotByIndex( tile.plotIndex );
	local war:table = HubTargets.WarTargets( unit, plot );
	local path:table = UnitManager.GetMoveToPathEx( unit, plot:GetIndex() );
	if war == nil and ( path == nil or path.plots == nil or #path.plots < 2 ) then
		HubCore.SayResult( "Unreachable" );
		return;
	end
	HubTargets.IssueMoveOrder( unit, plot, war, false );
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

-- "X: 5 tiles to improve near Rome" for the announcement of a selected builder (nil: not a builder, no moves, nothing to do).
function HubSettle.BuilderHint( unit:table )
	if unit == nil or BuildScan_Improvements( unit ) == nil or unit:GetMovesRemaining() <= 0 then return nil; end
	local city:table = BuildScan_DefaultCity( unit );
	if city == nil then return nil; end
	local scan:table = BuildScan_Scan( unit, city, true );
	if #scan.list == 0 then return nil; end
	return "X: " .. HubCore.Plural( #scan.list, "tile", "tiles" ) .. " to improve near " .. scan.cityName;
end

-- X: with a settler selected the spot browser, with a builder the tile browser, otherwise the scan for foreign units.
function HubSettle.ScanKey()
	if not HubCore.IsLocalPlayerActive() then return; end
	if HubCore.IsModeOpen( "settle" ) or HubCore.IsModeOpen( "build" ) then HubCore.CloseMode( true, false ); return; end
	local unit:table = UI.GetHeadSelectedUnit();
	if HubCore.IsSettler( unit ) and HubTargets.GetTargetMode() == nil then
		OpenSettleBrowser( unit );
		return;
	end
	if BuildScan_Improvements( unit ) ~= nil and HubTargets.GetTargetMode() == nil then
		OpenBuildBrowser( unit );
		return;
	end
	HubCursor.ScanUnits( true );
end
