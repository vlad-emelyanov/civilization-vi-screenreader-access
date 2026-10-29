-- ===========================================================================
---- ESPIONAGE OVERVIEW ----
-- ===========================================================================
include( "InstanceManager" );
include( "AnimSidePanelSupport" );
include( "SupportFunctions" );
include( "EspionageSupport" );
include( "TabSupport" );
include( "Colors" );
include( "ScreenReader" );		-- ScreenReaderAccess
include( "KeyNavList" );		-- ScreenReaderAccess
include( "SRListen" );		-- ScreenReaderAccess
include( "EspionageText" );	-- ScreenReaderAccess

-- ===========================================================================
-- CONSTANTS
-- ===========================================================================

local RELOAD_CACHE_ID:string = "EspionageOverview"; -- Must be unique (usually the same as the file name)
local MAX_BEFORE_TRUNC_MISSION_NAME		:number = 170;
local MAX_BEFORE_TRUNC_ASK_FOR_TRADE	:number = 135;

local TRAVEL_DEST_TRUNCATE_WIDTH		:number = 170;

local EspionageTabs:table = {
	OPERATIVES		= 0;
	CITY_ACTIVITY	= 1;
	MISSION_HISTORY	= 2;
};

-- The maximum number of districts we can show before we have to make them scroll
local NUM_DISTRICTS_WITHOUT_SCROLL		:number = 7;

-- ===========================================================================
--	MEMBERS
-- ===========================================================================

local m_AnimSupport:table; -- AnimSidePanelSupport

local m_OperativeIM:table		= InstanceManager:new("OperativeInstance", "Top", Controls.OperativeStack);
local m_CityIM:table			= InstanceManager:new("CityInstance", "CityGrid", Controls.CityActivityStack);
local m_CityDistrictIM:table	= InstanceManager:new("CityDistrictInstance", "DistrictIcon");
local m_EnemyOperativeIM:table	= InstanceManager:new("EnemyOperativeInstance", "GridButton", Controls.CapturedEnemyOperativeStack);
local m_MissionHistoryIM:table	= InstanceManager:new("MissionHistoryInstance", "Top", Controls.MissionHistoryStack);

-- A table of tabs indexed by EspionageTabs enum
local m_tabs:table = nil;
local m_selectedTab:number = -1;
local m_srQuiet:boolean = false;		-- ScreenReaderAccess: Close() without "Espionage closed"

-- ===========================================================================
function Refresh()
	-- Refresh Tabs
	PopulateTabs();

	if m_selectedTab == EspionageTabs.OPERATIVES then
		Controls.OperativeTabContainer:SetHide(false);
		Controls.CityActivityTabContainer:SetHide(true);
		Controls.MissionHistoryTabContainer:SetHide(true);

		RefreshOperatives();
	elseif m_selectedTab == EspionageTabs.CITY_ACTIVITY then
		Controls.OperativeTabContainer:SetHide(true);
		Controls.CityActivityTabContainer:SetHide(false);
		Controls.MissionHistoryTabContainer:SetHide(true);

		RefreshCityActivity();
	elseif m_selectedTab == EspionageTabs.MISSION_HISTORY then
		Controls.OperativeTabContainer:SetHide(true);
		Controls.CityActivityTabContainer:SetHide(true);
		Controls.MissionHistoryTabContainer:SetHide(false);

		RefreshMissionHistory();
	end
end

function RefreshOperatives()
	m_OperativeIM:ResetInstances();

	local localPlayerID = Game.GetLocalPlayer();
	if (localPlayerID == -1) then
		return;
	end

	local idleSpies:table = {};
	local activeSpies:table = {};
	local travellingSpies:table = {};

	-- Track the number of spies for display in the header
	local numberOfSpies:number = 0;

	-- Sort spies
	local localPlayerUnits:table = Players[localPlayerID]:GetUnits();
	for i, unit in localPlayerUnits:Members() do
		local unitInfo:table = GameInfo.Units[unit:GetUnitType()];
		if unitInfo.Spy then
			local operationType:number = unit:GetSpyOperation();
			if operationType == -1 then
				table.insert(idleSpies, unit);
			else
				table.insert(activeSpies, unit);
			end

			numberOfSpies = numberOfSpies + 1;
		end
	end

	-- Display idle spies
	for i, spy in ipairs(idleSpies) do
		AddOperative(spy);
	end

	-- Display active spies
	for i, spy in ipairs(activeSpies) do
		AddOperative(spy);
	end

	-- Display captured spies
	-- Loop through all players to see if they have any of our captured spies
	local players:table = Game.GetPlayers();
	for i, player in ipairs(players) do
		local playerDiplomacy:table = player:GetDiplomacy();
		local numCapturedSpies:number = playerDiplomacy:GetNumSpiesCaptured();
		for i=0,numCapturedSpies-1,1 do
			local spyInfo:table = playerDiplomacy:GetNthCapturedSpy(player:GetID(), i);
			if spyInfo and spyInfo.OwningPlayer == Game.GetLocalPlayer() then
				AddCapturedOperative(spyInfo, player:GetID());
				numberOfSpies = numberOfSpies + 1;
			end
		end
	end

	-- Display travelling spies
	local playerDiplomacy:table = Players[Game.GetLocalPlayer()]:GetDiplomacy();
	if playerDiplomacy then
		local numSpiesOffMap:number = playerDiplomacy:GetNumSpiesOffMap();
		for i=0,numSpiesOffMap-1,1 do
			local spyOffMapInfo:table = playerDiplomacy:GetNthOffMapSpy(Game.GetLocalPlayer(), i);
			if spyOffMapInfo and spyOffMapInfo.ReturnTurn ~= -1 then
				AddOffMapOperative(spyOffMapInfo);
				numberOfSpies = numberOfSpies + 1;
			end
		end
	end

	-- Display a messsage if we have no spies
	Controls.NoOperativesLabel:SetHide(numberOfSpies ~= 0);

	-- Update spy count and capcity
	local playerDiplomacy:table = Players[Game.GetLocalPlayer()]:GetDiplomacy();
	Controls.OperativeHeader:SetText(Locale.Lookup("LOC_ESPIONAGEOVERVIEW_OPERATIVES_SUBHEADER", numberOfSpies, playerDiplomacy:GetSpyCapacity()));

	Controls.OperativeStack:CalculateSize();
	Controls.OperativeScrollPanel:CalculateSize();
end

-- ===========================================================================
function RefreshCityActivity()
	m_CityIM:ResetInstances();

	local localPlayer:table = Players[Game.GetLocalPlayer()];
	if not localPlayer then
		return;
	end

	-- Reset all the district icon instances shared between city instances
	m_CityDistrictIM:ResetInstances();

	-- Add player owned cities
	AddPlayerCities(localPlayer);

	-- Add cities for other players
	local players:table = Game.GetPlayers();
	for i, player in ipairs(players) do
		-- Ignore the local player since those cities were already added
		if player:GetID() ~= localPlayer:GetID() then
			-- Only show full civs
			if player:IsMajor() then
				AddPlayerCities(player);
			end
		end
	end

	-- Show a message if we have no cities to display
	Controls.NoCitiesLabel:SetHide(m_CityIM.m_iAllocatedInstances ~= 0);

	Controls.CityActivityScrollPanel:CalculateSize();
end

-- ===========================================================================
function RefreshMissionHistory()
	m_EnemyOperativeIM:ResetInstances();

	local localPlayerID = Game.GetLocalPlayer();
	if (localPlayerID == -1) then
		return;
	end

	-- Update captured enemy operative info
	local haveCapturedEnemyOperative:boolean = false;
	local localPlayer:table = Players[localPlayerID];
	local playerDiplomacy:table = localPlayer:GetDiplomacy();
	local numCapturedSpies:number = playerDiplomacy:GetNumSpiesCaptured();
	for i=0,numCapturedSpies-1,1 do
		local spyInfo:table = playerDiplomacy:GetNthCapturedSpy(localPlayer:GetID(), i);
		if spyInfo then
			haveCapturedEnemyOperative = true;
			AddCapturedEnemyOperative(spyInfo);
		end
	end

	-- Hide captured enemy operative info if we have no captured enemy operatives
	if haveCapturedEnemyOperative then
		Controls.CapturedEnemyOperativeContainer:SetHide(false);
	else
		Controls.CapturedEnemyOperativeContainer:SetHide(true);
	end

	-- Update mission history
	m_MissionHistoryIM:ResetInstances();

	if playerDiplomacy then
		-- Add information for last 10 missions
		local recentMissions:table = playerDiplomacy:GetRecentMissions(Game.GetLocalPlayer(), 10, 0);
		if recentMissions then
			-- Hide no missions label
			Controls.NoRecentMissonsLabel:SetHide(true);

			for i,mission in pairs(recentMissions) do
				AddMissionHistoryInstance(mission);
			end
		else
			-- Show no missions label
			Controls.NoRecentMissonsLabel:SetHide(false);
		end
	end

	-- Show a message if we have no history or enemy operatives to display
	Controls.NoHistoryLabel:SetHide(m_EnemyOperativeIM.m_iAllocatedInstances ~= 0 or m_MissionHistoryIM.m_iAllocatedInstances ~= 0);

	ResizeMissionHistoryScrollPanel();

	Controls.MissionHistoryScrollPanel:CalculateSize();
