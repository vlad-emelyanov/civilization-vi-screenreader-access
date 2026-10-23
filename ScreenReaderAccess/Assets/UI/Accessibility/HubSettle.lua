-- ===========================================================================
--	HubSettle: settle spot browser (X with a settler).
--	Part of the InGameAccess hub (see docs/ingame-plan.md, Architecture): included by
--	UI/Additions/InGameAccess.lua. State and functions other hub modules use are fields of HubSettle.
-- ===========================================================================
HubSettle = {};

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

-- X: with a settler selected the spot browser, otherwise the scan for foreign units.
function HubSettle.ScanKey()
	if not HubCore.IsLocalPlayerActive() then return; end
	if HubCore.IsModeOpen( "settle" ) then HubCore.CloseMode( true, false ); return; end
	local unit:table = UI.GetHeadSelectedUnit();
	if HubCore.IsSettler( unit ) and HubTargets.GetTargetMode() == nil then
		OpenSettleBrowser( unit );
		return;
	end
	HubCursor.ScanUnits( true );
end
