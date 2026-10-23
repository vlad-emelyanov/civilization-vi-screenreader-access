-- ===========================================================================
--	HubCityReport: city report (Control+I) and city management.
--	Part of the InGameAccess hub (see docs/ingame-plan.md, Architecture): included by
--	UI/Additions/InGameAccess.lua. State and functions other hub modules use are fields of HubCityReport.
-- ===========================================================================
HubCityReport = {};

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
HubCityReport.m_manageView = nil;		-- nil: the report itself; "focus", "tiles" or "specialists"
HubCityReport.m_manageConfirm = nil;		-- key of the buyable tile that waits for its second Enter
HubCityReport.m_manageBusy = false;		-- a request was sent and its result is not known yet

-- Mirrors PlotInfo.OnClickCitizen (Base/Assets/UI/WorldView/PlotInfo.lua:55-67): the click on a citizen button of a tile.
-- The game's click toggles work/lock on a tile and adds specialists to a district.
function HubCityReport.RequestCitizenClick( city:table, plot:table )
	local params:table = {};
	params[ CityCommandTypes.PARAM_MANAGE_CITIZEN ] = UI.GetInterfaceModeParameter( CityCommandTypes.PARAM_MANAGE_CITIZEN );
	params[ CityCommandTypes.PARAM_X ] = plot:GetX();
	params[ CityCommandTypes.PARAM_Y ] = plot:GetY();
	CityManager.RequestCommand( city, CityCommandTypes.MANAGE, params );
end

-- Mirrors PlotInfo.OnClickPurchasePlot (PlotInfo.lua:83-98). False when the engine refuses.
function HubCityReport.RequestPlotPurchase( city:table, plot:table )
	local params:table = {};
	params[ CityCommandTypes.PARAM_PLOT_PURCHASE ] = UI.GetInterfaceModeParameter( CityCommandTypes.PARAM_PLOT_PURCHASE );
	params[ CityCommandTypes.PARAM_X ] = plot:GetX();
	params[ CityCommandTypes.PARAM_Y ] = plot:GetY();
	if not CityManager.CanStartCommand( city, CityCommandTypes.PURCHASE, params ) then return false; end
	CityManager.RequestCommand( city, CityCommandTypes.PURCHASE, params );
	return true;
end

-- Mirror CityPanel.SetYieldFocus / SetYieldIgnore (Base/Assets/UI/Panels/CityPanel.lua:445-478), g_pCity = city.
function HubCityReport.RequestYieldFocus( city:table, yieldType:number )
	local citizens:table = city:GetCitizens();
	local params:table = {};
	params[ CityCommandTypes.PARAM_FLAGS ] = 0;				-- Set Favored
	params[ CityCommandTypes.PARAM_YIELD_TYPE ] = yieldType;
	if citizens:IsFavoredYield( yieldType ) then
		params[ CityCommandTypes.PARAM_DATA0 ] = 0;
	else
		if citizens:IsDisfavoredYield( yieldType ) then HubCityReport.RequestYieldIgnore( city, yieldType ); end
		params[ CityCommandTypes.PARAM_DATA0 ] = 1;
	end
	CityManager.RequestCommand( city, CityCommandTypes.SET_FOCUS, params );
end

HubCityReport.RequestYieldIgnore = function( city:table, yieldType:number )
	local citizens:table = city:GetCitizens();
	local params:table = {};
	params[ CityCommandTypes.PARAM_FLAGS ] = 1;				-- Set Ignored
	params[ CityCommandTypes.PARAM_YIELD_TYPE ] = yieldType;
	if citizens:IsDisfavoredYield( yieldType ) then
		params[ CityCommandTypes.PARAM_DATA0 ] = 0;
	else
		if citizens:IsFavoredYield( yieldType ) then HubCityReport.RequestYieldFocus( city, yieldType ); end
		params[ CityCommandTypes.PARAM_DATA0 ] = 1;
	end
	CityManager.RequestCommand( city, CityCommandTypes.SET_FOCUS, params );
end

function HubCityReport.ManageData()
	local city:table = GetReportCity();
	if city == nil then return nil, nil; end
	return CityManage_Gather( city ), city;
end

-- "Food plus 5, production 13" of the city as it is now
function HubCityReport.ManageTotals( city:table )
	local data:table = CityReport_Gather( city );
	if data == nil then return ""; end
	return CityManage_Totals( data );