end

-- ===========================================================================
function ResizeMissionHistoryScrollPanel()
	-- Track size of elements in mission history panel to determine size of the mission history scroll panel
	local desiredScrollPanelSizeY:number = Controls.MissionHistoryTabContainer:GetSizeY();

	if not Controls.CapturedEnemyOperativeContainer:IsHidden() then
		desiredScrollPanelSizeY = desiredScrollPanelSizeY - Controls.CapturedEnemyOperativeContainer:GetSizeY();
	end

	-- Adjust the mission history scroll panel to fill bottom of panel
	desiredScrollPanelSizeY = desiredScrollPanelSizeY - Controls.MissionHistoryScrollPanel:GetOffsetY();

	Controls.MissionHistoryScrollPanel:SetSizeY(desiredScrollPanelSizeY);
end

-- ===========================================================================
function OnCapturedEnemyOperativeContainerSizeChanged()
	ResizeMissionHistoryScrollPanel();
end

-- ===========================================================================
function AddMissionHistoryInstance(mission:table)
	-- Don't show missions where the spy must escape but the player has yet to choose an escape route
	if mission.InitialResult == EspionageResultTypes.SUCCESS_MUST_ESCAPE or mission.InitialResult == EspionageResultTypes.FAIL_MUST_ESCAPE then
		if mission.EscapeResult == EspionageResultTypes.NO_RESULT then
			return;
		end
	end

	local missionHistoryInstance:table = m_MissionHistoryIM:GetInstance();

	-- Update operative name and rank
	missionHistoryInstance.OperativeName:SetText(Locale.ToUpper(mission.Name));
	missionHistoryInstance.OperativeRank:SetText(Locale.Lookup(GetSpyRankNameByLevel(mission.LevelAfter)));

	-- Update name and turns since
	local operationInfo:table = GameInfo.UnitOperations[mission.Operation];
	missionHistoryInstance.MissionName:SetText(Locale.Lookup(operationInfo.Description));
	local turnsSinceMission:number = Game.GetCurrentGameTurn() - mission.CompletionTurn;
	missionHistoryInstance.TurnsSinceMission:SetText(Locale.Lookup("LOC_ESPIONAGEOVERVIEW_TURNS_AGO", turnsSinceMission));

	-- Update outcome and font icon
	local outcomeDetails:table = GetMissionOutcomeDetails(mission);
	if outcomeDetails then
		if outcomeDetails.Success then
			missionHistoryInstance.MissionOutcomeText:SetText(Locale.ToUpper("LOC_ESPIONAGEOVERVIEW_MISSIONOUTCOME") .. " " .. Locale.ToUpper("LOC_ESPIONAGEOVERVIEW_SUCCESS"));
		else
			missionHistoryInstance.MissionOutcomeText:SetText(Locale.ToUpper("LOC_ESPIONAGEOVERVIEW_MISSIONOUTCOME") .. " " .. Locale.ToUpper("LOC_ESPIONAGEOVERVIEW_FAILURE"));
		end

		SetMissionHistorySuccess(missionHistoryInstance, outcomeDetails.Success);
		missionHistoryInstance.OperationDetails:SetText(outcomeDetails.Description);

		if outcomeDetails.SpyStatus ~= "" then
			missionHistoryInstance.MissionOutcomeSpyStatus:SetText(outcomeDetails.SpyStatus);
			missionHistoryInstance.MissionOutcomeSpyStatus:SetHide(false);
		else
			missionHistoryInstance.MissionOutcomeSpyStatus:SetHide(true);
		end
	end

	-- Update mission and district icons
	local textureOffsetX, textureOffsetY, textureSheet = IconManager:FindIconAtlas(operationInfo.Icon,40);
	if textureSheet then
		missionHistoryInstance.OperationIcon:SetTexture(textureOffsetX, textureOffsetY, textureSheet);
		missionHistoryInstance.OperationIcon:SetHide(false);
	else
		UI.DataError("Unable to find icon for spy operation: " .. operationInfo.Icon);
		missionHistoryInstance.OperationIcon:SetHide(true);
	end

	local iconString:string = "ICON_DISTRICT_CITY_CENTER";
	if operationInfo.TargetDistrict then
		iconString = "ICON_" .. operationInfo.TargetDistrict;
	elseif operationInfo.Hash == UnitOperationTypes.SPY_COUNTERSPY then
		local pTargetPlot:table = Map.GetPlotByIndex(mission.PlotIndex);
		local kDistrictInfo:table = GameInfo.Districts[pTargetPlot:GetDistrictType()];
		iconString = "ICON_" .. kDistrictInfo.DistrictType;
	end
	textureOffsetX, textureOffsetY, textureSheet = IconManager:FindIconAtlas(iconString,32);
	if textureSheet then
		missionHistoryInstance.OperationDistrictIcon:SetTexture(textureOffsetX, textureOffsetY, textureSheet);
	else
		UI.DataError("Unable to find icon for district: " .. iconString);
	end

	-- Scale the operation and district icons to match the operation description
	missionHistoryInstance.OperationIconGrid:SetSizeY(missionHistoryInstance.OperationDetailsContainer:GetSizeY());
	missionHistoryInstance.OperationDistrictIconGrid:SetSizeY(missionHistoryInstance.OperationDetailsContainer:GetSizeY());
end

-- ===========================================================================
function SetMissionHistorySuccess(missionHistoryInstance:table, wasSuccess:boolean)
	if wasSuccess then
		missionHistoryInstance.MissionGradient:SetColorByName("Green");
		missionHistoryInstance.MissionOutcomeText:SetColor(UI.GetColorValueFromHexLiteral(0xFF329600));
		missionHistoryInstance.MissionOutcomeSpyStatus:SetColor(UI.GetColorValueFromHexLiteral(0xFF329600));
		missionHistoryInstance.MissionOutcomeFontIcon:SetText("[ICON_CheckSuccess]");
	else
		missionHistoryInstance.MissionGradient:SetColorByName("Red");
		missionHistoryInstance.MissionOutcomeText:SetColor(UI.GetColorValueFromHexLiteral(0xFF0000C6));
		missionHistoryInstance.MissionOutcomeSpyStatus:SetColor(UI.GetColorValueFromHexLiteral(0xFF0000C6));
		missionHistoryInstance.MissionOutcomeFontIcon:SetText("[ICON_CheckFail]");
	end
end

-- ===========================================================================
function AddPlayerCities(player:table)
	local playerCities:table = player:GetCities();
	for j, city in playerCities:Members() do
		-- Check if the city is revealed
		local localPlayerVis:table = PlayersVisibility[Game.GetLocalPlayer()];
		if localPlayerVis:IsRevealed(city:GetX(), city:GetY()) then
			AddCity(city);
		end
	end
end

