-- Copyright 2018-2019, Firaxis Games

-- ===========================================================================
--	INCLUDES
-- ===========================================================================

include("AnimSidePanelSupport");
include("InstanceManager");
include("SupportFunctions");
include("TradeSupport");
include("ScreenReader");		-- ScreenReaderAccess
include("KeyNavList");		-- ScreenReaderAccess
include("Gamepad");		-- ScreenReaderAccess
include("SRListen");		-- ScreenReaderAccess
include("TradeOverviewText");	-- ScreenReaderAccess

-- ===========================================================================
--	CONSTANTS
-- ===========================================================================

local RELOAD_CACHE_ID:string = "TradeOverview"; -- Must be unique (usually the same as the file name)
local DATA_ICON_PREFIX:string = "ICON_";

local TRADE_TABS:table = {
	MY_ROUTES			= 0;
	ROUTES_TO_CITIES	= 1;
	AVAILABLE_ROUTES	= 2;
};

local m_currentTab:number;
local m_showMyBenefits:boolean = true;

-- ===========================================================================
--	VARIABLES
-- ===========================================================================

local m_RouteInstanceIM:table			= InstanceManager:new("RouteInstance", "Top", Controls.BodyStack);
local m_HeaderInstanceIM:table			= InstanceManager:new("HeaderInstance", "Top", Controls.BodyStack);
local m_SimpleButtonInstanceIM:table	= InstanceManager:new("SimpleButtonInstance", "Top", Controls.BodyStack);

local m_AnimSupport:table; -- AnimSidePanelSupport

-- ScreenReaderAccess: what the game's View* functions put on the screen, as plain ids (see the section before Initialize)
local m_srRecords:table = {};
local m_srSection:string = nil;
local m_srQuiet:boolean = false;		-- Close() without "Trade routes closed"

-- Show My Routes Tab
function ViewMyRoutes()
	-- Update Tabs
	SetMyRoutesTabSelected(true);
	SetRoutesToCitiesTabSelected(false);
	SetAvailableRoutesTabSelected(false);
	
	local localPlayerID = Game.GetLocalPlayer();
	if (localPlayerID == -1) then
		return;
	end

	-- Update Header
	local playerTrade	:table	= Players[localPlayerID]:GetTrade();
	local routesActive	:number = playerTrade:GetNumOutgoingRoutes();
	local routesCapacity:number = playerTrade:GetOutgoingRouteCapacity();
	Controls.HeaderLabel:SetText(Locale.ToUpper("LOC_TRADE_OVERVIEW_MY_ROUTES"));
	Controls.ActiveRoutesLabel:SetHide(false);

	-- If our active routes exceed our route capacity then color active route number red
	local routesActiveText:string = ""
	if routesActive > routesCapacity then
		routesActiveText = "[COLOR_RED]" .. tostring(routesActive) .. "[ENDCOLOR]";
	else
		routesActiveText = tostring(routesActive);
	end
	Controls.ActiveRoutesLabel:SetText(Locale.Lookup("LOC_TRADE_OVERVIEW_ACTIVE_ROUTES", routesActiveText, routesCapacity));

	-- Gather data and sort
	local routesSortedByPlayer:table = {};
	local localPlayerCities:table = Players[Game.GetLocalPlayer()]:GetCities();
	for i,city in localPlayerCities:Members() do
		local outgoingRoutes = city:GetTrade():GetOutgoingRoutes();
		for i,route in ipairs(outgoingRoutes) do
			-- Make sure we have a table for each destination player
			if routesSortedByPlayer[route.DestinationCityPlayer] == nil then
				local routes:table = {};
				routesSortedByPlayer[route.DestinationCityPlayer] = {};
			end

			table.insert(routesSortedByPlayer[route.DestinationCityPlayer], route);
		end
	end

	-- Add routes to local player cities
	if routesSortedByPlayer[Game.GetLocalPlayer()] ~= nil then
		CreatePlayerHeader(Players[Game.GetLocalPlayer()]);

		for i,route in ipairs(routesSortedByPlayer[Game.GetLocalPlayer()]) do
			AddRouteFromRouteInfo(route);
		end
	end

	-- Add routes to other civs
	local haveAddedCityStateHeader:boolean = false;
	for playerID,routes in pairs(routesSortedByPlayer) do
		if playerID ~= Game.GetLocalPlayer() then
			-- Skip City States as these are added below
			local playerInfluence:table = Players[playerID]:GetInfluence();
			if not playerInfluence:CanReceiveInfluence() then
				CreatePlayerHeader(Players[playerID]);

				for i,route in ipairs(routes) do
					AddRouteFromRouteInfo(route);
				end
			else
				-- Add city state routes
				if not haveAddedCityStateHeader then
					haveAddedCityStateHeader = true;
					CreateCityStateHeader();
				end

				for i,route in ipairs(routes) do
					AddRouteFromRouteInfo(route);
				end
			end
		end
	end

	-- Determine how many unused routes we have
	local unusedRoutes	:number = routesCapacity - routesActive;
	if unusedRoutes > 0 then
		CreateUnusedRoutesHeader();

		local idleTradeUnits:table = GetIdleTradeUnits(Game.GetLocalPlayer());

		-- Assign idle trade units to unused routes
		for i=1,unusedRoutes,1 do
			if #idleTradeUnits > 0 then
				-- Add button to choose a route for this trader
				AddChooseRouteButton(idleTradeUnits[1]);
				table.remove(idleTradeUnits, 1);
			else
				-- Add button to produce new trade unit
				AddProduceTradeUnitButton();
			end
		end
	end
end

-- Show Routes To My Cities Tab
function ViewRoutesToCities()
	-- Update Tabs
	SetMyRoutesTabSelected(false);
	SetRoutesToCitiesTabSelected(true);
	SetAvailableRoutesTabSelected(false);

	-- Update Header
	Controls.HeaderLabel:SetText(Locale.ToUpper("LOC_TRADE_OVERVIEW_ROUTES_TO_MY_CITIES"));
	Controls.ActiveRoutesLabel:SetHide(true);

	-- Gather data and sort
	local routesSortedByPlayer:table = {};
	local players = Game.GetPlayers();
	for _, player in ipairs(players) do
		-- Don't show domestic routes
		if player:GetID() ~= Game.GetLocalPlayer() then	
			local playerCities:table = player:GetCities();
			for _, city in playerCities:Members() do
				local outgoingRoutes = city:GetTrade():GetOutgoingRoutes();
				for _, route in ipairs(outgoingRoutes) do
					-- Check that the destination city owner is the local player
					if route.DestinationCityPlayer == Game.GetLocalPlayer() then
						-- Make sure we have a table for each destination player
						if routesSortedByPlayer[route.OriginCityPlayer] == nil then
							routesSortedByPlayer[route.OriginCityPlayer] = {};
						end
						table.insert(routesSortedByPlayer[route.OriginCityPlayer], route);
					end
				end
			end
		end
	end

	-- Add civ routes to stack
	local cityStateRoutes:table = {};
	for playerID, routes in pairs(routesSortedByPlayer) do
		local playerInfluence:table = Players[playerID]:GetInfluence();
		if not playerInfluence:CanReceiveInfluence() then
			CreatePlayerHeader(Players[playerID]);

			for i,route in ipairs(routes) do
				AddRouteFromRouteInfo(route);
			end
		else
			table.insert(cityStateRoutes, routes);
		end
	end

	-- Add city state routes to stack
	local haveAddedCityStateHeader:boolean = false;
	for _,routes in ipairs(cityStateRoutes) do
		if not haveAddedCityStateHeader then
			haveAddedCityStateHeader = true;
			CreateCityStateHeader();
		end

		for i,route in ipairs(routes) do
			AddRouteFromRouteInfo(route);
		end
	end
