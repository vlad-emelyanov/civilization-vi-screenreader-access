-- ===========================================================================
--	HubPlacement: district and wonder placement browser.
--	Part of the InGameAccess hub (see docs/ingame-plan.md, Architecture): included by
--	UI/Additions/InGameAccess.lua. State and functions other hub modules use are fields of HubPlacement.
-- ===========================================================================
HubPlacement = {};

local m_placeScan			:table = nil;		-- PlacementScan result of the open placement mode (district / wonder browser)
local m_placeParams			:table = nil;		-- insert-mode parameters read from the interface mode when placement began
local m_placeBusy			:boolean = false;	-- a tile purchase is waiting for its rescan: Enter says "Wait"

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
HubCore.PlacementPlotText = function( plot:table )
	local scan:table = m_placeScan;
	if scan == nil or not HubCore.IsModeOpen( "placement" ) then return nil; end
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
	HubCore.m_placeConfirm = nil;
	m_placeBusy = false;
	-- not when the close is the mode being replaced by another placement mode: that one must stay
	if not HubCore.m_placeReplaced and IsPlacementMode( UI.GetInterfaceMode() ) then UI.SetInterfaceMode( InterfaceModeTypes.SELECTION ); end
	local plot:table = HubCore.GetSelectionPlot();
	if plot ~= nil then HubCursor.SetCursor( plot:GetX(), plot:GetY(), false, nil, true ); end
end

local function PlacementCancel()
	HubCore.SayResult( "Placement cancelled" );
	UI.SetInterfaceMode( InterfaceModeTypes.SELECTION );		-- the mode change closes the browser; the game reopens the production panel
end