-- ===========================================================================
function AddCity(city:table)
	local cityInstance:table = m_CityIM:GetInstance();

	-- Update city banner
	local backColor:number, frontColor:number  = UI.GetPlayerColors( city:GetOwner() );

	cityInstance.BannerBase:SetColor( backColor );
	cityInstance.CityName:SetColor( frontColor );
	cityInstance.BannerBase:LocalizeAndSetToolTip("LOC_ESPIONAGEOVERVIEW_VIEW_CITY");
	cityInstance.BannerBase:RegisterCallback( Mouse.eLClick, function() LookAtCity(city:GetOwner(), city:GetID()); end );
    cityInstance.BannerBase:RegisterCallback(Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);

	-- Update capital indicator but never show it for city-states
	local cityName:string = "";
	if city:IsCapital() and Players[city:GetOwner()]:IsMajor() then
		cityName = "[ICON_Capital]" .. " " .. Locale.ToUpper(city:GetName());
	else
		cityName = Locale.ToUpper(city:GetName());
	end
	TruncateString(cityInstance.CityName, 220, cityName);

	-- Update district icons	
	local pCityDistricts:table = city:GetDistricts();
	if pCityDistricts ~= nil then
		-- Show or hide scroll arrows based on number of districts
		local bNeedsToScroll:boolean = pCityDistricts:GetNumDistricts() > NUM_DISTRICTS_WITHOUT_SCROLL;
		if bNeedsToScroll then
			cityInstance.CurrentScrollPos = 1;
			cityInstance.DistrictsScrollLeftButton:SetHide(false);
			cityInstance.DistrictsScrollLeftButton:SetDisabled(true);
			cityInstance.DistrictsScrollRightButton:SetHide(false);

			cityInstance.DistrictsScrollLeftButton:RegisterCallback( Mouse.eLClick, function() OnDistrictsLeftButton(cityInstance); end );
			cityInstance.DistrictsScrollRightButton:RegisterCallback( Mouse.eLClick, function() OnDistrictsRightButton(cityInstance); end );
		else
			cityInstance.DistrictsScrollLeftButton:SetHide(true);
			cityInstance.DistrictsScrollRightButton:SetHide(true);
		end

		-- Populate districts
		local iNumDistrictsThisCity:number = 0;
		for _, pDistrict in pCityDistricts:Members() do
			local kDistrictIconInst:table = AddDistrictIcon(cityInstance.CityDistrictStack, city, pDistrict);
			if kDistrictIconInst ~= nil then
				iNumDistrictsThisCity = iNumDistrictsThisCity + 1;

				if bNeedsToScroll and iNumDistrictsThisCity > (NUM_DISTRICTS_WITHOUT_SCROLL - 1) then
					kDistrictIconInst.DistrictIcon:SetHide(true);
				end
			end
		end
	end
		
	-- Update gain sources boost icon
	local player = Players[Game.GetLocalPlayer()];
	local playerDiplomacy:table = player:GetDiplomacy();
	if playerDiplomacy then
		local boostedTurnsRemaining:number = playerDiplomacy:GetSourceTurnsRemaining(city);
		if boostedTurnsRemaining > 0 then
			cityInstance.GainSourcesBoostIcon:SetHide(false);
		else
			cityInstance.GainSourcesBoostIcon:SetHide(true);
		end
	end

	if shouldShowCounterspyIcon then
		cityInstance.CounterspyIconBack:SetHide(false);
		cityInstance.CounterspyIconBack:SetColor( backColor );
		cityInstance.CounterspyIconFront:SetColor( frontColor );
	else
		cityInstance.CounterspyIconBack:SetHide(true);
	end
end

-- ===========================================================================
function OnDistrictsLeftButton( kCityInstance:table )
	kCityInstance.CurrentScrollPos = kCityInstance.CurrentScrollPos - 1;
	local kChildren:table = kCityInstance.CityDistrictStack:GetChildren();

	-- Always enable right button if we scroll left
	kCityInstance.DistrictsScrollRightButton:SetDisabled(false);
	
	-- Disable left button if we reach the beginning of the list
	if kCityInstance.CurrentScrollPos == 1 then
		kCityInstance.DistrictsScrollLeftButton:SetDisabled(true);
	end
	
	-- Show/hide children based on the current scroll pos
	-- (NUM_DISTRICTS_WITHOUT_SCROLL - 2) makes room for the 2 scroll buttons
	for i, kChild in ipairs(kChildren) do
		if i < kCityInstance.CurrentScrollPos or i > (kCityInstance.CurrentScrollPos + NUM_DISTRICTS_WITHOUT_SCROLL - 2) then
			kChild:SetHide(true);
		else
			kChild:SetHide(false);
		end
	end
end

-- ===========================================================================
function OnDistrictsRightButton( kCityInstance:table )
	kCityInstance.CurrentScrollPos = kCityInstance.CurrentScrollPos + 1;
	local kChildren:table = kCityInstance.CityDistrictStack:GetChildren();

	-- Always enable left button if we scroll right
	kCityInstance.DistrictsScrollLeftButton:SetDisabled(false);
	
	-- Disable right button if we're at the end of the list
	if (kCityInstance.CurrentScrollPos + NUM_DISTRICTS_WITHOUT_SCROLL - 2) >= #kChildren then
		kCityInstance.DistrictsScrollRightButton:SetDisabled(true);
	end
	
	-- Show/hide children based on the current scroll pos
	-- (NUM_DISTRICTS_WITHOUT_SCROLL - 2) makes room for the 2 scroll buttons
	for i, kChild in ipairs(kChildren) do
		if i < kCityInstance.CurrentScrollPos or i > (kCityInstance.CurrentScrollPos + NUM_DISTRICTS_WITHOUT_SCROLL - 2) then
			kChild:SetHide(true);
		else
			kChild:SetHide(false);
		end
	end
end

-- ===========================================================================
function AddDistrictIcon(kStackControl:table, pCity:table, pDistrict:table)
	if not pDistrict:IsComplete() then
		return nil;
	end

	local kDistrictDef:table = GameInfo.Districts[pDistrict:GetType()];
	if kDistrictDef == nil or kDistrictDef.DistrictType == "DISTRICT_WONDER" then
		return nil;
	end

	local kInstance:table = m_CityDistrictIM:GetInstance( kStackControl );

	kInstance.DistrictIcon:SetIcon("ICON_" .. kDistrictDef.DistrictType);
	local sToolTip:string = Locale.Lookup(kDistrictDef.Name);

	-- Check if one of our spies is active in this district
	local bShouldShowActiveSpy:boolean = false;
	local pPlayerUnits:table = Players[Game.GetLocalPlayer()]:GetUnits();
	for i, pUnit in pPlayerUnits:Members() do
		local kUnitDef:table = GameInfo.Units[pUnit:GetUnitType()];
		if not bShouldShowActiveSpy and kUnitDef.Spy then
			local eOperationType:number = pUnit:GetSpyOperation();
			local kOperationDef:table = GameInfo.UnitOperations[eOperationType];
			if kOperationDef then
				local pSpyPlot:table = Map.GetPlot(pUnit:GetX(), pUnit:GetY());
				local pTargetCity:table = Cities.GetPlotPurchaseCity(pSpyPlot);
				if pTargetCity:GetOwner() == pCity:GetOwner() and pTargetCity:GetID() == pCity:GetID() then
					local iSpyDistrictID:number = pSpyPlot:GetDistrictID();
					if pDistrict:GetID() == iSpyDistrictID then
						bShouldShowActiveSpy = true;
						sToolTip = sToolTip .. "[NEWLINE]" .. Locale.Lookup(pUnit:GetName()) .. "[NEWLINE]" .. Locale.Lookup(kOperationDef.Description);
					end
				end
			end
		end
	end

	kInstance.DistrictIcon:SetToolTipString( sToolTip );

	if bShouldShowActiveSpy then
		local backColor:number, frontColor:number  = UI.GetPlayerColors( Game.GetLocalPlayer() );
		kInstance.SpyIconBack:SetColor( backColor );
		kInstance.SpyIconFront:SetColor( frontColor );
		kInstance.SpyIconBack:SetHide(false);
	else
		kInstance.SpyIconBack:SetHide(true);
	end

	return kInstance;
end