end

-- Show Available Routes Tab
function ViewAvailableRoutes()
	-- Update Tabs
	SetMyRoutesTabSelected(false);
	SetRoutesToCitiesTabSelected(false);
	SetAvailableRoutesTabSelected(true);

	local localPlayerID = Game.GetLocalPlayer();
	if (localPlayerID == -1) then
		return;
	end

	local tradeManager:table = Game.GetTradeManager();

	-- Update Header
	Controls.HeaderLabel:SetText(Locale.ToUpper("LOC_TRADE_OVERVIEW_AVAILABLE_ROUTES"));
	Controls.ActiveRoutesLabel:SetHide(true);

	-- Determine if a trade unit in a city can trade with any other player cities
	local pLocalPlayer:table = Players[localPlayerID];
	local pLocalPlayerCities:table = pLocalPlayer:GetCities();
	local hasTradeRouteWithPlayer:boolean = false;
	local hasTradeRouteWithCityStates:boolean = false;
	local players:table = Game.GetPlayers();
	for i, destinationPlayer in ipairs(players) do
		local playerHeader:table = nil;
		hasTradeRouteWithPlayer = false;

		local cities:table = destinationPlayer:GetCities();
		for j, destinationCity in cities:Members() do
			for cityID in pLocalPlayerCities:Members() do
				local originCity = pLocalPlayerCities:FindID(cityID);
				if originCity ~= nil then
					if tradeManager:CanStartRoute(originCity:GetOwner(), originCity:GetID(), destinationCity:GetOwner(), destinationCity:GetID(), true) then
						-- Add Civ/CityState Header
						local pPlayerInfluence:table = destinationPlayer:GetInfluence();
						if not pPlayerInfluence:CanReceiveInfluence() then
							-- If first available route with this city add a city header
							if not hasTradeRouteWithPlayer then
								hasTradeRouteWithPlayer = true;
								CreatePlayerHeader(destinationPlayer);
							end
						else
							-- If first available route to a city state then add a city state header
							if not hasTradeRouteWithCityStates then
								hasTradeRouteWithCityStates = true;
								CreateCityStateHeader();
							end
						end
						
						-- Add Route
						AddRoute(pLocalPlayer, originCity, destinationPlayer, destinationCity, -1);
					end
				end
			end
		end
	end
end

-- ===========================================================================
function SetMyRoutesTabSelected( isSelected:boolean )
	Controls.MyRoutesButton:SetSelected(isSelected);
	Controls.MyRoutesTabLabel:SetHide(isSelected);
	Controls.MyRoutesSelected:SetHide(not isSelected);
	Controls.MyRoutesSelectedArrow:SetHide(not isSelected);
	Controls.MyRoutesTabSelectedLabel:SetHide(not isSelected);
end

-- ===========================================================================
function SetRoutesToCitiesTabSelected( isSelected:boolean )
	Controls.RoutesToCitiesButton:SetSelected(isSelected);
	Controls.RoutesToCitiesTabLabel:SetHide(isSelected);
	Controls.RoutesToCitiesSelected:SetHide(not isSelected);
	Controls.RoutesToCitiesSelectedArrow:SetHide(not isSelected);
	Controls.RoutesToCitiesTabSelectedLabel:SetHide(not isSelected);
end

-- ===========================================================================
function SetAvailableRoutesTabSelected( isSelected:boolean )
	Controls.AvailableRoutesButton:SetSelected(isSelected);
	Controls.AvailableRoutesTabLabel:SetHide(isSelected);
	Controls.AvailableRoutesSelected:SetHide(not isSelected);
	Controls.AvailableRoutesSelectedArrow:SetHide(not isSelected);
	Controls.AvailableRoutesTabSelectedLabel:SetHide(not isSelected);
end