-- Escape: back from the confirmation first, then out of the placement.
local function PlacementEscape()
	if HubCore.m_placeConfirm ~= nil then
		HubCore.m_placeConfirm = nil;
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
	if city == nil or not HubCore.IsLocalPlayerActive() then return; end
	-- the selection of the next unit may already have been spoken: do not cut it off, queue behind it
	local SayLocal = function( text:string )
		HubCore.m_lastResultTime = UI.GetElapsedTime();
		OutputMessageToScreenReader( text, HubCore.m_lastSelectionSpeech > HubCore.m_placeCommitTime );
	end
	if scan.purchaseYield ~= nil then
		local player:table = Players[ Game.GetLocalPlayer() ];
		local isGold:boolean = ( scan.purchaseYield == YieldTypes.GOLD );
		local balance:number = isGold and math.floor( player:GetTreasury():GetGoldBalance() ) or math.floor( player:GetReligion():GetFaithBalance() );
		if balance < before.balance then
			SayLocal( "Bought " .. scan.name .. ", " .. balance .. ( isGold and " gold" or " faith" ) .. " left" );
			return;
		end
	else
		local queue:table = city:GetBuildQueue();
		local hash:number = queue:GetCurrentProductionTypeHash();
		if hash == scan.hash or queue:GetSize() > before.size then
			local text:string = ( hash == scan.hash and "Producing " or "Queued " ) .. scan.name;
			local turns:number = queue:GetTurnsLeft();
			if hash == scan.hash and turns ~= nil and turns > 0 then text = text .. ", " .. HubCore.Plural( turns, "turn", "turns" ); end
			SayLocal( text );
			return;
		end
	end
	if tries < 3 then
		HubCore.After( 0.5, function() PlacementResult( scan, before, tries + 1 ); end );
	else
		SayLocal( "Not placed. Tab to the production panel to check" );
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
				HubCore.SayResult( "Can't buy " .. scan.name .. ", need " .. ( cost - balance ) .. ( isGold and " more gold" or " more faith" ) );
				return;
			end
		end
		local reasons:table = {};
		if results ~= nil then
			for _, text in ipairs( results[ CityOperationResults.FAILURE_REASONS ] or results[ CityCommandResults.FAILURE_REASONS ] or {} ) do table.insert( reasons, CleanTextForSpeech( Locale.Lookup( text ) ) ); end
		end
		HubCore.SayResult( "Can't place " .. scan.name .. " here any more" .. ( #reasons > 0 and ( ": " .. table.concat( reasons, ", " ) ) or "" ) );
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
	HubCore.m_lastKeyTime = UI.GetElapsedTime();
	HubCore.m_placeCommitTime = HubCore.m_lastKeyTime;
	LuaEvents.SRA_ExitPlacement( false );		-- WorldInput: leave the mode as the game does after placing (closes this mode)
	HubCore.After( 0.3, function()		-- the hook may be missing or fail: never stay in the placement mode after a commit
		if IsPlacementMode( UI.GetInterfaceMode() ) then UI.SetInterfaceMode( InterfaceModeTypes.SELECTION ); end
	end );
	HubCore.After( 0.4, function() PlacementResult( scan, before, 1 ); end );
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
		HubCore.SayResult( "Not buying this tile, " .. scan.name .. " can't go there: " .. blockers );
		return;
	end
	local params:table = {};
	params[ CityCommandTypes.PARAM_PLOT_PURCHASE ] = UI.GetInterfaceModeParameter( CityCommandTypes.PARAM_PLOT_PURCHASE );
	params[ CityCommandTypes.PARAM_X ] = c.x;
	params[ CityCommandTypes.PARAM_Y ] = c.y;
	-- CanStartCommand does not look at the balance (verified: it says yes and the purchase then silently fails)
	if gold < c.tileCost then
		HubCore.SayResult( "Can't buy this tile, need " .. ( c.tileCost - gold ) .. " more gold" );
		return;
	end
	if not CityManager.CanStartCommand( city, CityCommandTypes.PURCHASE, params ) then
		HubCore.SayResult( "Can't buy this tile" );
		return;
	end
	local owner:number = plot:GetOwner();
	CityManager.RequestCommand( city, CityCommandTypes.PURCHASE, params );
	HubCore.m_lastKeyTime = UI.GetElapsedTime();
	m_placeBusy = true;
	local function Report( tries:number )
		if not HubCore.IsModeOpen( "placement" ) then m_placeBusy = false; return; end
		if plot:GetOwner() == owner then
			if tries < 2 then
				HubCore.After( 1.0, function() Report( tries + 1 ); end );		-- the engine may not have applied the purchase yet
				return;
			end
			m_placeBusy = false;
			PlacementRescan();
			HubCore.SayResult( "Tile not bought" .. ( gold < c.tileCost and ( ", need " .. ( c.tileCost - gold ) .. " more gold" ) or "" ) );
			return;
		end
		local fresh:table = PlacementRescan();
		m_placeBusy = false;
		if fresh == nil then return; end
		local c2:table = fresh.byIndex[ c.plotIndex ];
		if c2 ~= nil and c2.owned then
			local effects:string = PlacementEffects( c2, false );
			HubCore.SayResult( "Tile bought for " .. c.tileCost .. " gold. Valid" .. ( effects ~= "" and ( ", " .. effects ) or "" ) .. ". Enter to place " .. fresh.name .. " here" );
		else
			local why:string = PlacementScan_Blockers( fresh, plot );
			if why == "" then why = PlacementScan_Cannot( fresh, plot ); end
			print( "InGameAccess: tile " .. plot:GetX() .. "," .. plot:GetY() .. " bought but refused for " .. fresh.typeName .. ": " .. why );
			HubCore.SayResult( "Tile bought, but " .. fresh.name .. " can't go there" .. ( why ~= "" and ( ": " .. why ) or "" ) );
		end
	end
	HubCore.After( 0.6, function() Report( 1 ); end );
end

-- Enter: the tile under the cursor (browsing puts the cursor on the listed tile; Shift+Arrows move it freely). The first
-- Enter asks, the second one does it.
local function PlacementEnter( item:table )
	local scan:table = m_placeScan;
	if scan == nil then return; end
	if m_placeBusy then HubCore.SayResult( "Wait" ); return; end
	local x:number, y:number = HubCursor.GetCursor();
	local plot:table = Map.GetPlot( x, y );
	if plot == nil then return; end
	local c:table = scan.byIndex[ plot:GetIndex() ];
	if c == nil then
		local why:string = PlacementScan_Cannot( scan, plot );
		HubCore.SayResult( "Can't place " .. scan.name .. " here" .. ( why ~= "" and ( ": " .. why ) or "" ) );
		return;
	end
	if HubCore.m_placeConfirm == c.plotIndex then
		HubCore.m_placeConfirm = nil;
		if c.owned then PlacementCommit( c ); else PlacementBuyTile( c ); end
		return;
	end
	HubCore.m_placeConfirm = c.plotIndex;
	local effects:string = PlacementEffects( c, false );
	if c.owned then
		HubCore.SayResult( "Place " .. scan.name .. " here?" .. ( effects ~= "" and ( " " .. effects .. "." ) or "" ) .. " Enter to confirm, Escape to go back" );
	else
		HubCore.SayResult( "Buy this tile for " .. c.tileCost .. " gold?" .. ( effects ~= "" and ( " " .. effects .. "." ) or "" ) .. " Enter to confirm, then Enter again to place " .. scan.name .. ". Escape to go back" );
	end
end

m_placeList = KeyNavList_Create{
	build		= BuildPlacementItems,
	isActive	= function() return HubCore.IsModeOpen( "placement" ); end,
	onActivate	= PlacementEnter,
	onClose		= PlacementEscape,
	onFocus		= function( item )
		HubCore.m_placeConfirm = nil;
		HubCursor.SetCursor( item.candidate.x, item.candidate.y, false, nil, true );
	end,
};

-- The game entered DISTRICT_PLACEMENT / BUILDING_PLACEMENT: scan, open the mode, say what can be done.
HubCore.OpenPlacement = function( mode:number )
	local city:table = UI.GetHeadSelectedCity();
	if city == nil or not HubCore.IsLocalPlayerActive() then
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
		HubCore.After( 0.1, function() if IsPlacementMode( UI.GetInterfaceMode() ) then UI.SetInterfaceMode( InterfaceModeTypes.SELECTION ); end end );
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
	HubCore.m_placeConfirm = nil;
	m_placeBusy = false;
	HubCore.CloseMode( false, true );
	HubCore.m_mode = { name = "placement", list = m_placeList, onClose = PlacementClosed };
	local best:table = scan.best;
	m_placeList.Open( "", best.key, true );
	HubCursor.SetCursor( best.x, best.y, false, nil, true );
	local text:string;
	if ownedNone then
		text = "No owned tile fits; " .. HubCore.Plural( #scan.list, "tile", "tiles" ) .. " can be bought. Best: " .. PlacementItemText( best ) .. ".";
	else
		text = "Place " .. scan.name .. " for " .. scan.cityName .. ( purchaseYield ~= nil and ", bought with " .. ( purchaseYield == YieldTypes.GOLD and "gold" or "faith" ) or "" )
			.. ", " .. HubCore.Plural( #scan.list, "tile", "tiles" ) .. ". Best: " .. PlacementItemText( best ) .. ".";
	end
	if scan.blocked > 0 and scan.blockedReason ~= nil then
		text = text .. " " .. HubCore.Plural( scan.blocked, "tile", "tiles" ) .. " not offered: " .. scan.blockedReason .. ".";
	end
	OutputMessageToScreenReader( text );
end