-- ===========================================================================
--	Called once during Init
-- ===========================================================================
function PopulateTabs()
	local localPlayerID:number = Game.GetLocalPlayer();
	if localPlayerID == -1 then
		return;
	end

	-- Grab player and diplomacy for local player
	local pPlayer:table = Players[localPlayerID];
	local pPlayerDiplomacy:table = nil;
	if pPlayer then
		pPlayerDiplomacy = pPlayer:GetDiplomacy();
	end

	if m_tabs == nil then
		m_tabs = CreateTabs( Controls.TabContainer, 42, 34, UI.GetColorValueFromHexLiteral(0xFF331D05) );
	end

	-- Operatives Tab
	if not m_tabs.OperativesTabAdded then
		m_tabs.AddTab( Controls.OperativesTabButton,		OnSelectOperativesTab );
		Controls.OperativesTabButton:RegisterCallback(Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
		m_tabs.OperativesTabAdded = true;
	end

	-- City Activity Tab
	if not m_tabs.CityActivityTabAdded then
		m_tabs.AddTab( Controls.CityActivityTabButton,		OnSelectCityActivityTab );
		Controls.CityActivityTabButton:RegisterCallback(Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
		m_tabs.CityActivityTabAdded = true;
	end
		
	-- Mission History Tab
	-- Only show mission history if we have any mission history or captured enemy operatives
	local shouldShowMissionHistory:boolean = false;
	if pPlayerDiplomacy then
		local firstMission = pPlayerDiplomacy:GetMission(localPlayerID, 0);
		if firstMission ~= 0 then
			-- We have a mission so show history
			shouldShowMissionHistory = true;
		end

		local numCapturedSpies:number = pPlayerDiplomacy:GetNumSpiesCaptured();
		if numCapturedSpies > 0 then
			-- Show mission history if we have captured enemy spies
			shouldShowMissionHistory = true;
		end
	end

	if shouldShowMissionHistory then
		if not m_tabs.MissionHistoryTabAdded then
			Controls.MissionHistoryTabButton:SetHide(false);
			m_tabs.AddTab( Controls.MissionHistoryTabButton,	OnSelectMissionHistoryTab );
			Controls.MissionHistoryTabButton:RegisterCallback(Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
			m_tabs.MissionHistoryTabAdded = true;
		end
	else
		Controls.MissionHistoryTabButton:SetHide(true);
	end

	m_tabs.EvenlySpreadTabs();
	m_tabs.CenterAlignTabs(-25);	-- Use negative to create padding as value represents amount to overlap
end

-- ===========================================================================
function SelectTabByIndex( tabIndex:number )
	if tabIndex == EspionageTabs.CITY_ACTIVITY then
		m_tabs.SelectTab( Controls.CityActivityTabButton );
	elseif tabIndex == EspionageTabs.MISSION_HISTORY then
		m_tabs.SelectTab( Controls.MissionHistoryTabButton );
	else
		m_tabs.SelectTab( Controls.OperativesTabButton );
	end
end

-- ===========================================================================
function OnSelectOperativesTab()
	m_selectedTab = EspionageTabs.OPERATIVES;
	Refresh();
end

-- ===========================================================================
function OnSelectCityActivityTab()
	m_selectedTab = EspionageTabs.CITY_ACTIVITY;
	Refresh();
end

-- ===========================================================================
function OnSelectMissionHistoryTab()
	m_selectedTab = EspionageTabs.MISSION_HISTORY;
	Refresh();
end

-- ===========================================================================
function AddOperative(spy:table)
	local operativeInstance:table = m_OperativeIM:GetInstance();

	local spyInfo:table = GameInfo.Units[spy:GetUnitType()];

	-- Operative Name
	operativeInstance.OperativeName:SetText(Locale.ToUpper(spy:GetName()));

	-- Operative Rank
	local spyExperience:table = spy:GetExperience();
	operativeInstance.OperativeRank:SetText(Locale.Lookup(GetSpyRankNameByLevel(spyExperience:GetLevel())));

	-- City Banner
	local spyPlot = Map.GetPlot(spy:GetX(), spy:GetY());
	local ownerCity = Cities.GetPlotPurchaseCity(spyPlot);
	if ownerCity then
		local backColor:number, frontColor:number  = UI.GetPlayerColors( ownerCity:GetOwner() );
		operativeInstance.CityBanner:SetColor( backColor );
		operativeInstance.LocationPip:SetColor( frontColor );
		operativeInstance.CityName:SetColor( frontColor );
		operativeInstance.CityName:SetText(Locale.ToUpper(ownerCity:GetName()));
		operativeInstance.CityBanner:LocalizeAndSetToolTip("LOC_ESPIONAGEOVERVIEW_VIEW_CITY");
		operativeInstance.CityBanner:RegisterCallback( Mouse.eLClick, function() LookAtCity(ownerCity:GetOwner(), ownerCity:GetID()); end );
        operativeInstance.CityBanner:RegisterCallback(Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
		operativeInstance.CityBanner:SetHide(false);
	else
		operativeInstance.CityBanner:SetHide(true);
	end
	
	local operationType:number = spy:GetSpyOperation();
	if operationType == -1 then
		-- Awaiting Assignment
		operativeInstance.Top:SetTextureOffsetVal(0, 73);

		operativeInstance.AwaitingAssignmentStack:SetHide(false);
		operativeInstance.ActiveMissionContainer:SetHide(true);
		operativeInstance.TravellingContainer:SetHide(true);
		operativeInstance.CapturedContainer:SetHide(true);
	else
		-- On Active Assignment
		operativeInstance.Top:SetTextureOffsetVal(0, 0);

		-- Operation Name
		local operationInfo:table = GameInfo.UnitOperations[operationType];
		TruncateStringWithTooltip(operativeInstance.OperationName, MAX_BEFORE_TRUNC_MISSION_NAME, Locale.Lookup(operationInfo.Description)); 

		-- Turns Remaining
		local turnsRemaining:number = spy:GetSpyOperationEndTurn() - Game.GetCurrentGameTurn();
		if turnsRemaining <= 0 then
			turnsRemaining = 0;
		end
		operativeInstance.OperationTurnsRemaining:SetText(Locale.Lookup("LOC_ESPIONAGEOVERVIEW_MORE_TURNS", turnsRemaining));

		-- Percent Complete
		local totalTurns:number = UnitManager.GetTimeToComplete(operationType, spy);
		local percentOperationComplete:number = (totalTurns - turnsRemaining) / totalTurns;
		operativeInstance.OperationPercentComplete:SetPercent(percentOperationComplete);

		-- Operation Icon
		local textureOffsetX, textureOffsetY, textureSheet = IconManager:FindIconAtlas(operationInfo.Icon,40);
		if textureSheet then
			operativeInstance.OperationIcon:SetTexture(textureOffsetX, textureOffsetY, textureSheet);
			operativeInstance.OperationIcon:SetHide(false);
		else
			UI.DataError("Unable to find icon for spy operation: " .. operationInfo.Icon);
			operativeInstance.OperationIcon:SetHide(true);
		end

		-- Operation District Icon
		local spyPlot:table = Map.GetPlot(spy:GetX(), spy:GetY());
		local districtType = spyPlot:GetDistrictType();
		local districtInfo = GameInfo.Districts[districtType];
		if districtInfo then
			local iconString:string = "ICON_" .. districtInfo.DistrictType;
			textureOffsetX, textureOffsetY, textureSheet = IconManager:FindIconAtlas(iconString,32);
			operativeInstance.OperationDistrictIcon:SetTexture(textureOffsetX, textureOffsetY, textureSheet);
		end

		-- Operation Details
		if ownerCity then
			if operationInfo.Hash == UnitOperationTypes.SPY_COUNTERSPY then
				operativeInstance.OperationDetails:SetText(Locale.Lookup("LOC_ESPIONAGECHOOSER_COUNTERSPY", Locale.Lookup(districtInfo.Name)));
			else
				operativeInstance.OperationDetails:SetText(GetFormattedOperationDetailText(operationInfo, spy, ownerCity));
			end
		end

		operativeInstance.AwaitingAssignmentStack:SetHide(true);
		operativeInstance.ActiveMissionContainer:SetHide(false);
		operativeInstance.TravellingContainer:SetHide(true);
		operativeInstance.CapturedContainer:SetHide(true);
	end
end

-- ===========================================================================
function LookAtCity(playerID:number, cityID:number)
	local player = Players[playerID];
	if player then
		city = player:GetCities():FindID(cityID);
		UI.LookAtPlotScreenPosition( city:GetX(), city:GetY(), 0.33, 0.5 );
	end
end

------------------------------------------------------------------------------------------------
function AddOffMapOperative(spy:table)
	local operativeInstance:table = m_OperativeIM:GetInstance();

	-- Adjust texture offset
	operativeInstance.Top:SetTextureOffsetVal(0, 146);

	-- Operative Name
	operativeInstance.OperativeName:SetText(Locale.ToUpper(spy.Name));

	-- Operative Rank
	operativeInstance.OperativeRank:SetText(Locale.Lookup(GetSpyRankNameByLevel(spy.Level)));

	-- Travel Time
	local travelTurnsRemaining:number = spy.ReturnTurn - Game.GetCurrentGameTurn();
	operativeInstance.TravelTurnsRemaining:SetText(Locale.Lookup("LOC_ESPIONAGEOVERVIEW_MORE_TURNS", travelTurnsRemaining));

	-- Travel Percentage Complete
	operativeInstance.TravelPercentComplete:SetPercent(0);

	-- Get city name
	local spyPlot:table = Map.GetPlot(spy.XLocation, spy.YLocation);
	local targetCity:table = Cities.GetPlotPurchaseCity(spyPlot);
	if targetCity then
		TruncateStringWithTooltip(operativeInstance.TravelDestinationName, TRAVEL_DEST_TRUNCATE_WIDTH, Locale.Lookup("LOC_ESPIONAGEOVERVIEW_TRANSIT_TO", targetCity:GetName()));
	end

	operativeInstance.CityBanner:SetHide(true);
	operativeInstance.AwaitingAssignmentStack:SetHide(true);
	operativeInstance.ActiveMissionContainer:SetHide(true);
	operativeInstance.TravellingContainer:SetHide(false);
	operativeInstance.CapturedContainer:SetHide(true);
end

------------------------------------------------------------------------------------------------
function AddCapturedOperative(spy:table, playerCapturedBy:number)
	local operativeInstance:table = m_OperativeIM:GetInstance();

	-- Adjust texture offset
	operativeInstance.Top:SetTextureOffsetVal(0, 146);

	-- Operative Name
	operativeInstance.OperativeName:SetText(Locale.ToUpper(spy.Name));

	-- Operative Rank
	operativeInstance.OperativeRank:SetText(Locale.Lookup(GetSpyRankNameByLevel(spy.Level)));

	-- Update information about the player who captured the spy
	local capturingPlayerConfig:table = PlayerConfigurations[playerCapturedBy];
	if capturingPlayerConfig then
		local backColor:number, frontColor:number  = UI.GetPlayerColors( playerCapturedBy );
		local textureOffsetX, textureOffsetY, textureSheet = IconManager:FindIconAtlas("ICON_" .. capturingPlayerConfig:GetCivilizationTypeName(),22);
		operativeInstance.CapturingCivIconBack:SetColor(backColor);
		operativeInstance.CapturingCivIconFront:SetColor(frontColor);
		operativeInstance.CapturingCivIconFront:SetTexture(textureOffsetX, textureOffsetY, textureSheet);
		operativeInstance.CapturingCivName:SetText(Locale.Lookup(capturingPlayerConfig:GetPlayerName()));
		TruncateStringWithTooltip(operativeInstance.AskForTradeButton, MAX_BEFORE_TRUNC_ASK_FOR_TRADE, Locale.Lookup("LOC_ESPIONAGEOVERVIEW_ASK_FOR_TRADE"));
		
		-- Show the ask trade button, if there is no pending deal.
		local localPlayerID:number = Game.GetLocalPlayer();
		local atWarWith:boolean = Players[localPlayerID]:GetDiplomacy():IsAtWarWith(playerCapturedBy);
		if atWarWith then
			operativeInstance.AskForTradeButton:SetDisabled(true);
			operativeInstance.AskForTradeButton:SetToolTipString(Locale.Lookup("LOC_DIPLOPANEL_AT_WAR"));
		elseif DealManager.HasPendingDeal(localPlayerID, playerCapturedBy) then
			operativeInstance.AskForTradeButton:SetDisabled(true);
			operativeInstance.AskForTradeButton:SetToolTipString(Locale.Lookup("LOC_DIPLOMACY_ANOTHER_DEAL_WITH_PLAYER_PENDING"));
		else
			operativeInstance.AskForTradeButton:SetDisabled(false);
			operativeInstance.AskForTradeButton:RegisterCallback( Mouse.eLClick, function() OnAskForOperativeTradeClicked(playerCapturedBy, spy.NameIndex); end );
			operativeInstance.AskForTradeButton:SetToolTipString("");
		end
	else
		UI.DataError("Could not find player configuration for player ID: " .. tostring(playerCapturedBy));
	end

	operativeInstance.CityBanner:SetHide(true);
	operativeInstance.AwaitingAssignmentStack:SetHide(true);
	operativeInstance.ActiveMissionContainer:SetHide(true);
	operativeInstance.TravellingContainer:SetHide(true);
	operativeInstance.CapturedContainer:SetHide(false);
end

------------------------------------------------------------------------------------------------
function OnAskForOperativeTradeClicked(capturingPlayerID:number, capturedSpyID:number)
	-- Can't do this if we already have a pending deal
	if (not DealManager.HasPendingDeal(Game.GetLocalPlayer(), capturingPlayerID)) then
		-- Clear deal
		DealManager.ClearWorkingDeal(DealDirection.OUTGOING, Game.GetLocalPlayer(), capturingPlayerID);

		local bDealValid = false;

		-- Add the spy to the deal
		local pDeal = DealManager.GetWorkingDeal(DealDirection.OUTGOING, Game.GetLocalPlayer(), capturingPlayerID);
		if (pDeal ~= nil) then
			local pDealItem = pDeal:AddItemOfType(DealItemTypes.CAPTIVE, capturingPlayerID);
			if (pDealItem ~= nil) then
				-- The value of the deal item holds the spy's index
				pDealItem:SetValueType( capturedSpyID );
				if (pDealItem:IsValid()) then
					pDealItem:SetLocked(true);
					bDealValid = true;
				end
			end
		end

		-- Request the diplomacy session.  This will open the deal screen, with the deal in its current state.
		if (bDealValid) then
			DiplomacyManager.RequestSession(Game.GetLocalPlayer(), capturingPlayerID, "MAKE_DEAL");
		else
			DealManager.ClearWorkingDeal(DealDirection.OUTGOING, Game.GetLocalPlayer(), capturingPlayerID);
		end
	end
end

------------------------------------------------------------------------------------------------
function AddCapturedEnemyOperative(spyInfo:table)
	local enemyOperativeInstance:table = m_EnemyOperativeIM:GetInstance();

	-- Update spy name
	local spyName:string = Locale.ToUpper(spyInfo.Name);
	enemyOperativeInstance.SpyName:SetText(spyName);

	-- Update owning civ spy icon
	local backColor:number, frontColor:number  = UI.GetPlayerColors( spyInfo.OwningPlayer );
	enemyOperativeInstance.SpyIconBack:SetColor(backColor);
	enemyOperativeInstance.SpyIconFront:SetColor(frontColor);

	-- Update owning civ name
	local owningPlayerConfig:table = PlayerConfigurations[spyInfo.OwningPlayer];
	enemyOperativeInstance.CivName:SetText(Locale.Lookup(owningPlayerConfig:GetCivilizationDescription()));

	local pLocalPlayerDiplo:table = Players[Game.GetLocalPlayer()]:GetDiplomacy();
	if pLocalPlayerDiplo and not pLocalPlayerDiplo:IsAtWarWith(spyInfo.OwningPlayer) then
		-- If we're not at war with the spies owner allow trading for that spy
		enemyOperativeInstance.OfferTradeText:SetHide(false);
		enemyOperativeInstance.GridButton:SetDisabled(false);
		enemyOperativeInstance.GridButton:RegisterCallback( Mouse.eLClick, function() OnAskForEnemyOperativeTradeClicked(spyInfo.OwningPlayer, spyInfo.NameIndex); end );
		enemyOperativeInstance.GridButton:SetToolTipString("");
	else
		enemyOperativeInstance.OfferTradeText:SetHide(true);
		enemyOperativeInstance.GridButton:SetDisabled(true);
		enemyOperativeInstance.GridButton:ClearCallback( Mouse.eLClick );
		enemyOperativeInstance.GridButton:SetToolTipString(Locale.Lookup("LOC_ESPIONAGE_SPY_TRADE_DISABLED_AT_WAR", spyName, Locale.Lookup(owningPlayerConfig:GetCivilizationShortDescription())));
	end

	Controls.CapturedEnemyOperativeStack:CalculateSize();
end

------------------------------------------------------------------------------------------------
function OnAskForEnemyOperativeTradeClicked(owningPlayerID:number, capturedSpyID:number)
	-- Clear deal
	DealManager.ClearWorkingDeal(DealDirection.OUTGOING, Game.GetLocalPlayer(), owningPlayerID);

	-- Add the spy to the deal
	local pDeal = DealManager.GetWorkingDeal(DealDirection.OUTGOING, Game.GetLocalPlayer(), owningPlayerID);
	if (pDeal ~= nil) then
		local pDealItem = pDeal:AddItemOfType(DealItemTypes.CAPTIVE, Game.GetLocalPlayer());
		if (pDealItem ~= nil) then
			---- The value of the deal item holds the spy's index
			pDealItem:SetLocked(true);
			pDealItem:SetValueType( capturedSpyID );
		end
	end

	-- Request the diplomacy session.  This will open the deal screen, with the deal in its current state.
	DiplomacyManager.RequestSession(Game.GetLocalPlayer(), owningPlayerID, "MAKE_DEAL");
end

------------------------------------------------------------------------------------------------
function Close()
	if m_AnimSupport.IsVisible() and not m_srQuiet then SRA_Closed(); end		-- ScreenReaderAccess
	m_AnimSupport:Hide();
    if not ContextPtr:IsHidden() then
        UI.PlaySound("CityStates_Panel_Close");
    end
end

------------------------------------------------------------------------------------------------
function Open(forceTabIndex:number)
	-- dont show panel if there is no local player
	local localPlayerID = Game.GetLocalPlayer();
	if (localPlayerID == -1) then
		return
	end

	m_AnimSupport:Show();

	if forceTabIndex then
		SelectTabByIndex( forceTabIndex );
	else
		-- Default to Operatives tab
		m_tabs.SelectTab( Controls.OperativesTabButton );
	end
	SRA_ArmOpen();		-- ScreenReaderAccess
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

------------------------------------------------------------------------------------------------
function OnSpyRemoved(spyOwner, counterSpyPlayer)
	if (not ContextPtr:IsHidden()) then
		if (spyOwner == Game.GetLocalPlayer()) then
			if (m_selectedTab == EspionageTabs.OPERATIVES) then
				RefreshOperatives();
			end
		end
	end
end

------------------------------------------------------------------------------------------------
function OnSpyAdded(spyOwner, spyUnitID)
	if (not ContextPtr:IsHidden()) then
		if (spyOwner == Game.GetLocalPlayer()) then
			if (m_selectedTab == EspionageTabs.OPERATIVES) then
				RefreshOperatives();
			end
		end
	end
end

function OnDiplomacyDealEnacted()
	if (not ContextPtr:IsHidden()) then
		if (m_selectedTab == EspionageTabs.MISSION_HISTORY) then
			RefreshMissionHistory();
		end
	end
end

------------------------------------------------------------------------------------------------
function OnClose()
	Close();
end

------------------------------------------------------------------------------------------------
function OnOpen()
	UI.PlaySound("CityStates_Panel_Open");
	Open();
end

------------------------------------------------------------------------------------------------
function OnCloseAllExcept(contextToStayOpen:string)
	if contextToStayOpen ~= ContextPtr:GetID() then 
		Close();
	end
end

-- ===========================================================================
function OnUnitOperationStarted(ownerID:number, unitID:number, operationID:number)
	if m_AnimSupport.IsVisible() then
		Refresh();
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
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "isVisible", m_AnimSupport:IsVisible());
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "selectedTab", m_selectedTab);
end

-- ===========================================================================
--	LUA EVENT
--	Reload support
-- ===========================================================================
function OnGameDebugReturn(context:string, contextTable:table)
	if context == RELOAD_CACHE_ID then
		if contextTable["isVisible"] ~= nil and contextTable["isVisible"] then			
			Open();
		end
		if contextTable["selectedTab"] ~= nil then			
			SelectTabByIndex( contextTable["selectedTab"] );
		end
	end
end

-- ===========================================================================
-- ===========================================================================
--	ScreenReaderAccess: keyboard navigation and speech (F3)
--	Opens 0.4 s after Open() with "Espionage: 2 of 3 spies, 1 awaiting orders. Operatives. Spy Ana, Recruit, in Rome,
--	awaiting orders, 1 of 2". Tabs as the screen has them (Operatives, City Activity, Mission History when the game
--	shows it): Tab / Control+Tab / Left / Right switch. Items are read from the game's data at key time (own spies in
--	their city, with mission and turns left, travelling and captured spies; revealed cities with districts and your
--	spies; recent missions with outcome and the enemy spies you hold). Up/Down/Home/End, Space = details. Enter: a spy
--	selects it (the espionage chooser then opens for an idle spy), a city shows it on the map, a captured spy asks for
--	a trade through the game's own function. Escape closes. Function keys pass through; every other keyboard event is
--	swallowed while the screen is open.
-- ===========================================================================
local m_srList				:table = nil;
local m_srOpenPending		:boolean = false;
local m_srOpenDelay			:number = 0;
local SRA_OPEN_DELAY		:number = 0.4;