end

-- After a request: waits until read() differs from before (the engine applies the command a moment later), then say( now ).
-- Gives up after 2 s with "Nothing changed".
function HubCityReport.ManageWatch( read, before:string, say )
	HubCityReport.m_manageBusy = true;
	HubCore.m_lastKeyTime = UI.GetElapsedTime();
	local function Poll( tries:number )
		HubCore.After( 0.4, function()
			if not HubCore.IsModeOpen( "cityreport" ) then HubCityReport.m_manageBusy = false; return; end
			local ok:boolean, now = pcall( read );
			if ok and now ~= before then
				HubCityReport.m_manageBusy = false;
				local ok2:boolean, err = pcall( say, now );
				if not ok2 then print( "InGameAccess city management error: " .. tostring( err ) ); end
			elseif tries >= 5 then
				HubCityReport.m_manageBusy = false;
				print( "InGameAccess: the city management request changed nothing" );
				OutputMessageToScreenReader( "Nothing changed" );
			else
				Poll( tries + 1 );
			end
		end );
	end
	Poll( 1 );
end

function HubCityReport.FindByPlot( list:table, plotIndex:number )
	for _, entry in ipairs( list or {} ) do
		if entry.plotIndex == plotIndex then return entry; end
	end
	return nil;
end

function HubCityReport.EnterManageView( view:string )
	local city:table = GetReportCity();
	if city == nil then return; end
	HubCityReport.m_manageView = view;
	HubCityReport.m_manageConfirm = nil;
	HubCityReport.m_manageBusy = false;
	if view == "focus" then
		HubCityReport.m_focusList.Reset();
		HubCityReport.m_focusList.Open( "Focus" );
	elseif view == "tiles" then
		HubCityReport.m_tilesList.Reset();
		HubCityReport.m_tilesList.Open( "Tiles" );
	else
		HubCityReport.m_specList.Reset();
		HubCityReport.m_specList.Open( "Specialists" );
	end
end

function HubCityReport.LeaveManageView()
	local view:string = HubCityReport.m_manageView;
	HubCityReport.m_manageView = nil;
	HubCityReport.m_manageConfirm = nil;
	HubCityReport.m_manageBusy = false;
	HubCityReport.m_focusList.Reset();
	HubCityReport.m_tilesList.Reset();
	HubCityReport.m_specList.Reset();
	local city:table = GetReportCity();
	if city ~= nil and view ~= "focus" then HubCursor.SetCursor( city:GetX(), city:GetY(), false, nil, true ); end
	m_reportList.Focus( view );
end

function HubCityReport.CursorToPlotIndex( plotIndex:number )
	local plot:table = Map.GetPlotByIndex( plotIndex );
	if plot ~= nil then HubCursor.SetCursor( plot:GetX(), plot:GetY(), false, nil, true ); end
end

function HubCityReport.FocusState( city:table, yieldType:number )
	local citizens:table = city:GetCitizens();
	if citizens:IsFavoredYield( yieldType ) then return "favored"; end
	if citizens:IsDisfavoredYield( yieldType ) then return "ignored"; end
	return "normal";
end

function HubCityReport.FocusEnter( item:table )
	if HubCityReport.m_manageBusy then OutputMessageToScreenReader( "Wait" ); return; end
	local city:table = GetReportCity();
	if city == nil then return; end
	local f:table = item.yield;
	local name:string = string.lower( f.name );
	local before:string = HubCityReport.FocusState( city, f.yieldType );
	if item.ignore then HubCityReport.RequestYieldIgnore( city, f.yieldType ); else HubCityReport.RequestYieldFocus( city, f.yieldType ); end
	HubCityReport.ManageWatch( function() return HubCityReport.FocusState( city, f.yieldType ); end, before, function( now )
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
		OutputMessageToScreenReader( text .. ". " .. HubCityReport.ManageTotals( city ) );
	end );
end