-- ===========================================================================
function AddChooseRouteButton( tradeUnit:table )
	local simpleButtonInstance:table = m_SimpleButtonInstanceIM:GetInstance();
	simpleButtonInstance.GridButton:SetText(Locale.Lookup("LOC_TRADE_OVERVIEW_CHOOSE_ROUTE"));
	simpleButtonInstance.GridButton:SetDisabled(false);
	table.insert( m_srRecords, { kind = "slot", section = m_srSection, traderID = tradeUnit:GetID(), n = #m_srRecords + 1 } );		-- ScreenReaderAccess
	simpleButtonInstance.GridButton:RegisterCallback( Mouse.eLClick, 
		function()
			SelectUnit( tradeUnit );
		end
	);
end

-- ===========================================================================
function SelectUnit( unit:table )
	local localPlayer = Game.GetLocalPlayer();
	if UI.GetHeadSelectedUnit() ~= unit and localPlayer ~= -1 and localPlayer == unit:GetOwner() then
		UI.DeselectAllUnits();
		UI.DeselectAllCities();
		UI.SelectUnit( unit );
	end
	UI.LookAtPlotScreenPosition( unit:GetX(), unit:GetY(), 0.42, 0.5 );
end

-- ===========================================================================
function AddProduceTradeUnitButton()
	local simpleButtonInstance:table = m_SimpleButtonInstanceIM:GetInstance();
	simpleButtonInstance.GridButton:SetText(Locale.Lookup("LOC_TRADE_OVERVIEW_PRODUCE_TRADE_UNIT"));
	simpleButtonInstance.GridButton:SetDisabled(true);
	table.insert( m_srRecords, { kind = "slot", section = m_srSection, n = #m_srRecords + 1 } );		-- ScreenReaderAccess
end

-- ===========================================================================
function AddRouteFromRouteInfo(routeInfo:table)
	local originPlayer:table = Players[routeInfo.OriginCityPlayer];
	local originCity:table = originPlayer:GetCities():FindID(routeInfo.OriginCityID);

	local destinationPlayer:table = Players[routeInfo.DestinationCityPlayer];
	local destinationCity:table = destinationPlayer:GetCities():FindID(routeInfo.DestinationCityID);

	AddRoute(originPlayer, originCity, destinationPlayer, destinationCity, routeInfo.TraderUnitID);
	m_srRecords[ #m_srRecords ].info = routeInfo;		-- ScreenReaderAccess
end

-- ===========================================================================
function AddRoute(originPlayer:table, originCity:table, destinationPlayer:table, destinationCity:table, traderUnitID:number)
	local routeInstance:table = m_RouteInstanceIM:GetInstance();
	table.insert( m_srRecords, { kind = "route", section = m_srSection, tab = m_currentTab, traderID = traderUnitID,
		op = originPlayer:GetID(), oc = originCity:GetID(), dp = destinationPlayer:GetID(), dc = destinationCity:GetID() } );		-- ScreenReaderAccess
						
	-- Update Route Label
	routeInstance.RouteLabel:SetText(Locale.ToUpper(originCity:GetName()) .. " " .. Locale.ToUpper("LOC_TRADE_OVERVIEW_TO") .. " " .. Locale.ToUpper(destinationCity:GetName()));

	-- Update Route Yields
	routeInstance.ResourceStack:DestroyAllChildren();
	routeInstance.NoBenefitsLabel:SetHide(false);

	-- XOR used to show right benefits when origin/destination switch between tabs
	local kRouteInfo:table = {};
	if m_showMyBenefits == not (m_currentTab == TRADE_TABS.ROUTES_TO_CITIES) then
		kRouteInfo = GetYieldsForRoute(originCity, destinationCity);
	else
		kRouteInfo = GetYieldsForRoute(originCity, destinationCity, true);
	end

	for yieldIndex=1, #kRouteInfo.kYieldValues, 1 do

		local yieldValue = kRouteInfo.kYieldValues[yieldIndex];

		if (yieldValue ~= 0 ) then

			local yieldInfo = GameInfo.Yields[yieldIndex - 1];

			local resourceInstance:table = {};
			ContextPtr:BuildInstanceForControl( "ResourceInstance", resourceInstance, routeInstance.ResourceStack );
								
			resourceInstance.ResourceIconLabel:SetText(yieldInfo.IconString);
			resourceInstance.ResourceValueLabel:SetText("+" .. Round(yieldValue,1));

			-- Set tooltip to resouce name
			resourceInstance.Top:LocalizeAndSetToolTip(yieldInfo.Name);

			-- Update Label Color
			if (yieldInfo.YieldType == "YIELD_FOOD") then
				resourceInstance.ResourceValueLabel:SetColorByName("ResFoodLabelCS");
			elseif (yieldInfo.YieldType == "YIELD_PRODUCTION") then
				resourceInstance.ResourceValueLabel:SetColorByName("ResProductionLabelCS");
			elseif (yieldInfo.YieldType == "YIELD_GOLD") then
				resourceInstance.ResourceValueLabel:SetColorByName("ResGoldLabelCS");
			elseif (yieldInfo.YieldType == "YIELD_SCIENCE") then
				resourceInstance.ResourceValueLabel:SetColorByName("ResScienceLabelCS");
			elseif (yieldInfo.YieldType == "YIELD_CULTURE") then
				resourceInstance.ResourceValueLabel:SetColorByName("ResCultureLabelCS");
			elseif (yieldInfo.YieldType == "YIELD_FAITH") then
				resourceInstance.ResourceValueLabel:SetColorByName("ResFaithLabelCS");
			end

			routeInstance.NoBenefitsLabel:SetHide(true);
		end
	end
	routeInstance.ResourceStack:CalculateSize();

	routeInstance.GridButton:SetToolTipString(kRouteInfo.TooltipText);

	-- If showing benefits for my city then the destinations religions pressure will be shown
	local influencingCity:table = nil;
	local influencedCity:table = nil;
	-- XOR used to show right benefits when origin/destination switch between tabs
	if m_showMyBenefits == not (m_currentTab == TRADE_TABS.ROUTES_TO_CITIES) then
		influencingCity = destinationCity;
		influencedCity = originCity;
	else
		influencingCity = originCity;
		influencedCity = destinationCity;
	end

	-- Show the religions pressure from the influencing city
	if kRouteInfo.MajorityReligion > 0 and kRouteInfo.ReligionPressure > 0 then
		local religionInfo:table = GameInfo.Religions[kRouteInfo.MajorityReligion];
		local iconName:string = DATA_ICON_PREFIX .. religionInfo.ReligionType;
		local majorityReligionColor:number = UI.GetColorValue(religionInfo.Color);
		
		if majorityReligionColor ~= nil then
			routeInstance.ReligionPressureIcon:SetColor(majorityReligionColor);
		end
		local textureOffsetX, textureOffsetY, textureSheet = IconManager:FindIconAtlas(iconName,22);
		if textureOffsetX ~= nil then
			routeInstance.ReligionPressureIcon:SetTexture( textureOffsetX, textureOffsetY, textureSheet );
		end

		routeInstance.ReligionPressureValue:SetColor(UI.GetColorValue(religionInfo.Color));
		routeInstance.ReligionPressureValue:SetText("+" .. Round(kRouteInfo.ReligionPressure,1));
		
		routeInstance.ReligionPressureContainer:SetToolTipString(Locale.Lookup(religionInfo.Name));
		routeInstance.ReligionPressureContainer:SetHide(false);

		routeInstance.NoBenefitsLabel:SetHide(true);
	else
		routeInstance.ReligionPressureContainer:SetHide(true);
	end

	-- Update Trading Post Icon
	if destinationCity:GetTrade():HasActiveTradingPost(originPlayer) then
		routeInstance.TradingPostIndicator:SetAlpha(1.0);
		routeInstance.TradingPostIndicator:LocalizeAndSetToolTip("LOC_TRADE_OVERVIEW_TOOLTIP_TRADE_POST_ESTABLISHED");
	else
		routeInstance.TradingPostIndicator:SetAlpha(0.2);
		routeInstance.TradingPostIndicator:LocalizeAndSetToolTip("LOC_TRADE_OVERVIEW_TOOLTIP_NO_TRADE_POST");
	end

	-- Update Path Bonus Icon
	routeInstance.RouteBonusIcon:SetHide(not kRouteInfo.HasPathBonus);

	-- Update distance to city
	local distanceToDestination:number = Map.GetPlotDistance(originCity:GetX(), originCity:GetY(), destinationCity:GetX(), destinationCity:GetY());
	routeInstance.RouteDistance:SetText(distanceToDestination);

	-- Update Origin Civ Icon
	local originPlayerConfig:table = PlayerConfigurations[originPlayer:GetID()];
	local originPlayerIconString:string = "ICON_" .. originPlayerConfig:GetCivilizationTypeName();
	local textureOffsetX, textureOffsetY, textureSheet = IconManager:FindIconAtlas(originPlayerIconString, 30);
	local secondaryColor, primaryColor = UI.GetPlayerColors( originPlayer:GetID() );
	routeInstance.OriginCivIcon:SetTexture(textureOffsetX, textureOffsetY, textureSheet);
	routeInstance.OriginCivIcon:LocalizeAndSetToolTip( originPlayerConfig:GetCivilizationDescription() );
	routeInstance.OriginCivIcon:SetColor( primaryColor );
	routeInstance.OriginCivIconBacking:SetColor( secondaryColor );

	local destinationPlayerConfig:table = PlayerConfigurations[destinationPlayer:GetID()];
	local destinationPlayerInfluence:table = Players[destinationPlayer:GetID()]:GetInfluence();
	if not destinationPlayerInfluence:CanReceiveInfluence() then
		-- Destination Icon for Civilizations
		if destinationPlayerConfig ~= nil then
			local iconString:string = "ICON_" .. destinationPlayerConfig:GetCivilizationTypeName();
			local textureOffsetX, textureOffsetY, textureSheet = IconManager:FindIconAtlas(iconString, 30);
			routeInstance.DestinationCivIcon:SetTexture(textureOffsetX, textureOffsetY, textureSheet);
			routeInstance.DestinationCivIcon:LocalizeAndSetToolTip( destinationPlayerConfig:GetCivilizationDescription() );
		end

		local secondaryColor, primaryColor = UI.GetPlayerColors( destinationPlayer:GetID() );
		routeInstance.DestinationCivIcon:SetColor(primaryColor);
		routeInstance.DestinationCivIconBacking:SetColor(secondaryColor);
	else
		-- Destination Icon for City States
		if destinationPlayerConfig ~= nil then
			local secondaryColor, primaryColor = UI.GetPlayerColors( destinationPlayer:GetID() );
			local leader		:string = destinationPlayerConfig:GetLeaderTypeName();
			local leaderInfo	:table	= GameInfo.Leaders[leader];

			local iconString:string = GetCityStateIcon(leader, leaderInfo);
			if iconString ~= nil then
				local textureOffsetX, textureOffsetY, textureSheet = IconManager:FindIconAtlas(iconString, 30);
				routeInstance.DestinationCivIcon:SetTexture(textureOffsetX, textureOffsetY, textureSheet);
				routeInstance.DestinationCivIcon:SetColor(primaryColor);
				routeInstance.DestinationCivIconBacking:SetColor(secondaryColor);
				routeInstance.DestinationCivIcon:LocalizeAndSetToolTip( destinationCity:GetName() );
			end
		end
	end

	-- Update Benefits Arrow
	-- XOR used to show right benefits when origin/destination switch between tabs
	if m_showMyBenefits == not (m_currentTab == TRADE_TABS.ROUTES_TO_CITIES) then
		local primaryColor, secondaryColor = UI.GetPlayerColors( originPlayer:GetID() );
		routeInstance.OriginCivArrow:SetHide(false);
		routeInstance.OriginCivArrow:SetColor(secondaryColor);
		routeInstance.DestinationCivArrow:SetHide(true);
	else
		local primaryColor, secondaryColor = UI.GetPlayerColors( destinationPlayer:GetID() );
		routeInstance.OriginCivArrow:SetHide(true);
		routeInstance.DestinationCivArrow:SetHide(false);
		routeInstance.DestinationCivArrow:SetColor(secondaryColor);
	end

	-- Update route status icon
	if m_currentTab == TRADE_TABS.MY_ROUTES then
		routeInstance.RouteStatusFontIcon:SetHide(false);
	else
		routeInstance.RouteStatusFontIcon:SetHide(true);
	end

	-- Find trader unit and set button callback to select that unit
	if tradeUnitID and tradeUnitID ~= -1 then
		local tradeUnit:table = originPlayer:GetUnits():FindID(traderUnitID);
		if tradeUnit then
			if m_currentTab == TRADE_TABS.AVAILABLE_ROUTES then
				-- If selecting an available route, select unit and select route in route chooser
				routeInstance.GridButton:RegisterCallback( Mouse.eLClick, 
					function()
						SelectUnit( tradeUnit );
						LuaEvents.TradeOverview_SelectRouteFromOverview( destinationPlayer:GetID(), destinationCity:GetID() );
					end
				);
			else
				routeInstance.GridButton:RegisterCallback( Mouse.eLClick, 
					function()
						SelectUnit( tradeUnit );
					end
				);
			end
		end
	end
end

-- ===========================================================================
function GetCityStateIcon(leaderName:string, leaderInfo:table)
	local iconString:string;

	if (leader == "LEADER_MINOR_CIV_SCIENTIFIC" or leaderInfo.InheritFrom == "LEADER_MINOR_CIV_SCIENTIFIC") then				
		iconString = "ICON_CITYSTATE_SCIENCE";
	elseif (leader == "LEADER_MINOR_CIV_RELIGIOUS" or leaderInfo.InheritFrom == "LEADER_MINOR_CIV_RELIGIOUS") then
		iconString = "ICON_CITYSTATE_FAITH";
	elseif (leader == "LEADER_MINOR_CIV_TRADE" or leaderInfo.InheritFrom == "LEADER_MINOR_CIV_TRADE") then
		iconString = "ICON_CITYSTATE_TRADE";
	elseif (leader == "LEADER_MINOR_CIV_CULTURAL" or leaderInfo.InheritFrom == "LEADER_MINOR_CIV_CULTURAL") then
		iconString = "ICON_CITYSTATE_CULTURE";
	elseif (leader == "LEADER_MINOR_CIV_MILITARISTIC" or leaderInfo.InheritFrom == "LEADER_MINOR_CIV_MILITARISTIC") then
		iconString = "ICON_CITYSTATE_MILITARISTIC";
	elseif (leader == "LEADER_MINOR_CIV_INDUSTRIAL" or leaderInfo.InheritFrom == "LEADER_MINOR_CIV_INDUSTRIAL") then
		iconString = "ICON_CITYSTATE_INDUSTRIAL";
	end

	return iconString;
end

-- ===========================================================================
function Refresh()
	PreRefresh();

	if m_currentTab == TRADE_TABS.MY_ROUTES then
		ViewMyRoutes();
	elseif m_currentTab == TRADE_TABS.ROUTES_TO_CITIES then
		ViewRoutesToCities();
	elseif m_currentTab == TRADE_TABS.AVAILABLE_ROUTES then
		ViewAvailableRoutes();
	end

	PostRefresh();
end

-- ===========================================================================
function PreRefresh()
	-- Reset Stack
	m_RouteInstanceIM:ResetInstances();
	m_HeaderInstanceIM:ResetInstances();
	m_SimpleButtonInstanceIM:ResetInstances();

	m_srRecords = {};		-- ScreenReaderAccess
	m_srSection = nil;		-- ScreenReaderAccess
end

-- ===========================================================================
function PostRefresh()
	-- Calculate Stack Sizes
	Controls.BodyScrollPanel:CalculateSize();
end

-- ===========================================================================
function SetBenefitsFilter(showMyBenefits:boolean)
	if showMyBenefits == nil then
		return;
	end

	m_showMyBenefits = showMyBenefits;

	if m_showMyBenefits then
		Controls.BenefitsLabel:SetText(Locale.Lookup("LOC_TRADE_OVERVIEW_MY_BENEFITS"));
	else
		Controls.BenefitsLabel:SetText(Locale.Lookup("LOC_TRADE_OVERVIEW_THEIR_BENEFITS"));
	end

	Refresh();
end

-- Create Player Header Instance
function CreatePlayerHeader(player:table)
	local headerInstance:table = m_HeaderInstanceIM:GetInstance();

	local pPlayerConfig:table = PlayerConfigurations[player:GetID()];
	headerInstance.HeaderLabel:SetText(Locale.ToUpper(pPlayerConfig:GetPlayerName()));
	m_srSection = Locale.Lookup(pPlayerConfig:GetPlayerName());		-- ScreenReaderAccess

	-- Determine are diplomatic visibility status
	local visibilityIndex:number = Players[Game.GetLocalPlayer()]:GetDiplomacy():GetVisibilityOn(player);

	-- Determine this player has a trade route with the local player
	local hasTradeRoute:boolean = false;
	local localPlayer = Game.GetLocalPlayer();
	local playerCities:table = player:GetCities();
	for i,city in playerCities:Members() do
		if city:GetTrade():HasTradeRouteFrom(localPlayer) then
			hasTradeRoute = true;
			break;
		end
	end

	-- Display trade route tourism modifier
	local baseTourismModifier = GlobalParameters.TOURISM_TRADE_ROUTE_BONUS;
	local extraTourismModifier = Players[Game.GetLocalPlayer()]:GetCulture():GetExtraTradeRouteTourismModifier();
	-- TODO: Use LOC_TRADE_OVERVIEW_TOURISM_BONUS when we can update the text
	headerInstance.TourismBonusPercentage:SetText("+" .. Locale.ToPercent((baseTourismModifier + extraTourismModifier)/100));

	if hasTradeRoute then
		headerInstance.TourismBonusCheckmark:SetHide(false);
		headerInstance.TourismBonusPercentage:SetColorByName("TradeOverviewTextCS");
		headerInstance.TourismBonusIcon:SetTexture(0,0,"Tourism_VisitingSmall");
		headerInstance.TourismBonusGrid:LocalizeAndSetToolTip("LOC_TRADE_OVERVIEW_TOOLTIP_TOURISM_BONUS");

		headerInstance.VisibilityBonusCheckmark:SetHide(false);
		headerInstance.VisibilityBonusIcon:SetTexture("Diplomacy_VisibilityIcons");
		headerInstance.VisibilityBonusIcon:SetVisState(math.min(math.max(visibilityIndex - 1, 0), 3));
		headerInstance.VisibilityBonusGrid:LocalizeAndSetToolTip("LOC_TRADE_OVERVIEW_TOOLTIP_DIPLOMATIC_VIS_BONUS");
	else
		headerInstance.TourismBonusCheckmark:SetHide(true);
		headerInstance.TourismBonusPercentage:SetColorByName("TradeOverviewTextDisabledCS");
		headerInstance.TourismBonusIcon:SetTexture(0,0,"Tourism_VisitingSmallGrey");
		headerInstance.TourismBonusGrid:LocalizeAndSetToolTip("LOC_TRADE_OVERVIEW_TOOLTIP_NO_TOURISM_BONUS");

		headerInstance.VisibilityBonusCheckmark:SetHide(true);
		headerInstance.VisibilityBonusIcon:SetTexture("Diplomacy_VisibilityIconsGrey");
		headerInstance.VisibilityBonusIcon:SetVisState(math.min(math.max(visibilityIndex, 0), 3));
		headerInstance.VisibilityBonusGrid:LocalizeAndSetToolTip("LOC_TRADE_OVERVIEW_TOOLTIP_NO_DIPLOMATIC_VIS_BONUS");
	end

	headerInstance.TourismBonusGrid:SetHide(false);
	headerInstance.VisibilityBonusGrid:SetHide(false);
end

-- Create City State Header Instance
function CreateCityStateHeader()
	local headerInstance:table = m_HeaderInstanceIM:GetInstance();

	headerInstance.HeaderLabel:SetText(Locale.ToUpper("LOC_TRADE_OVERVIEW_CITY_STATES"));
	m_srSection = Locale.Lookup("LOC_TRADE_OVERVIEW_CITY_STATES");		-- ScreenReaderAccess

	headerInstance.VisibilityBonusGrid:SetHide(true);
	headerInstance.TourismBonusGrid:SetHide(true);
end

-- Create Unused Routes Header Instance
function CreateUnusedRoutesHeader()
	local headerInstance:table = m_HeaderInstanceIM:GetInstance();

	headerInstance.HeaderLabel:SetText(Locale.ToUpper("LOC_TRADE_OVERVIEW_UNUSED_ROUTES"));
	m_srSection = Locale.Lookup("LOC_TRADE_OVERVIEW_UNUSED_ROUTES");		-- ScreenReaderAccess

	headerInstance.VisibilityBonusGrid:SetHide(true);
	headerInstance.TourismBonusGrid:SetHide(true);
end

-- ===========================================================================
function GetYieldsForDestinationCity(originCity:table, destinationCity:table)
	local tradeManager = Game.GetTradeManager();

	-- From route
	local routeYields = tradeManager:CalculateDestinationYieldsFromPotentialRoute(originCity:GetOwner(), originCity:GetID(), destinationCity:GetOwner(), destinationCity:GetID());
	-- From path
	local pathYields = tradeManager:CalculateDestinationYieldsFromPath(originCity:GetOwner(), originCity:GetID(), destinationCity:GetOwner(), destinationCity:GetID());
	-- From modifiers
	local modifierYields = tradeManager:CalculateDestinationYieldsFromModifiers(originCity:GetOwner(), originCity:GetID(), destinationCity:GetOwner(), destinationCity:GetID());

	-- Add the yields together and return the result
	local i;
	local yieldCount = #routeYields;

	for i=1, yieldCount, 1 do
		routeYields[i] = routeYields[i] + pathYields[i] + modifierYields[i];
	end

	return routeYields;
end

-- ===========================================================================
function Open()
	-- dont show panel if there is no local player
	local localPlayerID = Game.GetLocalPlayer();
	if (localPlayerID == -1) then
		return
	end

	m_AnimSupport.Show();
	UI.PlaySound("CityStates_Panel_Open");
end

-- ===========================================================================
function Close()	
    if not ContextPtr:IsHidden() then
        UI.PlaySound("CityStates_Panel_Close");
    end
	if m_AnimSupport.IsVisible() and not m_srQuiet then SRA_Closed(); end		-- ScreenReaderAccess
	m_AnimSupport.Hide();
end

-- ===========================================================================
function OnOpen()
	-- Default to My Routes
	OnMyRoutesButton();

	Open();
	SRA_ArmOpen();		-- ScreenReaderAccess
end

-- ===========================================================================
function OnMyRoutesButton()
	m_currentTab = TRADE_TABS.MY_ROUTES;
	Refresh();
end

-- ===========================================================================
function OnRoutesToCitiesButton()
	m_currentTab = TRADE_TABS.ROUTES_TO_CITIES;
	Refresh();
end

-- ===========================================================================
function OnAvailableRoutesButton()
	m_currentTab = TRADE_TABS.AVAILABLE_ROUTES;
	Refresh();
end

-- ===========================================================================
function OnClose()
	Close();
end

-- ===========================================================================
function OnBenefitsButton()
	if m_showMyBenefits then
		SetBenefitsFilter(false);
	else
		SetBenefitsFilter(true);
	end
end

-- ===========================================================================
--	LUA Event
--	Explicit close (from partial screen hooks), part of closing everything,
-- ===========================================================================
function OnCloseAllExcept( contextToStayOpen:string )
	if contextToStayOpen == ContextPtr:GetID() then return; end
	Close();
end

------------------------------------------------------------------------------------------------
function OnLocalPlayerTurnEnd()
	if(GameConfiguration.IsHotseat()) then
		Close();
	end
end

-- ===========================================================================
--	Game Event
-- ===========================================================================
function OnInterfaceModeChanged(eOldMode:number, eNewMode:number)
	if eNewMode == InterfaceModeTypes.VIEW_MODAL_LENS then
		Close();
	end
end

-- ===========================================================================
--	UI EVENT
-- ===========================================================================
function OnInit(isReload:boolean)
	if isReload then
		LuaEvents.GameDebug_GetValues(RELOAD_CACHE_ID);
	end
end

-- ===========================================================================
--	UI EVENT
-- ===========================================================================
function OnShutdown()
	SRUnlistenAll();		-- ScreenReaderAccess
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "isHidden", ContextPtr:IsHidden());
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "currentTab", m_currentTab);
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "showMyBenefits", m_showMyBenefits);
end

-- ===========================================================================
--	LUA EVENT
--	Reload support
-- ===========================================================================
function OnGameDebugReturn(context:string, contextTable:table)
	if context == RELOAD_CACHE_ID then
		if contextTable["showMyBenefits"] ~= nil and contextTable["showMyBenefits"] then
			SetBenefitsFilter(true);
		else
			SetBenefitsFilter(false);
		end
		if contextTable["isHidden"] ~= nil and not contextTable["isHidden"] then			
			Open();
		end
		if contextTable["currentTab"] ~= nil then
			m_currentTab = contextTable["currentTab"];
			Refresh();
		end
	end
end

-- ===========================================================================
function OnUnitOperationStarted(ownerID:number, unitID:number, operationID:number)
	if m_AnimSupport.IsVisible() and operationID == UnitOperationTypes.MAKE_TRADE_ROUTE then
		Refresh();
	end
end

-- ===========================================================================
function OnPolicyChanged( ePlayer )
	if m_AnimSupport.IsVisible() and ePlayer == Game.GetLocalPlayer() then
		Refresh();
	end
end

-- ===========================================================================
--	ScreenReaderAccess: keyboard navigation and speech (F4)
--	The game's own View* functions decide what is listed (they run on every Refresh); PreRefresh/AddRoute/the header
--	functions record each route, slot and section as plain ids in m_srRecords. Item texts are derived from the game's
--	state at key time (lazily: only the spoken item is computed). Opens 0.4 s after OnOpen with "Trade routes: 2 of 3
--	used. My routes, 2 routes. <first>, 1 of 2". Up/Down/Home/End move, Space = benefits, tooltip, distance, Left/Right
--	or Tab/Control+Tab switch the tab, B toggles my/their benefits, Enter: a route of mine selects its trader, an
--	available route selects an idle trader in the origin city and preselects the route in the route chooser, a free
--	slot selects its idle trader. Escape closes. Function keys pass through (F4 toggles the screen); every other
--	keyboard event is swallowed while the screen is open.
--	Turns left: the screen shows none; the route table is searched for a "turns remaining" field and its field names
--	are printed once to Lua.log ("TradeOverview route fields") for the next iteration.
-- ===========================================================================
local m_srList				:table = nil;
local m_srOpenPending		:boolean = false;
local m_srOpenDelay			:number = 0;
local m_srFieldsPrinted		:boolean = false;
local SRA_OPEN_DELAY		:number = 0.4;

local function SRA_Say( text:string, nointerrupt:boolean )
	OutputMessageToScreenReader( text, nointerrupt );
end

local function SRA_City( playerID:number, cityID:number )
	local player:table = Players[ playerID ];
	if player == nil then return nil; end
	return player:GetCities():FindID( cityID );
end

local function SRA_TabName()
	if m_currentTab == TRADE_TABS.ROUTES_TO_CITIES then return Locale.Lookup( "LOC_TRADE_OVERVIEW_ROUTES_TO_MY_CITIES" ); end
	if m_currentTab == TRADE_TABS.AVAILABLE_ROUTES then return Locale.Lookup( "LOC_TRADE_OVERVIEW_AVAILABLE_ROUTES" ); end
	return Locale.Lookup( "LOC_TRADE_OVERVIEW_MY_ROUTES" );
end

-- { { name, amount } } of the non-zero yields of a GetYieldsForRoute result
local function SRA_YieldList( kRouteInfo:table )
	local list:table = {};
	for yieldIndex = 1, #kRouteInfo.kYieldValues do
		local value = kRouteInfo.kYieldValues[ yieldIndex ];
		local yieldInfo = GameInfo.Yields[ yieldIndex - 1 ];
		if value ~= 0 and yieldInfo ~= nil then
			table.insert( list, { name = Locale.Lookup( yieldInfo.Name ), amount = value } );
		end
	end
	return list;
end

local function SRA_Pressure( kRouteInfo:table )
	if kRouteInfo.MajorityReligion > 0 and kRouteInfo.ReligionPressure > 0 then
		local religionInfo = GameInfo.Religions[ kRouteInfo.MajorityReligion ];
		if religionInfo ~= nil then
			return { name = Locale.Lookup( Game.GetReligion():GetName( religionInfo.Index ) ), amount = math.floor( kRouteInfo.ReligionPressure + 0.5 ) };
		end
	end
	return nil;
end

-- The route table of the game may carry a "turns remaining" number; no documented field, so look for one.
local function SRA_TurnsLeft( info:table )
	if info == nil then return nil; end
	if not m_srFieldsPrinted then
		m_srFieldsPrinted = true;
		local names:table = {};
		for k, v in pairs( info ) do table.insert( names, tostring( k ) .. "=" .. type( v ) ); end
		table.sort( names );
		print( "TradeOverview route fields: " .. table.concat( names, ", " ) );
	end
	for k, v in pairs( info ) do
		local name:string = string.lower( tostring( k ) );
		if type( v ) == "number" and string.find( name, "turn", 1, true ) ~= nil
			and ( string.find( name, "remain", 1, true ) ~= nil or string.find( name, "left", 1, true ) ~= nil ) then
			return v;
		end
	end
	return nil;
end

local function SRA_CityNameAt( unit:table )
	local city:table = Cities.GetCityInPlot( unit:GetX(), unit:GetY() );
	if city ~= nil then return Locale.Lookup( city:GetName() ); end
	return nil;
end

local function SRA_TraderText( rec:table )
	if rec.traderID == nil or rec.traderID == -1 then return nil; end
	local owner:table = Players[ rec.op ];
	local unit:table = owner ~= nil and owner:GetUnits():FindID( rec.traderID ) or nil;
	if unit == nil then return nil; end
	local city:string = SRA_CityNameAt( unit );
	if city ~= nil then return "trader in " .. city; end
	local near:table = Cities.GetPlotPurchaseCity( Map.GetPlot( unit:GetX(), unit:GetY() ) );
	if near ~= nil then return "trader near " .. Locale.Lookup( near:GetName() ); end
	return "trader on the way";
end

-- Everything one route item says, from the game's state now.
local function SRA_RouteView( rec:table )
	local oCity:table, dCity:table = SRA_City( rec.op, rec.oc ), SRA_City( rec.dp, rec.dc );
	if oCity == nil or dCity == nil then return nil; end
	-- same XOR as AddRoute: whose benefits the shown yields are
	local showOrigin:boolean = ( m_showMyBenefits == not ( rec.tab == TRADE_TABS.ROUTES_TO_CITIES ) );
	local originInfo:table = GetYieldsForRoute( oCity, dCity );
	local destInfo:table = GetYieldsForRoute( oCity, dCity, true );
	local shown:table, other:table = destInfo, originInfo;
	if showOrigin then shown, other = originInfo, destInfo; end
	return {
		oCity = oCity, dCity = dCity,
		oName = Locale.Lookup( oCity:GetName() ), dName = Locale.Lookup( dCity:GetName() ),
		shownName = Locale.Lookup( ( showOrigin and oCity or dCity ):GetName() ),
		otherName = Locale.Lookup( ( showOrigin and dCity or oCity ):GetName() ),
		shown = shown, other = other,
		distance = Map.GetPlotDistance( oCity:GetX(), oCity:GetY(), dCity:GetX(), dCity:GetY() ),
		tradingPost = dCity:GetTrade():HasActiveTradingPost( oCity:GetOwner() ),
	};
end

local function SRA_RouteText( rec:table )
	local view:table = SRA_RouteView( rec );
	if view == nil then return "Route no longer available"; end
	return TradeOverviewText_Route{
		origin = view.oName, destination = view.dName, yields = SRA_YieldList( view.shown ), pressure = SRA_Pressure( view.shown ),
		tradingPost = view.tradingPost, turns = SRA_TurnsLeft( rec.info ), trader = SRA_TraderText( rec ),
		distance = ( rec.tab == TRADE_TABS.AVAILABLE_ROUTES ) and view.distance or nil,
	};
end

local function SRA_RouteDetail( rec:table )
	local view:table = SRA_RouteView( rec );
	if view == nil then return "Route no longer available"; end
	return TradeOverviewText_Detail{
		tooltip = "Benefits for " .. view.shownName .. ". " .. CleanTextForSpeech( view.shown.TooltipText or "" ),
		theirName = view.otherName, theirYields = SRA_YieldList( view.other ),
		distance = view.distance, tradingPost = view.tradingPost, trader = SRA_TraderText( rec ),
	};
end

local function SRA_SlotTrader( rec:table )
	if rec.traderID == nil then return nil; end
	local unit:table = Players[ Game.GetLocalPlayer() ]:GetUnits():FindID( rec.traderID );
	if unit == nil then return nil; end
	return unit, SRA_CityNameAt( unit );
end

function SRA_BuildItems()
	local items:table = {};
	if Game.GetLocalPlayer() == -1 then return items; end
	for _, rec in ipairs( m_srRecords ) do
		local item:table;
		if rec.kind == "route" then
			item = { key = "r:" .. rec.tab .. ":" .. rec.op .. ":" .. rec.oc .. ":" .. rec.dp .. ":" .. rec.dc .. ":" .. tostring( rec.traderID ),
				section = rec.section, rec = rec, detail = function() return SRA_RouteDetail( rec ); end };
			setmetatable( item, { __index = function( t, k )
				if k == "text" then
					local v:string = SRA_RouteText( rec );
					t.text = v;
					return v;
				end
			end } );
		else
			local unit:table, where:string = SRA_SlotTrader( rec );
			item = { key = "slot:" .. rec.n, section = rec.section, rec = rec, text = TradeOverviewText_Slot{ trader = where },
				detail = unit ~= nil and "Enter selects the trader so you can choose a route" or "Build a trader in one of your cities, then choose its route" };
		end
		table.insert( items, item );
	end
	return items;
end

local function SRA_CountRoutes( items:table )
	local n:number = 0;
	for _, item in ipairs( items ) do
		if item.rec.kind == "route" then n = n + 1; end
	end
	return n;
end

-- Says the tab (with the screen's head when opening) and its first item; the focus goes to the first item.
local function SRA_AnnounceTab( opening:boolean )
	local items:table = SRA_BuildItems();
	local d:table = { tab = SRA_TabName(), count = SRA_CountRoutes( items ), total = #items, short = not opening };
	if opening and m_currentTab == TRADE_TABS.MY_ROUTES and Game.GetLocalPlayer() ~= -1 then
		local playerTrade:table = Players[ Game.GetLocalPlayer() ]:GetTrade();
		d.used, d.capacity = playerTrade:GetNumOutgoingRoutes(), playerTrade:GetOutgoingRouteCapacity();
	end
	if #items > 0 then
		m_srList.Open( "", nil, true );
		d.first, d.index = items[1].text, 1;
		if items[1].section ~= nil then d.first = items[1].section .. ": " .. d.first; end
	end
	SRA_Say( TradeOverviewText_Opening( d ), opening );
end

local function SRA_CloseQuiet()
	m_srQuiet = true;
	Close();
	m_srQuiet = false;
end

local function SRA_FindUnit( playerID:number, unitID:number )
	local player:table = Players[ playerID ];
	if player == nil or unitID == nil or unitID == -1 then return nil; end
	return player:GetUnits():FindID( unitID );
end

local function SRA_StartAvailable( rec:table )
	local oCity:table, dCity:table = SRA_City( rec.op, rec.oc ), SRA_City( rec.dp, rec.dc );
	if oCity == nil or dCity == nil then SRA_Say( "Route no longer available" ); return; end
	local traders:table = GetIdleTradeUnits( Game.GetLocalPlayer() );
	local chosen:table = nil;
	for _, unit in ipairs( traders ) do
		local city:table = Cities.GetCityInPlot( unit:GetX(), unit:GetY() );
		if city ~= nil and city:GetOwner() == oCity:GetOwner() and city:GetID() == oCity:GetID() then chosen = unit; break; end
	end
	if chosen == nil then
		if #traders == 0 then
			SRA_Say( "No idle trader. Build a trader first" );
		else
			SRA_Say( "No idle trader in " .. Locale.Lookup( oCity:GetName() ) .. ". Move a trader there first" );
		end
		return;
	end
	SelectUnit( chosen );
	LuaEvents.TradeOverview_SelectRouteFromOverview( rec.dp, rec.dc );
	SRA_CloseQuiet();
end

local function SRA_OnActivate( item:table )
	local rec:table = item.rec;
	if rec.kind == "slot" then
		local unit:table = SRA_FindUnit( Game.GetLocalPlayer(), rec.traderID );
		if unit == nil then SRA_Say( "No idle trader. Build a trader in one of your cities first" ); return; end
		SelectUnit( unit );
		SRA_CloseQuiet();
	elseif rec.tab == TRADE_TABS.AVAILABLE_ROUTES then
		SRA_StartAvailable( rec );
	elseif rec.tab == TRADE_TABS.MY_ROUTES then
		local unit:table = SRA_FindUnit( rec.op, rec.traderID );
		if unit == nil then SRA_Say( "Trader not found" ); return; end
		SelectUnit( unit );
		SRA_CloseQuiet();
	else
		SRA_Say( "A route of another civilization. Space reads the details" );
	end
end

local function SRA_SwitchTab( delta:number )
	local tab:number = ( m_currentTab + delta ) % 3;
	if tab == TRADE_TABS.MY_ROUTES then
		OnMyRoutesButton();
	elseif tab == TRADE_TABS.ROUTES_TO_CITIES then
		OnRoutesToCitiesButton();
	else
		OnAvailableRoutesButton();
	end
	m_srList.Reset();
	SRA_AnnounceTab( false );
end

local function SRA_ToggleBenefits()
	OnBenefitsButton();
	SRA_Say( m_showMyBenefits and "Showing my benefits" or "Showing their benefits" );
end

function SRA_Closed()
	SRA_Say( "Trade routes closed" );
end

function SRA_CreateList()
	m_srList = KeyNavList_Create{
		build = SRA_BuildItems,
		isActive = function() return m_AnimSupport ~= nil and m_AnimSupport.IsVisible(); end,
		onActivate = SRA_OnActivate,
		onClose = function() Close(); end,
		extraKeys = {
			[ Keys.VK_LEFT ] = function() SRA_SwitchTab( -1 ); end,
			[ Keys.VK_RIGHT ] = function() SRA_SwitchTab( 1 ); end,
			[ Keys.B ] = SRA_ToggleBenefits,
			[ Gamepad.Key( "X" ) ] = SRA_ToggleBenefits,
		},
	};
end

function SRA_ArmOpen()
	m_srList.Reset();
	m_srOpenPending = true;
	m_srOpenDelay = SRA_OPEN_DELAY;
end

function SRA_OnUpdate( deltaTime:number )
	if not m_srOpenPending then return; end
	if ContextPtr:IsHidden() then m_srOpenPending = false; return; end
	m_srOpenDelay = m_srOpenDelay - deltaTime;
	if m_srOpenDelay > 0 then return; end
	m_srOpenPending = false;
	local ok:boolean, err = xpcall( function() SRA_AnnounceTab( true ); end, KeyNavErrorHandler );
	if not ok then print( "TradeOverview announce error: " .. tostring( err ) ); end
end

local function SRA_IsFunctionKey( key:number )
	for n = 1, 12 do
		if Keys[ "VK_F" .. n ] ~= nil and Keys[ "VK_F" .. n ] == key then return true; end
	end
	return false;
end

function SRA_HandleInput( input:table )
	if m_AnimSupport == nil or not m_AnimSupport.IsVisible() then return false; end
	local msg:number = input:GetMessageType();
	if msg ~= KeyEvents.KeyDown and msg ~= KeyEvents.KeyUp then return false; end
	local key:number = input:GetKey();
	if SRA_IsFunctionKey( key ) then return false; end
	if key == Keys.VK_TAB then
		if msg == KeyEvents.KeyUp then
			local delta:number = ( input:IsShiftDown() or input:IsControlDown() ) and -1 or 1;
			local ok:boolean, err = xpcall( function() SRA_SwitchTab( delta ); end, KeyNavErrorHandler );
			if not ok then print( "TradeOverview tab error: " .. tostring( err ) ); end
		end
		return true;
	end
	m_srList.HandleInput( input );
	return true;		-- everything else is swallowed while the screen is open
end

function SRA_InputHandler( input:table )
	if SRA_HandleInput( input ) then return true; end
	return m_AnimSupport.OnInputHandler( input );
end
print( "ScreenReaderAccess: TradeOverview copy loaded" );

-- ===========================================================================
function Initialize()
	-- Control Events
	Controls.CloseButton:RegisterCallback(Mouse.eLClick, OnClose);
	Controls.CloseButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	Controls.MyRoutesButton:RegisterCallback(Mouse.eLClick,			OnMyRoutesButton);
	Controls.MyRoutesButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	Controls.RoutesToCitiesButton:RegisterCallback(Mouse.eLClick,	OnRoutesToCitiesButton);
	Controls.RoutesToCitiesButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	Controls.AvailableRoutesButton:RegisterCallback(Mouse.eLClick,	OnAvailableRoutesButton);
	Controls.AvailableRoutesButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	Controls.BenefitsButton:RegisterCallback(Mouse.eLClick,			OnBenefitsButton);
	Controls.BenefitsButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);

	-- Lua Events
	SRListen( LuaEvents.PartialScreenHooks_OpenTradeOverview, OnOpen );		-- ScreenReaderAccess
	SRListen( LuaEvents.PartialScreenHooks_CloseTradeOverview, OnClose );		-- ScreenReaderAccess
	SRListen( LuaEvents.PartialScreenHooks_CloseAllExcept, OnCloseAllExcept );		-- ScreenReaderAccess

	-- Animation Controller
	m_AnimSupport = CreateScreenAnimation(Controls.SlideAnim);

	-- Rundown / Screen Events
	SRListen( Events.SystemUpdateUI, m_AnimSupport.OnUpdateUI );		-- ScreenReaderAccess
	ContextPtr:SetInputHandler(SRA_InputHandler, true);		-- ScreenReaderAccess (was m_AnimSupport.OnInputHandler)
	ContextPtr:SetUpdate(SRA_OnUpdate);		-- ScreenReaderAccess
	SRA_CreateList();		-- ScreenReaderAccess

	Controls.Title:SetText(Locale.Lookup("LOC_TRADE_OVERVIEW_TITLE"));

	-- Game Engine Events	
	SRListen( Events.UnitOperationStarted, OnUnitOperationStarted );		-- ScreenReaderAccess
	SRListen( Events.GovernmentPolicyChanged, OnPolicyChanged );		-- ScreenReaderAccess
	SRListen( Events.GovernmentPolicyObsoleted, OnPolicyChanged );		-- ScreenReaderAccess
	SRListen( Events.LocalPlayerTurnEnd, OnLocalPlayerTurnEnd );		-- ScreenReaderAccess
	SRListen( Events.InterfaceModeChanged, OnInterfaceModeChanged );		-- ScreenReaderAccess


	-- Hot-Reload Events
	ContextPtr:SetInitHandler(OnInit);
	ContextPtr:SetShutdown(OnShutdown);
	SRListen( LuaEvents.GameDebug_Return, OnGameDebugReturn );		-- ScreenReaderAccess
end
Initialize();