local function SRA_Say( text:string, nointerrupt:boolean )
	OutputMessageToScreenReader( text, nointerrupt );
end

local function SRA_Clean( text:string )
	return CleanTextForSpeech( text or "" );
end

local function SRA_TabNames()
	return {
		[ EspionageTabs.OPERATIVES ]		= Locale.Lookup( "LOC_ESPIONAGEOVERVIEW_OPERATIVES_HEADER" ),
		[ EspionageTabs.CITY_ACTIVITY ]		= Locale.Lookup( "LOC_ESPIONAGEOVERVIEW_CITY_ACTIVITY_HEADER" ),
		[ EspionageTabs.MISSION_HISTORY ]	= Locale.Lookup( "LOC_ESPIONAGEOVERVIEW_MISSION_HISTORY_HEADER" ),
	};
end

-- Tab indexes the game currently offers, in order.
local function SRA_VisibleTabs()
	local tabs:table = { EspionageTabs.OPERATIVES, EspionageTabs.CITY_ACTIVITY };
	if not Controls.MissionHistoryTabButton:IsHidden() then table.insert( tabs, EspionageTabs.MISSION_HISTORY ); end
	return tabs;
end

local function SRA_OwnerText( ownerID:number )
	if ownerID == Game.GetLocalPlayer() then return "yours"; end
	local player:table = Players[ ownerID ];
	if player ~= nil and player:GetInfluence():CanReceiveInfluence() then return "city-state"; end
	local config:table = PlayerConfigurations[ ownerID ];
	if config == nil then return nil; end
	return Locale.Lookup( config:GetCivilizationShortDescription() );