function HubCityReport.TilesEnter( item:table )
	if HubCityReport.m_manageBusy then OutputMessageToScreenReader( "Wait" ); return; end
	local city:table = GetReportCity();
	local t:table = item.tile;
	local plot:table = Map.GetPlotByIndex( t.plotIndex );
	if city == nil or plot == nil then return; end
	if t.cost ~= nil then
		local gold:number = math.floor( Players[ Game.GetLocalPlayer() ]:GetTreasury():GetGoldBalance() );
		-- CanStartCommand does not look at the balance (docs/engine-notes.md)
		if gold < t.cost then
			HubCityReport.m_manageConfirm = nil;
			OutputMessageToScreenReader( "Can't buy this tile, need " .. ( t.cost - gold ) .. " more gold" );
			return;
		end
		if HubCityReport.m_manageConfirm ~= t.key then
			HubCityReport.m_manageConfirm = t.key;
			OutputMessageToScreenReader( "Buy this tile for " .. t.cost .. " gold? Enter to confirm, Escape to go back" );
			return;
		end
		HubCityReport.m_manageConfirm = nil;
		if not HubCityReport.RequestPlotPurchase( city, plot ) then
			OutputMessageToScreenReader( "Can't buy this tile" );
			return;
		end
		HubCityReport.ManageWatch( function() return tostring( plot:GetOwner() ); end, tostring( plot:GetOwner() ), function()
			HubCityReport.m_tilesList.Focus( "t" .. t.plotIndex, "Bought for " .. t.cost .. " gold" );
		end );
		return;
	end
	local function Sig()
		local m:table = HubCityReport.ManageData();
		local now:table = m ~= nil and HubCityReport.FindByPlot( m.tiles, t.plotIndex ) or nil;
		if now == nil then return "gone"; end
		return now.count .. ":" .. tostring( now.locked );
	end
	local before:string = Sig();
	HubCityReport.RequestCitizenClick( city, plot );
	HubCityReport.ManageWatch( Sig, before, function()
		local m:table = HubCityReport.ManageData();
		local now:table = m ~= nil and HubCityReport.FindByPlot( m.tiles, t.plotIndex ) or nil;
		local state:string = ( now ~= nil ) and CityManage_TileState( now ) or "Changed";
		OutputMessageToScreenReader( state .. ". " .. HubCityReport.ManageTotals( city ) );
	end );
end

function HubCityReport.SpecialistsEnter( item:table )
	if HubCityReport.m_manageBusy then OutputMessageToScreenReader( "Wait" ); return; end
	local city:table = GetReportCity();
	local dist:table = item.district;
	local plot:table = Map.GetPlotByIndex( dist.plotIndex );
	if city == nil or plot == nil then return; end
	local function Count()
		local m:table = HubCityReport.ManageData();
		local now:table = m ~= nil and HubCityReport.FindByPlot( m.districts, dist.plotIndex ) or nil;
		return now ~= nil and tostring( now.count ) or "gone";
	end
	local before:string = Count();
	HubCityReport.RequestCitizenClick( city, plot );
	HubCityReport.ManageWatch( Count, before, function()
		local m:table = HubCityReport.ManageData();
		local now:table = m ~= nil and HubCityReport.FindByPlot( m.districts, dist.plotIndex ) or nil;
		if now == nil then return; end
		OutputMessageToScreenReader( CityManage_DistrictText( now ) .. ". " .. HubCityReport.ManageTotals( city ) );
	end );
end

-- Backspace / Delete: one specialist less. The game has no "remove one" click (a click adds, and past the last slot the
-- district empties), so this clicks until the count has dropped by one (at most as many clicks as slots plus one).
function HubCityReport.SpecialistsRemove()
	if HubCityReport.m_manageBusy then OutputMessageToScreenReader( "Wait" ); return; end
	local m:table, city:table = HubCityReport.ManageData();
	if m == nil then return; end
	local focusKey = HubCityReport.m_specList.GetFocusKey();
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
		local fresh:table = HubCityReport.ManageData();
		local now:table = fresh ~= nil and HubCityReport.FindByPlot( fresh.districts, dist.plotIndex ) or nil;
		return now ~= nil and tostring( now.count ) or "gone";
	end
	local function Say()
		local fresh:table = HubCityReport.ManageData();
		local now:table = fresh ~= nil and HubCityReport.FindByPlot( fresh.districts, dist.plotIndex ) or nil;
		if now == nil then return; end
		OutputMessageToScreenReader( CityManage_DistrictText( now ) .. ". " .. HubCityReport.ManageTotals( city ) );
	end
	local function Step()
		clicks = clicks + 1;
		local before:string = Count();
		HubCityReport.RequestCitizenClick( city, plot );
		HubCityReport.ManageWatch( Count, before, function( now )
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
	isActive	= function() return HubCore.IsModeOpen( "cityreport" ) and HubCityReport.m_manageView == nil; end,
	onActivate	= function( item )
		if item.manage ~= nil then HubCityReport.EnterManageView( item.manage ); return; end
		OutputMessageToScreenReader( "Nothing to open here. Space reads the details" );
	end,
	onClose		= function() HubCore.CloseMode( true, false ); end,
};