end

local function SRA_CityAt( x:number, y:number )
	return Cities.GetPlotPurchaseCity( Map.GetPlot( x, y ) );
end

local function SRA_CivName( playerID:number )
	local config:table = PlayerConfigurations[ playerID ];
	if config == nil then return nil; end
	return Locale.Lookup( config:GetCivilizationShortDescription() );
end

-- ---- Operatives ------------------------------------------------------------------------------

local function SRA_MissionText( spy:table, operationType:number, ownerCity:table )
	local operationInfo:table = GameInfo.UnitOperations[ operationType ];
	local text:string = Locale.Lookup( operationInfo.Description );
	if operationInfo.Hash == UnitOperationTypes.SPY_COUNTERSPY then
		local districtInfo:table = GameInfo.Districts[ Map.GetPlot( spy:GetX(), spy:GetY() ):GetDistrictType() ];
		if districtInfo ~= nil then text = text .. ", " .. Locale.Lookup( districtInfo.Name ); end
	end
	return text;
end

local function SRA_SpyItem( spy:table )
	local operationType:number = spy:GetSpyOperation();
	local ownerCity:table = SRA_CityAt( spy:GetX(), spy:GetY() );
	local data:table = {
		name = Locale.Lookup( spy:GetName() ),
		rank = Locale.Lookup( GetSpyRankNameByLevel( spy:GetExperience():GetLevel() ) ),
		state = ( operationType == -1 ) and "idle" or "mission",
	};
	if ownerCity ~= nil then
		data.city = Locale.Lookup( ownerCity:GetName() );
		local owner:string = SRA_OwnerText( ownerCity:GetOwner() );
		if owner ~= nil and owner ~= "yours" then data.city = data.city .. " (" .. owner .. ")"; end
	end
	local detail:string;
	if operationType ~= -1 then
		data.mission = SRA_MissionText( spy, operationType, ownerCity );
		data.turns = math.max( 0, spy:GetSpyOperationEndTurn() - Game.GetCurrentGameTurn() );
		local operationInfo:table = GameInfo.UnitOperations[ operationType ];
		local parts:table = {};
		if ownerCity ~= nil and operationInfo.Hash ~= UnitOperationTypes.SPY_COUNTERSPY then
			table.insert( parts, SRA_Clean( GetFormattedOperationDetailText( operationInfo, spy, ownerCity ) ) );
		elseif operationInfo.Hash == UnitOperationTypes.SPY_COUNTERSPY then
			local districtInfo:table = GameInfo.Districts[ Map.GetPlot( spy:GetX(), spy:GetY() ):GetDistrictType() ];
			if districtInfo ~= nil then table.insert( parts, SRA_Clean( Locale.Lookup( "LOC_ESPIONAGECHOOSER_COUNTERSPY", Locale.Lookup( districtInfo.Name ) ) ) ); end
		end
		local total:number = UnitManager.GetTimeToComplete( operationType, spy );
		if total ~= nil and total > 0 then table.insert( parts, ( total - data.turns ) .. " of " .. total .. " turns done" ); end
		table.insert( parts, SRKey( "Enter" ) .. " selects the spy" );
		detail = table.concat( parts, ". " );
	else
		detail = "Awaiting orders. " .. SRKey( "Enter" ) .. " selects the spy to choose a destination or mission";
	end
	return { key = "spy:" .. spy:GetID(), text = EspionageText_Spy( data ), detail = detail, kind = "spy", id = spy:GetID() };
end

local function SRA_OperativeItems()
	local items:table = {};
	local localID:number = Game.GetLocalPlayer();
	if localID == -1 then return items, 0, 0; end
	local player:table = Players[ localID ];
	local idle:table, active:table = {}, {};
	for _, unit in player:GetUnits():Members() do
		if GameInfo.Units[ unit:GetUnitType() ].Spy then
			if unit:GetSpyOperation() == -1 then table.insert( idle, unit ); else table.insert( active, unit ); end
		end
	end
	for _, spy in ipairs( idle ) do table.insert( items, SRA_SpyItem( spy ) ); end
	for _, spy in ipairs( active ) do table.insert( items, SRA_SpyItem( spy ) ); end
	local spies:number = #idle + #active;

	-- our spies captured by others
	for _, other in ipairs( Game.GetPlayers() ) do
		local diplomacy:table = other:GetDiplomacy();
		for i = 0, diplomacy:GetNumSpiesCaptured() - 1 do
			local spyInfo:table = diplomacy:GetNthCapturedSpy( other:GetID(), i );
			if spyInfo and spyInfo.OwningPlayer == localID then
				spies = spies + 1;
				local byID:number = other:GetID();
				local atWar:boolean = player:GetDiplomacy():IsAtWarWith( byID );
				local pending:boolean = DealManager.HasPendingDeal( localID, byID );
				local nameIndex = spyInfo.NameIndex;
				table.insert( items, { key = "captured:" .. byID .. ":" .. tostring( nameIndex ), kind = "captured", byID = byID, nameIndex = nameIndex,
					atWar = atWar, pending = pending,
					text = EspionageText_Spy{ name = Locale.Lookup( spyInfo.Name ), rank = Locale.Lookup( GetSpyRankNameByLevel( spyInfo.Level ) ), state = "captured", capturedBy = SRA_CivName( byID ) },
					detail = atWar and "At war, no trade possible" or ( pending and "Another deal with them is pending" or SRKey( "Enter" ) .. " asks for a trade to get the spy back" ) } );
			end
		end
	end

	-- travelling spies
	local diplomacy:table = player:GetDiplomacy();
	if diplomacy then
		for i = 0, diplomacy:GetNumSpiesOffMap() - 1 do
			local info:table = diplomacy:GetNthOffMapSpy( localID, i );
			if info and info.ReturnTurn ~= -1 then
				spies = spies + 1;
				local target:table = SRA_CityAt( info.XLocation, info.YLocation );
				table.insert( items, { key = "off:" .. tostring( info.Name ) .. ":" .. i, kind = "travel",
					text = EspionageText_Spy{ name = Locale.Lookup( info.Name ), rank = Locale.Lookup( GetSpyRankNameByLevel( info.Level ) ), state = "travel",
						destination = target ~= nil and Locale.Lookup( target:GetName() ) or nil, turns = math.max( 0, info.ReturnTurn - Game.GetCurrentGameTurn() ) },
					detail = "On the way, it can not be selected until it arrives" } );
			end
		end
	end
	return items, spies, #idle;
end

-- ---- City activity ---------------------------------------------------------------------------

local function SRA_CityItem( city:table )
	local localID:number = Game.GetLocalPlayer();
	local player:table = Players[ localID ];
	local districts:table = {};
	local cityDistricts:table = city:GetDistricts();
	if cityDistricts ~= nil then
		for _, district in cityDistricts:Members() do
			local def:table = GameInfo.Districts[ district:GetType() ];
			if district:IsComplete() and def ~= nil and def.DistrictType ~= "DISTRICT_WONDER" then table.insert( districts, Locale.Lookup( def.Name ) ); end
		end
	end
	local spies:table = {};
	for _, unit in player:GetUnits():Members() do
		if GameInfo.Units[ unit:GetUnitType() ].Spy and unit:GetSpyOperation() ~= -1 then
			local there:table = SRA_CityAt( unit:GetX(), unit:GetY() );
			if there ~= nil and there:GetOwner() == city:GetOwner() and there:GetID() == city:GetID() then
				table.insert( spies, Locale.Lookup( unit:GetName() ) );
			end
		end
	end
	local boost:number = 0;
	local diplomacy:table = player:GetDiplomacy();
	if diplomacy then boost = diplomacy:GetSourceTurnsRemaining( city ); end
	local owner:number = city:GetOwner();
	return { key = "city:" .. owner .. ":" .. city:GetID(), kind = "city", owner = owner, id = city:GetID(),
		text = EspionageText_City{ name = Locale.Lookup( city:GetName() ), owner = SRA_OwnerText( owner ),
			capital = city:IsCapital() and Players[ owner ]:IsMajor(), districts = districts, spies = spies, boostTurns = boost },
		detail = SRKey( "Enter" ) .. " shows the city on the map" };
end

local function SRA_CityItems()
	local items:table = {};
	local localID:number = Game.GetLocalPlayer();
	if localID == -1 then return items; end
	local vis:table = PlayersVisibility[ localID ];
	local function AddCities( player:table )
		for _, city in player:GetCities():Members() do
			if vis:IsRevealed( city:GetX(), city:GetY() ) then table.insert( items, SRA_CityItem( city ) ); end
		end
	end
	AddCities( Players[ localID ] );
	local minors:table = {};
	for _, player in ipairs( Game.GetPlayers() ) do
		if player:GetID() ~= localID then
			if player:IsMajor() then
				AddCities( player );
			elseif player.IsMinor ~= nil and player:IsMinor() then
				table.insert( minors, player );
			end
		end
	end
	for _, player in ipairs( minors ) do AddCities( player ); end		-- Expansion: city-states come last
	return items;
end

-- ---- Mission history -------------------------------------------------------------------------

local function SRA_HistoryItems()
	local items:table = {};
	local localID:number = Game.GetLocalPlayer();
	if localID == -1 then return items; end
	local localPlayer:table = Players[ localID ];
	local diplomacy:table = localPlayer:GetDiplomacy();
	if diplomacy == nil then return items; end
	for i = 0, diplomacy:GetNumSpiesCaptured() - 1 do
		local spyInfo:table = diplomacy:GetNthCapturedSpy( localID, i );
		if spyInfo then
			local owning:number = spyInfo.OwningPlayer;
			local canTrade:boolean = not diplomacy:IsAtWarWith( owning );
			table.insert( items, { key = "enemy:" .. owning .. ":" .. tostring( spyInfo.NameIndex ), kind = "enemy", owning = owning, nameIndex = spyInfo.NameIndex,
				canTrade = canTrade, section = "Captured enemy spies",
				text = EspionageText_EnemySpy{ name = Locale.Lookup( spyInfo.Name ), civ = SRA_CivName( owning ), canTrade = canTrade },
				detail = canTrade and SRKey( "Enter" ) .. " offers a trade for this spy" or "At war, no trade possible" } );
		end
	end
	local recent:table = diplomacy:GetRecentMissions( localID, 10, 0 );
	if recent then
		for i, mission in pairs( recent ) do
			local hidden:boolean = ( mission.InitialResult == EspionageResultTypes.SUCCESS_MUST_ESCAPE or mission.InitialResult == EspionageResultTypes.FAIL_MUST_ESCAPE )
				and mission.EscapeResult == EspionageResultTypes.NO_RESULT;
			local operationInfo:table = GameInfo.UnitOperations[ mission.Operation ];
			if not hidden and operationInfo ~= nil then
				local outcome:table = GetMissionOutcomeDetails( mission ) or {};
				local city:string = ( mission.CityName ~= nil and mission.CityName ~= "" ) and Locale.Lookup( mission.CityName ) or nil;
				table.insert( items, { key = "mission:" .. tostring( mission.CompletionTurn ) .. ":" .. tostring( i ), kind = "mission", section = "Recent missions",
					text = EspionageText_History{ name = Locale.Lookup( mission.Name ), rank = Locale.Lookup( GetSpyRankNameByLevel( mission.LevelAfter ) ),
						mission = Locale.Lookup( operationInfo.Description ) .. ( city ~= nil and ( " in " .. city ) or "" ),
						turnsAgo = Game.GetCurrentGameTurn() - mission.CompletionTurn, success = outcome.Success,
						description = SRA_Clean( outcome.Description ), status = SRA_Clean( outcome.SpyStatus ) },
					detail = SRA_Clean( outcome.Description ) } );
			end
		end
	end
	return items;