HubCityReport.m_focusList = KeyNavList_Create{
	build		= function()
		local m:table = HubCityReport.ManageData();
		if m == nil then return {}; end
		return CityManage_FocusItems( m );
	end,
	isActive	= function() return HubCore.IsModeOpen( "cityreport" ) and HubCityReport.m_manageView == "focus"; end,
	onActivate	= HubCityReport.FocusEnter,
	onClose		= HubCityReport.LeaveManageView,
};

HubCityReport.m_tilesList = KeyNavList_Create{
	build		= function()
		local m:table = HubCityReport.ManageData();
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
	isActive	= function() return HubCore.IsModeOpen( "cityreport" ) and HubCityReport.m_manageView == "tiles"; end,
	onActivate	= HubCityReport.TilesEnter,
	onClose		= HubCityReport.LeaveManageView,
	onFocus		= function( item )
		HubCityReport.m_manageConfirm = nil;
		HubCityReport.CursorToPlotIndex( item.tile.plotIndex );
	end,
};

HubCityReport.m_specList = KeyNavList_Create{
	build		= function()
		local m:table = HubCityReport.ManageData();
		if m == nil then return {}; end
		local items:table = CityManage_DistrictItems( m );
		for _, item in ipairs( items ) do
			item.detail = item.text .. ". Enter adds a specialist, Backspace removes one";
		end
		return items;
	end,
	isActive	= function() return HubCore.IsModeOpen( "cityreport" ) and HubCityReport.m_manageView == "specialists"; end,
	onActivate	= HubCityReport.SpecialistsEnter,
	onClose		= HubCityReport.LeaveManageView,
	onFocus		= function( item ) HubCityReport.CursorToPlotIndex( item.district.plotIndex ); end,
	extraKeys	= { [Keys.VK_BACK] = HubCityReport.SpecialistsRemove, [Keys.VK_DELETE] = HubCityReport.SpecialistsRemove },
};

-- What the mode holds: the report list and its sub-lists (each handles keys only while it is the active view).
HubCityReport.m_reportFacade = {
	Open		= function( title:string ) HubCityReport.m_manageView = nil; m_reportList.Open( title ); end,
	Reset		= function()
		HubCityReport.m_manageView = nil;
		HubCityReport.m_manageConfirm = nil;
		HubCityReport.m_manageBusy = false;
		m_reportList.Reset();
		HubCityReport.m_focusList.Reset();
		HubCityReport.m_tilesList.Reset();
		HubCityReport.m_specList.Reset();
	end,
	HandleInput	= function( input:table )
		return m_reportList.HandleInput( input ) or HubCityReport.m_focusList.HandleInput( input ) or HubCityReport.m_tilesList.HandleInput( input ) or HubCityReport.m_specList.HandleInput( input );
	end,
};

function HubCityReport.ToggleCityReport()
	if HubCore.IsModeOpen( "cityreport" ) then HubCore.CloseMode( true, false ); return; end
	if not HubTargets.CanOpenMode() then return; end
	if not Hub.m_cityReportLoaded or CityReport_Gather == nil or CityReport_BuildItems == nil then
		OutputMessageToScreenReader( "The city report is not available" );
		return;
	end
	local localPlayer:number = Game.GetLocalPlayer();
	local city:table = UI.GetHeadSelectedCity();
	if city == nil or city:GetOwner() ~= localPlayer then
		city = nil;
		local x:number, y:number = HubCursor.GetCursor();
		local atCursor:table = Cities.GetCityInPlot( x, y );
		if atCursor ~= nil and atCursor:GetOwner() == localPlayer then city = atCursor; end
	end
	if city == nil then
		OutputMessageToScreenReader( "No city selected. Backslash selects the capital" );
		return;
	end
	m_reportCity = { owner = city:GetOwner(), id = city:GetID() };
	HubCore.OpenMode( "cityreport", HubCityReport.m_reportFacade, Locale.Lookup( city:GetName() ) .. " report", function() m_reportCity = nil; end );
end