end

-- ---- list ------------------------------------------------------------------------------------

function SRA_BuildItems()
	if m_selectedTab == EspionageTabs.CITY_ACTIVITY then return SRA_CityItems(); end
	if m_selectedTab == EspionageTabs.MISSION_HISTORY then return SRA_HistoryItems(); end
	local items:table = SRA_OperativeItems();
	return items;
end

local function SRA_EmptyText()
	if m_selectedTab == EspionageTabs.CITY_ACTIVITY then return Locale.Lookup( "LOC_ESPIONAGE_NO_CITIES" ); end
	if m_selectedTab == EspionageTabs.MISSION_HISTORY then return Locale.Lookup( "LOC_ESPIONAGE_NO_HISTORY" ); end
	return Locale.Lookup( "LOC_ESPIONAGE_NO_OPERATIVES" );
end

-- Opening: "Espionage: 2 of 3 spies, 1 awaiting orders. Operatives. <first>, 1 of 2"; tab switch: "City Activity. <first>, 1 of 9".
local function SRA_AnnounceTab( opening:boolean )
	local items:table = SRA_BuildItems();
	local parts:table = {};
	if opening and Game.GetLocalPlayer() ~= -1 then
		local _unused, spies, idle = SRA_OperativeItems();
		table.insert( parts, EspionageText_Header{ spies = spies, capacity = Players[ Game.GetLocalPlayer() ]:GetDiplomacy():GetSpyCapacity(), idle = idle } );
	end
	table.insert( parts, SRA_TabNames()[ m_selectedTab ] or "" );
	if #items == 0 then
		table.insert( parts, SRA_Clean( SRA_EmptyText() ) );
	else
		m_srList.Open( "", nil, true );
		local first:string = items[1].text;
		if items[1].section ~= nil then first = items[1].section .. ": " .. first; end
		table.insert( parts, first .. ", 1 of " .. #items );
	end
	SRA_Say( table.concat( parts, ". " ), opening );
end

local function SRA_CloseQuiet()
	m_srQuiet = true;
	Close();
	m_srQuiet = false;
end

local function SRA_SwitchTab( delta:number )
	local tabs:table = SRA_VisibleTabs();
	local index:number = 1;
	for i, tab in ipairs( tabs ) do
		if tab == m_selectedTab then index = i; end
	end
	index = ( index - 1 + delta ) % #tabs + 1;
	SelectTabByIndex( tabs[ index ] );
	m_srList.Reset();
	SRA_AnnounceTab( false );
end

local function SRA_OnActivate( item:table )
	if item.kind == "spy" then
		local unit:table = Players[ Game.GetLocalPlayer() ]:GetUnits():FindID( item.id );
		if unit == nil then SRA_Say( "Spy not found" ); return; end
		UI.DeselectAllUnits();
		UI.DeselectAllCities();
		UI.SelectUnit( unit );
		UI.LookAtPlotScreenPosition( unit:GetX(), unit:GetY(), 0.42, 0.5 );
		SRA_CloseQuiet();		-- the hub announces the selected spy; the chooser opens for an idle one
	elseif item.kind == "city" then
		local player:table = Players[ item.owner ];
		local city:table = player ~= nil and player:GetCities():FindID( item.id ) or nil;
		if city == nil then SRA_Say( "City not found" ); return; end
		LookAtCity( item.owner, item.id );
		LuaEvents.SRA_CursorTo( city:GetX(), city:GetY() );
		SRA_Say( "Showing " .. Locale.Lookup( city:GetName() ) .. " on the map. The map cursor is there" );
	elseif item.kind == "captured" then
		if item.atWar then SRA_Say( "At war, no trade possible" ); return; end
		if DealManager.HasPendingDeal( Game.GetLocalPlayer(), item.byID ) then SRA_Say( "Another deal with them is pending" ); return; end
		OnAskForOperativeTradeClicked( item.byID, item.nameIndex );
		SRA_Say( "Asking for a trade" );
	elseif item.kind == "enemy" then
		if not item.canTrade then SRA_Say( "At war, no trade possible" ); return; end
		OnAskForEnemyOperativeTradeClicked( item.owning, item.nameIndex );
		SRA_Say( "Offering a trade" );
	elseif item.kind == "travel" then
		SRA_Say( "On the way, it can not be selected until it arrives" );
	else
		SRA_Say( item.detail or "Nothing to do" );
	end
end

function SRA_Closed()
	SRA_Say( "Espionage closed" );
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
	if not ok then print( "EspionageOverview announce error: " .. tostring( err ) ); end
end

local function SRA_IsFunctionKey( key:number )
	for n = 1, 12 do
		if Keys[ "VK_F" .. n ] ~= nil and Keys[ "VK_F" .. n ] == key then return true; end
	end
	return false;
end

function SRA_HandleInput( input:table )
	if m_AnimSupport == nil or not m_AnimSupport.IsVisible() then return false; end
	input = Gamepad.WrapInput( input );		-- ScreenReaderAccess: controller mode (D-pad = arrows, LB / RB = Control+Tab / Tab)
	local msg:number = input:GetMessageType();
	if msg ~= KeyEvents.KeyDown and msg ~= KeyEvents.KeyUp then return false; end
	local key:number = input:GetKey();
	if SRA_IsFunctionKey( key ) then return false; end
	if key == Keys.VK_TAB then
		if msg == KeyEvents.KeyUp then
			local delta:number = ( input:IsShiftDown() or input:IsControlDown() ) and -1 or 1;
			local ok:boolean, err = xpcall( function() SRA_SwitchTab( delta ); end, KeyNavErrorHandler );
			if not ok then print( "EspionageOverview tab error: " .. tostring( err ) ); end
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
print( "ScreenReaderAccess: EspionageOverview copy loaded" );

function Initialize()
	Controls.Title:SetText(Locale.Lookup("LOC_ESPIONAGE_TITLE"));

	-- Control Events
	Controls.CloseButton:RegisterCallback(Mouse.eLClick, OnClose);
	Controls.CloseButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	Controls.CapturedEnemyOperativeContainer:RegisterSizeChanged( OnCapturedEnemyOperativeContainerSizeChanged );

	-- Lua Events
	SRListen( LuaEvents.PartialScreenHooks_OpenEspionage, OnOpen );		-- ScreenReaderAccess
	SRListen( LuaEvents.PartialScreenHooks_CloseEspionage, OnClose );		-- ScreenReaderAccess
	SRListen( LuaEvents.PartialScreenHooks_CloseAllExcept, OnCloseAllExcept );		-- ScreenReaderAccess

	-- Animation Controller
	m_AnimSupport = CreateScreenAnimation(Controls.SlideAnim);

	-- Rundown / Screen Events
	SRListen( Events.SystemUpdateUI, m_AnimSupport.OnUpdateUI );		-- ScreenReaderAccess
	ContextPtr:SetInputHandler(SRA_InputHandler, true);		-- ScreenReaderAccess (was m_AnimSupport.OnInputHandler)
	ContextPtr:SetUpdate(SRA_OnUpdate);		-- ScreenReaderAccess
	SRA_CreateList();		-- ScreenReaderAccess

	-- Game Engine Events	
	SRListen( Events.UnitOperationStarted, OnUnitOperationStarted );		-- ScreenReaderAccess
	SRListen( Events.LocalPlayerTurnEnd, OnLocalPlayerTurnEnd );		-- ScreenReaderAccess

	SRListen( Events.InterfaceModeChanged, OnInterfaceModeChanged );		-- ScreenReaderAccess
	
	SRListen( Events.SpyAdded, OnSpyAdded );		-- ScreenReaderAccess
	SRListen( Events.SpyRemoved, OnSpyRemoved );		-- ScreenReaderAccess
	SRListen( Events.DiplomacyDealEnacted, OnDiplomacyDealEnacted );		-- ScreenReaderAccess -- Folks may be trading captured spies, if they do we must update the panel

	-- Hot-Reload Events
	ContextPtr:SetInitHandler(OnInit);
	ContextPtr:SetShutdown(OnShutdown);
	SRListen( LuaEvents.GameDebug_Return, OnGameDebugReturn );		-- ScreenReaderAccess

	PopulateTabs();
end
Initialize();
