-- ===========================================================================
--
--	Slideout panel for selecting a new destination for a spy unit
--
-- ===========================================================================
include("InstanceManager");
include("AnimSidePanelSupport");
include("SupportFunctions");
include("EspionageSupport");
include("Colors");
include("ScreenReader");		-- ScreenReaderAccess
include("KeyNavList");		-- ScreenReaderAccess
include("SRListen");		-- ScreenReaderAccess
include("EspionageText");	-- ScreenReaderAccess

-- ===========================================================================
--	CONSTANTS
-- ===========================================================================
local RELOAD_CACHE_ID:string = "EspionageChooser"; -- Must be unique (usually the same as the file name)
local MAX_BEFORE_TRUNC_CHOOSE_NEXT:number = 210;

local EspionageChooserModes:table = {
	DESTINATION_CHOOSER	= 0;
	MISSION_CHOOSER		= 1;
};

local MISSION_CHOOSER_MISSIONSCROLLPANEL_RELATIVE_SIZE_Y = -132;
local DESTINATION_CHOOSER_MISSIONSCROLLPANEL_RELATIVE_SIZE_Y = -267;

local DISTRICT_IM:string = "DistrictIM";
local DISTRICT_SCROLL_POS:string = "DistrictScrollPos";

local MAX_DISTRICTS_TO_SHOW:number = 7;

-- ===========================================================================
--	MEMBERS
-- ===========================================================================
local m_AnimSupport			:table; -- AnimSidePanelSupport

-- Current EspionageChooserMode
local m_currentChooserMode	:number = -1;

-- Instance managers
local m_RouteChoiceIM		:table = InstanceManager:new("DestinationInstance", "DestinationButton",	Controls.DestinationStack);
local m_MissionStackIM		:table = InstanceManager:new("MissionInstance",		"MissionButton",		Controls.MissionStack);

-- Currently selected spy
local m_spy					:table = nil;

-- While in DESTINATION_CHOOSER - Currently selected destination
-- While in MISSION_CHOOSER - City where the selected spy resides
local m_city				:table = nil;

-- ScreenReaderAccess: what the game lists, recorded by AddDestination / the Add*Operation functions (see the section before INIT)
local m_srDestinations		:table = {};	-- { owner, id } in the order AddDestination was called
local m_srMissions			:table = {};	-- { opHash, plotIndex, counter, reasons } in the order of the mission stack

-- ===========================================================================
function Refresh()
	if m_spy == nil then
		UI.DataError("m_spy is nil. Expected to be currently selected spy.");
		Close();
		return;
	end

	if m_city == nil and m_currentChooserMode == EspionageChooserModes.MISSION_CHOOSER then
		UI.DataError("m_city is nil while updating espionage mission chooser. Expected to be city spy currently resides in.");
		Close();
		return;
	end


	RefreshTop();
	RefreshBottom();
end

-- ===========================================================================
function RefreshTop()
	if m_currentChooserMode == EspionageChooserModes.DESTINATION_CHOOSER then
		-- DESTINATION_CHOOSER
		Controls.Title:SetText(Locale.ToUpper("LOC_ESPIONAGECHOOSER_PANEL_HEADER"));

		-- Controls that should never be visible in the DESTINATION_CHOOSER
		Controls.ActiveBoostContainer:SetHide(true);
		Controls.NoActiveBoostLabel:SetHide(true);
		
		-- If we've selected a city then show the district icons for that city
		if m_city then
			
			AddDistrictIcons(Controls, m_city);
			Controls.DistrictInfo:SetHide(false);
			Controls.SelectACityMessage:SetHide(true);

			UpdateCityBanner(m_city);
		else
			Controls.BannerBase:SetHide(true);
			Controls.DistrictsScrollLeftButton:SetHide(true);
			Controls.DistrictsScrollRightButton:SetHide(true);
			Controls.DistrictInfo:SetHide(true);
			Controls.SelectACityMessage:SetHide(false);
		end
	else
		-- MISSION_CHOOSER
		Controls.Title:SetText(Locale.ToUpper("LOC_ESPIONAGECHOOSER_CHOOSE_MISSION"));

		-- Controls that should never be visible in the MISSION_CHOOSER
		Controls.SelectACityMessage:SetHide(true);
		Controls.DistrictInfo:SetHide(true);

		-- Controls that should always be visible in the MISSION_CHOOSER
		Controls.BannerBase:SetHide(false);

		UpdateCityBanner(m_city);
		
		-- Update active gain sources boost message
		local player = Players[Game.GetLocalPlayer()];
		local playerDiplomacy:table = player:GetDiplomacy();
		if playerDiplomacy then
			local boostedTurnsRemaining:number = playerDiplomacy:GetSourceTurnsRemaining(m_city);
			if boostedTurnsRemaining > 0 then
				TruncateStringWithTooltip(Controls.ActiveBoostLabel, MAX_BEFORE_TRUNC_CHOOSE_NEXT, Locale.Lookup("LOC_ESPIONAGECHOOSER_GAIN_SOURCES_ACTIVE", boostedTurnsRemaining));
				
				--Controls.ActiveBoostLabel:SetText(Locale.Lookup("LOC_ESPIONAGECHOOSER_GAIN_SOURCES_ACTIVE", boostedTurnsRemaining));
				Controls.ActiveBoostContainer:SetHide(false);
				Controls.NoActiveBoostLabel:SetHide(true);
			else
				Controls.ActiveBoostContainer:SetHide(true);
				Controls.NoActiveBoostLabel:SetHide(false);
			end
		end
	end
end

-- ===========================================================================
function RefreshBottom()
	if m_currentChooserMode == EspionageChooserModes.DESTINATION_CHOOSER then
		-- DESTINATION_CHOOSER
		if m_city then
			Controls.DestinationPanel:SetHide(true);
			Controls.MissionPanel:SetHide(false);
			Controls.PossibleMissionsLabel:SetHide(false);
			Controls.DestinationChooserButtons:SetHide(false);
			Controls.MissionScrollPanel:SetParentRelativeSizeY(DESTINATION_CHOOSER_MISSIONSCROLLPANEL_RELATIVE_SIZE_Y);
			RefreshMissionList();
		else
			Controls.DestinationPanel:SetHide(false);
			Controls.MissionPanel:SetHide(true);
			m_RouteChoiceIM:ResetInstances();
			m_srDestinations = {};		-- ScreenReaderAccess
			RefreshDestinationList();
		end
	else
		-- MISSION_CHOOSER
		-- Controls that should never be visible in the MISSION_CHOOSER
		Controls.DestinationPanel:SetHide(true);
		Controls.PossibleMissionsLabel:SetHide(true);
		Controls.DestinationChooserButtons:SetHide(true);

		-- Controls that should always be visible in the MISSION_CHOOSER
		Controls.MissionPanel:SetHide(false);

		Controls.MissionScrollPanel:SetParentRelativeSizeY(MISSION_CHOOSER_MISSIONSCROLLPANEL_RELATIVE_SIZE_Y);
		RefreshMissionList();
	end
end

-- ===========================================================================
-- Refresh the destination list with all revealed non-city state owned cities
-- ===========================================================================
function RefreshDestinationList()
	local localPlayerID = Game.GetLocalPlayer();
	local localPlayer = Players[localPlayerID];
	if localPlayer == nil then
		return;
	end

	-- Add each players cities to destination list
	local players:table = Game.GetPlayers();
	for i, player in ipairs(players) do
		local diploStateID:number = player:GetDiplomaticAI():GetDiplomaticStateIndex( localPlayerID );
		if diploStateID ~= -1 then
			local disploState:string = GameInfo.DiplomaticStates[diploStateID].StateType;
			-- Only show full civs
			if player:IsMajor() and disploState ~= "DIPLO_STATE_ALLIED" then
				if (player:GetID() == localPlayer:GetID() or player:GetTeam() == -1 or localPlayer:GetTeam() == -1 or player:GetTeam() ~= localPlayer:GetTeam()) then
					AddPlayerCities(player);
				end
			end
		end
	end

	Controls.DestinationPanel:CalculateInternalSize();
end

-- ===========================================================================
-- Refresh the mission list with counterspy targets for cities the player owns
-- and offensive spy operations for cities owned by other players
-- ===========================================================================
function RefreshMissionList()
	m_MissionStackIM:ResetInstances();
	m_srMissions = {};		-- ScreenReaderAccess

	-- Determine if this is a owned by the local player
	if m_city:GetOwner() == Game.GetLocalPlayer() then
		-- If we own this city show a list of possible counterspy targets
		for operation in GameInfo.UnitOperations() do
			if operation.OperationType == "UNITOPERATION_SPY_COUNTERSPY" then
				local cityPlot:table = Map.GetPlot(m_city:GetX(), m_city:GetY());
				local canStart:boolean, results:table = UnitManager.CanStartOperation( m_spy, operation.Hash, cityPlot, false, true);
				if canStart then
					-- Check the CanStartOperation results for a target district plot
					for i,districtPlotID in ipairs(results[UnitOperationResults.PLOTS]) do
						AddCounterspyOperation(operation, districtPlotID);
					end
				end
			end
		end
	else
		-- Fill mission stack with possible missions at selected city
		for operation in GameInfo.UnitOperations() do
			if operation.CategoryInUI == "OFFENSIVESPY" then
				local cityPlot:table = Map.GetPlot(m_city:GetX(), m_city:GetY());
				local canStart:boolean, results:table = UnitManager.CanStartOperation( m_spy, operation.Hash, cityPlot, false, true);
				if canStart then
					local bAddedOperation:boolean = false;

					-- Look through the results to determine if this operation is targeting a specific district
					if results and results[UnitOperationResults.PLOTS] then
						for i,districtPlotID in ipairs(results[UnitOperationResults.PLOTS]) do
							local pTargetPlot:table = Map.GetPlotByIndex(districtPlotID);
							if pTargetPlot ~= nil then
								AddAvailableOffensiveOperation(operation, results, pTargetPlot);
								bAddedOperation = true;
							end
						end
					end

					-- If the operation wasn't added with a specific district then just use the city
					if bAddedOperation == false then
						AddAvailableOffensiveOperation(operation, results, cityPlot);
					end
				else
					---- If we're provided with a failure reason then show the mission disabled
					if results and results[UnitOperationResults.FAILURE_REASONS] then
						AddDisabledOffensiveOperation(operation, results, cityPlot);
					end
				end
			end
		end
	end

	Controls.MissionScrollPanel:CalculateInternalSize();
end

-- ===========================================================================
function AddCounterspyOperation(operation:table, districtPlotID:number)
	SRA_RecordMission( operation, districtPlotID, true, nil );		-- ScreenReaderAccess
	local missionInstance:table = m_MissionStackIM:GetInstance();

	-- Find district
	local cityDistricts:table = m_city:GetDistricts();
	for i,district in cityDistricts:Members() do
		local districtPlot:table = Map.GetPlot(district:GetX(), district:GetY());
		if districtPlot:GetIndex() == districtPlotID then
			local districtInfo:table = GameInfo.Districts[district:GetType()];

			-- Update mission info
			missionInstance.MissionName:SetText(Locale.Lookup(operation.Description));
			missionInstance.MissionDetails:SetText(Locale.Lookup("LOC_ESPIONAGECHOOSER_COUNTERSPY", Locale.Lookup(districtInfo.Name)));
			missionInstance.MissionDetails:SetColorByName("White");

			-- Update mission icon
			local iconString:string = "ICON_" .. districtInfo.DistrictType;
			missionInstance.TargetDistrictIcon:SetIcon(iconString);
			missionInstance.TargetDistrictIcon:SetHide(false);
			missionInstance.MissionIcon:SetHide(true);

			-- If this is the mission choose set callback to open up mission briefing
			if m_currentChooserMode == EspionageChooserModes.MISSION_CHOOSER then
				missionInstance.MissionButton:RegisterCallback( Mouse.eLClick, function() OnCounterspySelected(districtPlot); end );
			end
		end
	end
	
	missionInstance.MissionStatsStack:SetHide(true);

	-- While in DESTINATION_CHOOSER mode we don't want the buttons to act
	-- like buttons since they cannot be clicked in that mode
	if m_currentChooserMode == EspionageChooserModes.DESTINATION_CHOOSER then
		missionInstance.MissionButton:SetDisabled(true);
		missionInstance.MissionButton:SetVisState(0);
	else
		missionInstance.MissionButton:SetDisabled(false);
	end

	-- Default the selector brace to hidden
	missionInstance.SelectorBrace:SetColor(UI.GetColorValueFromHexLiteral(0x00FFFFFF));
end

-- ===========================================================================
function AddOffensiveOperation(operation:table, result:table, targetCityPlot:table)
	local missionInstance:table = m_MissionStackIM:GetInstance();
	missionInstance.MissionButton:SetDisabled(false);

	-- Update mission name
	missionInstance.MissionName:SetText(Locale.Lookup(operation.Description));

	-- Update mission icon
	missionInstance.MissionIcon:SetIcon(operation.Icon);
	missionInstance.MissionIcon:SetHide(false)
	missionInstance.TargetDistrictIcon:SetHide(true);

	RefreshMissionStats(missionInstance, operation, result, m_spy, m_city, targetCityPlot);

	missionInstance.MissionStatsStack:SetHide(false);
	missionInstance.MissionStatsStack:CalculateSize();

	-- Default the selector brace to hidden
	missionInstance.SelectorBrace:SetColor(UI.GetColorValueFromHexLiteral(0x00FFFFFF));

	return missionInstance;
end

-- ===========================================================================
function AddDisabledOffensiveOperation(operation:table, result:table, targetCityPlot:table)
	SRA_RecordMission( operation, targetCityPlot:GetIndex(), false, result[UnitOperationResults.FAILURE_REASONS] or { "" } );		-- ScreenReaderAccess
	local missionInstance:table = AddOffensiveOperation(operation, result, targetCityPlot);

	-- Update mission description with reason the mission is disabled
	if result and result[UnitOperationResults.FAILURE_REASONS] then
		local failureReasons:table = result[UnitOperationResults.FAILURE_REASONS];
		local missionDetails:string = "";

		-- Add all given reasons into mission details
		for i,reason in ipairs(failureReasons) do
			if missionDetails == "" then
				missionDetails = reason;
			else
				missionDetails = missionDetails .. "[NEWLINE]" .. reason;
			end
		end

		missionInstance.MissionDetails:SetText(missionDetails);
		missionInstance.MissionDetails:SetColorByName("Red");
	end

	missionInstance.MissionStack:CalculateSize();
	missionInstance.MissionButton:DoAutoSize();

	-- Disable mission button
	missionInstance.MissionButton:SetDisabled(true);
end

-- ===========================================================================
function AddAvailableOffensiveOperation(operation:table, result:table, pTargetPlot:table)
	SRA_RecordMission( operation, pTargetPlot:GetIndex(), false, nil );		-- ScreenReaderAccess
	local missionInstance:table = AddOffensiveOperation(operation, result, pTargetPlot);

	-- Update mission details
	missionInstance.MissionDetails:SetText(GetFormattedOperationDetailText(operation, m_spy, m_city));
	missionInstance.MissionDetails:SetColorByName("White");

	missionInstance.MissionStack:CalculateSize();
	missionInstance.MissionButton:DoAutoSize();

	-- If this is the mission choose set callback to open up mission briefing
	if m_currentChooserMode == EspionageChooserModes.MISSION_CHOOSER then
		missionInstance.MissionButton:RegisterCallback( Mouse.eLClick, function() OnMissionSelected(operation, missionInstance, pTargetPlot); end );
	end

	-- While in DESTINATION_CHOOSER mode we don't want the buttons to act
	-- like buttons since they cannot be clicked in that mode
	if m_currentChooserMode == EspionageChooserModes.DESTINATION_CHOOSER then
		missionInstance.MissionButton:SetDisabled(true);
		missionInstance.MissionButton:SetVisState(0);
	else
		missionInstance.MissionButton:SetDisabled(false);
	end
end

-- ===========================================================================
function OnCounterspySelected(districtPlot:table)
	local tParameters:table = {};
	tParameters[UnitOperationTypes.PARAM_X] = districtPlot:GetX();
	tParameters[UnitOperationTypes.PARAM_Y] = districtPlot:GetY();

	UnitManager.RequestOperation(m_spy, UnitOperationTypes.SPY_COUNTERSPY, tParameters);
end

-- ===========================================================================
function OnMissionSelected(operation:table, instance:table, pTargetPlot:table)
	LuaEvents.EspionageChooser_ShowMissionBriefing(operation.Hash, m_spy:GetID(), pTargetPlot);

	-- Hide all selection borders before selecting another
	for i=1, m_MissionStackIM.m_iCount, 1 do
		local otherInstances:table = m_MissionStackIM:GetAllocatedInstance(i);
		if otherInstances then
			otherInstances.SelectorBrace:SetColor(UI.GetColorValue("COLOR_CLEAR"));
		end
	end

	-- Show selected border over instance
	instance.SelectorBrace:SetColor(UI.GetColorValue("COLOR_WHITE"));
end

-- ===========================================================================
function UpdateCityBanner(city:table)
	local backColor:number, frontColor:number  = UI.GetPlayerColors( city:GetOwner() );

	Controls.BannerBase:SetColor( backColor );
		Controls.CityName:SetColor( frontColor );
	TruncateStringWithTooltip(Controls.CityName, 195, Locale.ToUpper(city:GetName()));
	Controls.BannerBase:SetHide(false);

	if m_currentChooserMode == EspionageChooserModes.DESTINATION_CHOOSER then
		-- Update travel time
		local travelTime:number = UnitManager.GetTravelTime(m_spy, m_city);
		local establishTime:number = UnitManager.GetEstablishInCityTime(m_spy, m_city);
		local totalTravelTime:number = travelTime + establishTime;
		Controls.TravelTime:SetColor( frontColor );
		Controls.TravelTime:SetText(tostring(totalTravelTime));
		Controls.TravelTimeIcon:SetColor( frontColor )
		Controls.TravelTimeStack:SetHide(false);

		-- Update travel time tool tip string
		Controls.BannerBase:SetToolTipString(Locale.Lookup("LOC_ESPIONAGECHOOSER_TRAVEL_TIME_TOOLTIP", travelTime, establishTime));
	else
		Controls.TravelTimeStack:SetHide(true);
		Controls.BannerBase:SetToolTipString("");
	end
end

-- ===========================================================================
function AddPlayerCities(player:table)
	local playerCities:table = player:GetCities();
	for j, city in playerCities:Members() do
		-- Check if the city is revealed
		local localPlayerVis:table = PlayersVisibility[Game.GetLocalPlayer()];
		if localPlayerVis:IsRevealed(city:GetX(), city:GetY()) then
			AddDestination(city);
		end
	end
end

-- ===========================================================================
function AddDestination(city:table)
	table.insert( m_srDestinations, { owner = city:GetOwner(), id = city:GetID() } );		-- ScreenReaderAccess
	local destinationInstance:table = m_RouteChoiceIM:GetInstance();

	-- Update city name and banner color
	local backColor:number, frontColor:number  = UI.GetPlayerColors( city:GetOwner() );

	destinationInstance.BannerBase:SetColor( backColor );	
	destinationInstance.CityName:SetColor( frontColor );

	-- Update capital indicator but never show it for city-states
	if city:IsCapital() and Players[city:GetOwner()]:IsMajor() then
		TruncateStringWithTooltip(destinationInstance.CityName, 185, "[ICON_Capital] " .. Locale.ToUpper(city:GetName()));
	else
		TruncateStringWithTooltip(destinationInstance.CityName, 185, Locale.ToUpper(city:GetName()));
	end

	-- Update travel time
	local travelTime:number = UnitManager.GetTravelTime(m_spy, city);
	local establishTime:number = UnitManager.GetEstablishInCityTime(m_spy, city);
	local totalTravelTime:number = travelTime + establishTime;
	destinationInstance.TravelTime:SetColor( frontColor );
	destinationInstance.TravelTime:SetText(tostring(totalTravelTime));
	destinationInstance.TravelTimeIcon:SetColor( frontColor )

	-- Update travel time tool tip string
	destinationInstance.BannerBase:SetToolTipString(Locale.Lookup("LOC_ESPIONAGECHOOSER_TRAVEL_TIME_TOOLTIP", travelTime, establishTime));

	AddDistrictIcons(destinationInstance, city);

	-- Set button callback
	destinationInstance.DestinationButton:RegisterCallback( Mouse.eLClick, function() OnSelectDestination(city);  end);
end

-- ===========================================================================
function AddDistrictIcons( kParentControl:table, pCity:table )
	if kParentControl[DISTRICT_IM] == nil then
		kParentControl[DISTRICT_IM] = InstanceManager:new("CityDistrictInstance", "DistrictIcon", kParentControl.DistrictIconStack);
	end

	kParentControl[DISTRICT_IM]:ResetInstances();

	local iNumDistricts:number = 0;
	local pCityDistricts:table = pCity:GetDistricts();
	for _, pDistrict in pCityDistricts:Members() do
		local kDistrictInst:table = AddDistrictIcon(kParentControl[DISTRICT_IM], pCity, pDistrict);
		if kDistrictInst ~= nil then
			iNumDistricts = iNumDistricts + 1;

			if iNumDistricts > MAX_DISTRICTS_TO_SHOW then
				kDistrictInst.DistrictIcon:SetHide(true);
			else
				kDistrictInst.DistrictIcon:SetHide(false);
			end
		end
	end

	if iNumDistricts > MAX_DISTRICTS_TO_SHOW then
		kParentControl.DistrictsScrollLeftButton:SetHide(false);
		kParentControl.DistrictsScrollLeftButton:SetDisabled(true);
		kParentControl.DistrictsScrollRightButton:SetHide(false);
		kParentControl.DistrictsScrollRightButton:SetDisabled(false);
		kParentControl[DISTRICT_SCROLL_POS] = 1;
	else
		kParentControl.DistrictsScrollLeftButton:SetHide(true);
		kParentControl.DistrictsScrollRightButton:SetHide(true);
	end

	kParentControl.DistrictsScrollLeftButton:RegisterCallback( Mouse.eLClick, function() OnDistrictLeftScroll(kParentControl); end );
	kParentControl.DistrictsScrollRightButton:RegisterCallback( Mouse.eLClick, function() OnDistrictRightScroll(kParentControl); end );
end

-- ===========================================================================
function UpdateVisibleDistrictIcons( kParentControl:table, iScrollPos:number )
	local kDistrictIM:table = kParentControl[DISTRICT_IM];
	for i=1, kDistrictIM.m_iCount, 1 do
		local kDistrictInst:table = kDistrictIM:GetAllocatedInstance(i);
		if kDistrictInst ~= nil then
			if i < iScrollPos or (i > iScrollPos + MAX_DISTRICTS_TO_SHOW - 1) then
				kDistrictInst.DistrictIcon:SetHide(true);
			else
				kDistrictInst.DistrictIcon:SetHide(false);
			end
		end
	end

	kParentControl[DISTRICT_SCROLL_POS] = iScrollPos;

	if iScrollPos == 1 then
		kParentControl.DistrictsScrollLeftButton:SetDisabled(true);
		kParentControl.DistrictsScrollRightButton:SetDisabled(false);
	elseif iScrollPos >= (kDistrictIM.m_iCount - MAX_DISTRICTS_TO_SHOW + 1) then
		kParentControl.DistrictsScrollLeftButton:SetDisabled(false);
		kParentControl.DistrictsScrollRightButton:SetDisabled(true);
	else
		kParentControl.DistrictsScrollLeftButton:SetDisabled(false);
		kParentControl.DistrictsScrollRightButton:SetDisabled(false);
	end
end

-- ===========================================================================
function OnDistrictLeftScroll( kParentControl:table )
	local iNewScrollPos:number = kParentControl[DISTRICT_SCROLL_POS] - 1;
	UpdateVisibleDistrictIcons( kParentControl, iNewScrollPos );
end

-- ===========================================================================
function OnDistrictRightScroll( kParentControl:table )
	local iNewScrollPos:number = kParentControl[DISTRICT_SCROLL_POS] + 1;
	UpdateVisibleDistrictIcons( kParentControl, iNewScrollPos );
end

-- ===========================================================================
function AddDistrictIcon(kInstanceIM:table, pCity:table, pDistrict:table)
	if not pDistrict:IsComplete() then
		return nil;
	end

	local kDistrictDef:table = GameInfo.Districts[pDistrict:GetType()];
	if kDistrictDef == nil or kDistrictDef.DistrictType == "DISTRICT_WONDER" then
		return nil;
	end

	local kInstance:table = kInstanceIM:GetInstance();

	kInstance.DistrictIcon:SetIcon("ICON_" .. kDistrictDef.DistrictType);
	local sToolTip:string = Locale.Lookup(kDistrictDef.Name);
	kInstance.DistrictIcon:SetToolTipString( sToolTip );

	return kInstance;
end

-- ===========================================================================
function RefreshDistrictIcon(city:table, districtType:string, districtIcon:table)
	local hasDistrict:boolean = false;
	local cityDistricts:table = city:GetDistricts();
	for i, district in cityDistricts:Members() do
		if district:IsComplete() then
			
			--gets the district type of the currently selected district 
			local districtInfo:table = GameInfo.Districts[district:GetType()];
			local currentDistrictType = districtInfo.DistrictType

			--assigns currentDistrictType to be the general type of district (i.e. DISTRICT_HANSA becomes DISTRICT_INDUSTRIAL_ZONE)
			local replaces = GameInfo.DistrictReplaces[districtInfo.Hash];
			if(replaces) then
				currentDistrictType = GameInfo.Districts[replaces.ReplacesDistrictType].DistrictType
			end

			--if this district is the type we are looking for, display that
			if currentDistrictType == districtType then
				hasDistrict = true;
			end
		end
	end

	if hasDistrict then
		districtIcon:SetHide(false);
	else
		districtIcon:SetHide(true);
	end
end

-- ===========================================================================
function OnSelectDestination(city:table)
	m_city = city;

	-- Look at the selected destination
	UI.LookAtPlot(m_city:GetX(), m_city:GetY());

	Refresh();
end

-- ===========================================================================
function TeleportToSelectedCity()
	if not m_city or not m_spy then
		return
	end

	local tParameters:table = {};
	tParameters[UnitOperationTypes.PARAM_X] = m_city:GetX();
	tParameters[UnitOperationTypes.PARAM_Y] = m_city:GetY();

	if (UnitManager.CanStartOperation( m_spy, UnitOperationTypes.SPY_TRAVEL_NEW_CITY, Map.GetPlot(m_city:GetX(), m_city:GetY()), tParameters)) then
		UnitManager.RequestOperation( m_spy, UnitOperationTypes.SPY_TRAVEL_NEW_CITY, tParameters);
		UI.SetInterfaceMode(InterfaceModeTypes.SELECTION);
	end
end

-- ===========================================================================
function Open()
	-- Set chooser mode based on interface mode
	if UI.GetInterfaceMode() == InterfaceModeTypes.SPY_TRAVEL_TO_CITY then
		m_currentChooserMode = EspionageChooserModes.DESTINATION_CHOOSER;
	else
		m_currentChooserMode = EspionageChooserModes.MISSION_CHOOSER;
	end

	-- Cache the selected spy
	local selectedUnit:table = UI.GetHeadSelectedUnit();
	if selectedUnit then
		local selectedUnitInfo:table = GameInfo.Units[selectedUnit:GetUnitType()];
		if selectedUnitInfo and selectedUnitInfo.Spy then
			m_spy = selectedUnit;
		else
			m_spy = nil;
			return;
		end
	else
		m_spy = nil;
		return;
	end

	-- Set m_city depending on the mode
	if m_currentChooserMode == EspionageChooserModes.DESTINATION_CHOOSER then
		-- Clear m_city for Destination Chooser as it will be the city the player chooses
		m_city = nil;
	else
		-- Set m_city to city where in for Mission Chooser as we only want missions from this city
		local spyPlot:table = Map.GetPlot(m_spy:GetX(), m_spy:GetY());
		local city:table = Cities.GetPlotPurchaseCity(spyPlot);
		m_city = city;
	end
	
	if not m_AnimSupport:IsVisible() then
		m_AnimSupport:Show();
	end

	Refresh();
	
	-- Play opening sound
	UI.PlaySound("Tech_Tray_Slide_Open");
	SRA_ArmOpen();		-- ScreenReaderAccess
end

-- ===========================================================================
function Close()
	if m_AnimSupport:IsVisible() then
		SRA_ClearConfirm();		-- ScreenReaderAccess
		m_AnimSupport:Hide();
		UI.SetInterfaceMode(InterfaceModeTypes.SELECTION);
        UI.PlaySound("Tech_Tray_Slide_Closed");
	end
end

-- ===========================================================================
function OnConfirmPlacement()
	-- If we're selecting a city we own and we're already there switch to the counterspy mission chooser
	local spyPlot:table = Map.GetPlot(m_spy:GetX(), m_spy:GetY());
	local spyCity:table = Cities.GetPlotPurchaseCity(spyPlot);
	if m_city:GetOwner() == Game.GetLocalPlayer() and spyCity:GetID() == m_city:GetID() and m_city:GetOwner() == spyCity:GetOwner() then
		m_currentChooserMode = EspionageChooserModes.MISSION_CHOOSER;
		Refresh();
	else
		TeleportToSelectedCity();
		UI.PlaySound("UI_Spy_Confirm_Placement");
	end
end

-- ===========================================================================
function OnCancel()
	m_city = nil;
	Refresh();
end

-- ===========================================================================
function OnInterfaceModeChanged( oldMode:number, newMode:number )
	if oldMode == InterfaceModeTypes.SPY_CHOOSE_MISSION and newMode ~= InterfaceModeTypes.SPY_TRAVEL_TO_CITY then
		if m_AnimSupport:IsVisible() then
			Close();
		end
	end
	if oldMode == InterfaceModeTypes.SPY_TRAVEL_TO_CITY and newMode ~= InterfaceModeTypes.SPY_CHOOSE_MISSION then
		if m_AnimSupport:IsVisible() then
			Close();
		end
	end

	if newMode == InterfaceModeTypes.SPY_TRAVEL_TO_CITY then
		Open();
	end
	if newMode == InterfaceModeTypes.SPY_CHOOSE_MISSION then
		Open();
	end
end

-- ===========================================================================
function OnUnitSelectionChanged( playerID : number, unitID : number, hexI : number, hexJ : number, hexK : number, bSelected : boolean, bEditable : boolean)
	-- Make sure we're the local player and not observing
	if playerID ~= Game.GetLocalPlayer() or playerID == -1 then
		return;
	end

	-- Make sure the selected unit is a spy and that we don't have a current spy operation
	GoToProperInterfaceMode(UI.GetHeadSelectedUnit());
end

------------------------------------------------------------------
function OnUnitActivityChanged( playerID :number, unitID :number, eActivityType :number)
	-- Make sure we're the local player and not observing
	if playerID ~= Game.GetLocalPlayer() or playerID == -1 then
		return;
	end

	GoToProperInterfaceMode(UI.GetHeadSelectedUnit());
end

-- ===========================================================================
function GoToProperInterfaceMode(spyUnit:table)
	local desiredInterfaceMode:number = nil;

	if spyUnit and spyUnit:IsReadyToMove() then
		local spyUnitInfo:table = GameInfo.Units[spyUnit:GetUnitType()];
		if spyUnitInfo.Spy then
			-- Make sure the spy is awake
			local activityType:number = UnitManager.GetActivityType(spyUnit);
			if activityType == ActivityTypes.ACTIVITY_AWAKE then
				local spyPlot:table = Map.GetPlot(spyUnit:GetX(), spyUnit:GetY());
				local city:table = Cities.GetPlotPurchaseCity(spyPlot);
				if city and city:GetOwner() == Game.GetLocalPlayer() then
					--UI.SetInterfaceMode(InterfaceModeTypes.SPY_TRAVEL_TO_CITY);
					desiredInterfaceMode = InterfaceModeTypes.SPY_TRAVEL_TO_CITY;
				else
					--UI.SetInterfaceMode(InterfaceModeTypes.SPY_CHOOSE_MISSION);
					desiredInterfaceMode = InterfaceModeTypes.SPY_CHOOSE_MISSION;
				end
			end
		end
	end

	if desiredInterfaceMode then
		if UI.GetInterfaceMode() == desiredInterfaceMode then
			-- If already in the right interfacec mode then just refresh
			Open();
		else
			UI.SetInterfaceMode(desiredInterfaceMode);
		end
	else
		-- If not going to an espionage interface mode then close if we're open
		if m_AnimSupport:IsVisible() then
			Close();
		end
	end
end

------------------------------------------------------------------------------------------------
function OnLocalPlayerTurnEnd()
	if(GameConfiguration.IsHotseat()) then
		Close();
	end
end

-- ===========================================================================
function OnMissionBriefingClosed()
	if m_AnimSupport:IsVisible() then
		-- If we're shown and we close a mission briefing hide the selector brace for all to make sure it gets hidden probably
		for i=1,m_MissionStackIM.m_iCount,1 do
			local instance:table = m_MissionStackIM:GetAllocatedInstance(i);
			if instance then
				instance.SelectorBrace:SetColor(UI.GetColorValue("COLOR_CLEAR"));
			end
		end
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

-- ===========================================================================
function OnClose()
	Close();
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
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "selectedCity", m_city);
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "selectedSpy", m_spy);
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "currentChooserMode", m_currentChooserMode);
end

-- ===========================================================================
--	LUA EVENT
--	Reload support
-- ===========================================================================
function OnGameDebugReturn(context:string, contextTable:table)
	if context == RELOAD_CACHE_ID then
		if contextTable["currentChooserMode"] ~= nil then			
			m_currentChooserMode = contextTable["currentChooserMode"];
		end
		if contextTable["selectedCity"] ~= nil then			
			m_city = contextTable["selectedCity"];
		end
		if contextTable["selectedSpy"] ~= nil then			
			m_spy = contextTable["selectedSpy"];
		end
		if contextTable["isVisible"] ~= nil and contextTable["isVisible"] then			
			m_AnimSupport:Show();
			Refresh();
		end
	end
end

-- ===========================================================================
--	ScreenReaderAccess: keyboard navigation and speech
--	Opens 0.4 s after Open() (a spy was selected) in one of the game's two modes.
--	Destination mode (the spy is in one of your cities): "Choose destination for Ana: 6 cities. Thebes, Egypt, 4 turns,
--	1 of 6". The list is what AddDestination put on the screen (recorded in m_srDestinations, so the expansion's
--	RefreshDestinationList decides who is listed). Enter selects the city through OnSelectDestination and asks "Send Ana
--	to Thebes? Arrives in 4 turns ... Enter to confirm, Escape to go back"; Enter again calls OnConfirmPlacement (one of
--	your own cities opens the counterspy mission list instead), Escape calls OnCancel. Space reads the districts and the
--	travel time, or in the question the missions available there.
--	Mission mode (the spy is in a city): "Choose mission in Thebes: 5 missions. Steal tech boost, 75 percent success,
--	8 turns, 1 of 5", recorded from AddCounterspyOperation / AddAvailableOffensiveOperation / AddDisabledOffensiveOperation
--	and re-read from the game (probabilities, turns) at key time. Enter asks "Start ...? Enter to confirm", Enter again
--	requests the operation exactly like the mission briefing's Accept button (UnitManager.RequestOperation; counterspy
--	with the district as the target, as OnCounterspySelected does). Space = what the mission does and the chances of
--	success, failure and losing the spy. Escape in the list closes ("Cancelled"). Every keyboard event is swallowed
--	while the chooser is shown.
-- ===========================================================================
local m_srList				:table = nil;
local m_srConfirm			:table = nil;		-- { kind = "travel" | "mission", ... } while a question is asked
local m_srOpenPending		:boolean = false;
local m_srOpenDelay			:number = 0;
local SRA_OPEN_DELAY		:number = 0.4;

local function SRA_Say( text:string, nointerrupt:boolean )
	OutputMessageToScreenReader( text, nointerrupt );
end

local function SRA_Clean( text:string )
	return CleanTextForSpeech( text or "" );
end

local function SRA_SpyName()
	if m_spy == nil then return ""; end
	return Locale.Lookup( m_spy:GetName() );
end

local function SRA_CityName( city:table )
	return Locale.Lookup( city:GetName() );
end

local function SRA_OwnerText( ownerID:number )
	if ownerID == Game.GetLocalPlayer() then return "yours"; end
	local player:table = Players[ ownerID ];
	if player ~= nil and player:GetInfluence():CanReceiveInfluence() then return "city-state"; end
	local config:table = PlayerConfigurations[ ownerID ];
	if config == nil then return nil; end
	return Locale.Lookup( config:GetCivilizationShortDescription() );
end

local function SRA_Plural( n:number, one:string, many:string )
	return n .. " " .. ( n == 1 and one or many );
end

-- ---- recording what the game lists -----------------------------------------------------------

function SRA_RecordMission( operation:table, plotIndex:number, counter:boolean, reasons:table )
	table.insert( m_srMissions, { opHash = operation.Hash, plotIndex = plotIndex, counter = counter, reasons = reasons } );
end

-- ---- destinations ----------------------------------------------------------------------------

local function SRA_TravelTimes( city:table )
	local travel:number = UnitManager.GetTravelTime( m_spy, city );
	local establish:number = UnitManager.GetEstablishInCityTime( m_spy, city );
	return travel, establish;
end

local function SRA_DistrictNames( city:table )
	local names:table = {};
	local districts:table = city:GetDistricts();
	if districts ~= nil then
		for _, district in districts:Members() do
			local def:table = GameInfo.Districts[ district:GetType() ];
			if district:IsComplete() and def ~= nil and def.DistrictType ~= "DISTRICT_WONDER" then table.insert( names, Locale.Lookup( def.Name ) ); end
		end
	end
	return names;
end

local function SRA_DestinationItems()
	local items:table = {};
	if m_spy == nil then return items; end
	for _, entry in ipairs( m_srDestinations ) do
		local city:table = CityManager.GetCity( entry.owner, entry.id );
		if city ~= nil then
			local travel:number, establish:number = SRA_TravelTimes( city );
			local cityOwner:number, cityID:number = entry.owner, entry.id;
			table.insert( items, {
				key = "d:" .. cityOwner .. ":" .. cityID, owner = cityOwner, id = cityID, name = SRA_CityName( city ),
				text = EspionageText_Destination{ name = SRA_CityName( city ), owner = SRA_OwnerText( cityOwner ),
					capital = city:IsCapital() and Players[ cityOwner ]:IsMajor(), turns = travel + establish },
				detail = function()
					local parts:table = { "Travel " .. SRA_Plural( travel, "turn", "turns" ) .. " plus " .. SRA_Plural( establish, "turn", "turns" ) .. " to establish" };
					local districts:table = SRA_DistrictNames( city );
					if #districts > 0 then table.insert( parts, "Districts: " .. table.concat( districts, ", " ) ); end
					return table.concat( parts, ". " );
				end,
			} );
		end
	end
	return items;
end

-- ---- missions --------------------------------------------------------------------------------

local function SRA_MissionPlot( entry:table )
	return Map.GetPlotByIndex( entry.plotIndex );
end

local function SRA_MissionDistrict( entry:table, plot:table )
	if plot == nil then return nil; end
	local def:table = GameInfo.Districts[ plot:GetDistrictType() ];
	if def == nil then return nil; end
	if not entry.counter and def.DistrictType == "DISTRICT_CITY_CENTER" then return nil; end
	return Locale.Lookup( def.Name );
end

-- { success, failure, lost } in whole percents, nil when the game gives no odds for this mission
local function SRA_Outcomes( operation:table, plot:table )
	if m_spy == nil or plot == nil then return nil; end
	local probability:table = UnitManager.GetResultProbability( operation.Index, m_spy, plot );
	if probability == nil or probability[ "ESPIONAGE_SUCCESS_UNDETECTED" ] == nil then return nil; end
	local success:number = probability[ "ESPIONAGE_SUCCESS_UNDETECTED" ] + ( probability[ "ESPIONAGE_SUCCESS_MUST_ESCAPE" ] or 0 );
	success = math.floor( success * 100 + 0.5 );
	local failure:number = ( probability[ "ESPIONAGE_FAIL_UNDETECTED" ] or 0 ) + ( probability[ "ESPIONAGE_FAIL_MUST_ESCAPE" ] or 0 );
	failure = math.floor( failure * 100 + 0.5 );
	return { success = success, failure = failure, lost = math.max( 0, 100 - success - failure ) };
end

local function SRA_MissionData( entry:table )
	local operation:table = GameInfo.UnitOperations[ entry.opHash ];
	if operation == nil then return nil; end
	local plot:table = SRA_MissionPlot( entry );
	local data:table = { operation = operation, plot = plot, name = Locale.Lookup( operation.Description ),
		district = SRA_MissionDistrict( entry, plot ) };
	if entry.reasons ~= nil then
		data.reason = SRA_Clean( table.concat( entry.reasons, ". " ) );
		if data.reason == "" then data.reason = "not possible now"; end
		return data;
	end
	data.turns = UnitManager.GetTimeToComplete( operation.Index, m_spy );
	if not entry.counter then
		local outcomes:table = SRA_Outcomes( operation, plot );
		if outcomes ~= nil then data.chance = outcomes.success; data.outcomes = outcomes; end
	end
	return data;
end

local function SRA_MissionDetail( entry:table, data:table )
	local parts:table = {};
	if data.reason ~= nil then
		table.insert( parts, "Unavailable: " .. data.reason );
	elseif entry.counter then
		table.insert( parts, SRA_Clean( Locale.Lookup( "LOC_ESPIONAGECHOOSER_COUNTERSPY", data.district or "" ) ) );
	elseif m_city ~= nil then
		table.insert( parts, SRA_Clean( GetFormattedOperationDetailText( data.operation, m_spy, m_city ) ) );
	end
	if data.outcomes ~= nil then table.insert( parts, EspionageText_Outcomes( data.outcomes ) ); end
	if data.turns ~= nil then table.insert( parts, SRA_Plural( data.turns, "turn", "turns" ) .. " to complete" ); end
	return table.concat( parts, ". " );
end

local function SRA_MissionItems()
	local items:table = {};
	if m_spy == nil or m_city == nil then return items; end
	for _, entry in ipairs( m_srMissions ) do
		local data:table = SRA_MissionData( entry );
		if data ~= nil then
			local recorded:table = entry;
			table.insert( items, {
				key = "m:" .. entry.opHash .. ":" .. entry.plotIndex, entry = recorded, name = data.name, district = data.district,
				choosable = ( data.reason == nil ), reason = data.reason and ( data.name .. " is unavailable: " .. data.reason ) or nil,
				text = EspionageText_Mission{ name = data.name, district = data.district, chance = data.chance, turns = data.turns, reason = data.reason, noName = entry.counter },
				detail = function() return SRA_MissionDetail( recorded, data ); end,
			} );
		end
	end
	return items;
end

-- ---- the list --------------------------------------------------------------------------------

local function SRA_IsDestinationList()
	return m_currentChooserMode == EspionageChooserModes.DESTINATION_CHOOSER and m_city == nil;
end

function SRA_BuildItems()
	if m_spy == nil then return {}; end
	if SRA_IsDestinationList() then return SRA_DestinationItems(); end
	return SRA_MissionItems();
end

local function SRA_Head()
	if SRA_IsDestinationList() then return "Choose destination for " .. SRA_SpyName(); end
	if m_city ~= nil and m_srMissions[ 1 ] ~= nil and m_srMissions[ 1 ].counter then return "Counterspy missions in " .. SRA_CityName( m_city ); end
	if m_city ~= nil then return "Choose mission in " .. SRA_CityName( m_city ); end
	return "Choose";
end

local function SRA_AnnounceList()
	local items:table = SRA_BuildItems();
	local noun:string = SRA_IsDestinationList() and "cities" or "missions";
	local single:string = SRA_IsDestinationList() and "city" or "mission";
	if #items == 0 then
		SRA_Say( SRA_Head() .. ": no " .. noun .. ". " .. SRKey( "Escape" ) .. " to cancel", true );
		return;
	end
	m_srList.Open( "", nil, true );
	local index:number = 1;
	for i, item in ipairs( items ) do
		if item.key == m_srList.GetFocusKey() then index = i; end
	end
	SRA_Say( SRA_Head() .. ": " .. SRA_Plural( #items, single, noun ) .. ". " .. items[ index ].text .. ", " .. index .. " of " .. #items, true );
end

-- ---- questions (Enter on an item) ------------------------------------------------------------

local function SRA_SpyIsInCity( city:table )
	if m_spy == nil then return false; end
	local spyCity:table = Cities.GetPlotPurchaseCity( Map.GetPlot( m_spy:GetX(), m_spy:GetY() ) );
	return spyCity ~= nil and spyCity:GetOwner() == city:GetOwner() and spyCity:GetID() == city:GetID();
end

local function SRA_AskTravel()
	local pending:table = m_srConfirm;
	local city:table = CityManager.GetCity( pending.owner, pending.id );
	if city == nil then return; end
	if pending.counter then
		SRA_Say( SRA_CityName( city ) .. " is your city where " .. SRA_SpyName() .. " is. " .. SRKey( "Enter" ) .. " to choose a counterspy mission, " .. SRKey( "Escape" ) .. " to go back" );
		return;
	end
	local travel:number, establish:number = SRA_TravelTimes( city );
	local missions:number = #SRA_MissionItems();
	SRA_Say( "Send " .. SRA_SpyName() .. " to " .. SRA_CityName( city ) .. "? Arrives in " .. SRA_Plural( travel + establish, "turn", "turns" )
		.. ". " .. SRA_Plural( missions, "mission", "missions" ) .. " possible there, " .. SRKey( "Space" ) .. " lists them. " .. SRKey( "Enter" ) .. " to confirm, " .. SRKey( "Escape" ) .. " to go back" );
end

local function SRA_AskMission()
	local pending:table = m_srConfirm;
	local data:table = SRA_MissionData( pending.entry );
	if data == nil then return; end
	SRA_Say( "Start " .. EspionageText_Mission{ name = data.name, district = data.district, chance = data.chance, turns = data.turns }
		.. " in " .. SRA_CityName( m_city ) .. "? " .. SRKey( "Enter" ) .. " to confirm, " .. SRKey( "Escape" ) .. " to go back, " .. SRKey( "Space" ) .. " for details" );
end

local function SRA_SelectDestination( item:table )
	local city:table = CityManager.GetCity( item.owner, item.id );
	if city == nil then SRA_Say( "That city is no longer available" ); return; end
	OnSelectDestination( city );		-- the game: remember the city, look at it, show its missions
	local counter:boolean = ( city:GetOwner() == Game.GetLocalPlayer() ) and SRA_SpyIsInCity( city );
	m_srConfirm = { kind = "travel", owner = item.owner, id = item.id, key = item.key, counter = counter };
	SRA_AskTravel();
end

local function SRA_SelectMission( item:table )
	m_srConfirm = { kind = "mission", entry = item.entry, key = item.key };
	SRA_AskMission();
end

local function SRA_ConfirmTravel()
	local pending:table = m_srConfirm;
	local city:table = CityManager.GetCity( pending.owner, pending.id );
	if city == nil or m_city == nil or m_spy == nil then
		m_srConfirm = nil;
		SRA_Say( "That city is no longer available" );
		return;
	end
	if pending.counter then
		m_srConfirm = nil;
		OnConfirmPlacement();		-- own city with the spy in it: the game switches to the mission chooser
		m_srList.Reset();
		SRA_AnnounceList();
		return;
	end
	local plot:table = Map.GetPlot( city:GetX(), city:GetY() );
	local params:table = {};
	params[ UnitOperationTypes.PARAM_X ] = city:GetX();
	params[ UnitOperationTypes.PARAM_Y ] = city:GetY();
	if not UnitManager.CanStartOperation( m_spy, UnitOperationTypes.SPY_TRAVEL_NEW_CITY, plot, params ) then
		SRA_Say( "Can't send " .. SRA_SpyName() .. " to " .. SRA_CityName( city ) .. ". " .. SRKey( "Escape" ) .. " to go back" );
		return;
	end
	local travel:number, establish:number = SRA_TravelTimes( city );
	local spyName:string, cityName:string = SRA_SpyName(), SRA_CityName( city );
	m_srConfirm = nil;
	OnConfirmPlacement();		-- the game: TeleportToSelectedCity, which requests the operation and leaves the chooser mode
	SRA_Say( spyName .. " travels to " .. cityName .. ", arrives in " .. SRA_Plural( travel + establish, "turn", "turns" ) );
end

local function SRA_ConfirmMission()
	local pending:table = m_srConfirm;
	local entry:table = pending.entry;
	local data:table = SRA_MissionData( entry );
	if data == nil or data.reason ~= nil or m_spy == nil or m_city == nil then
		m_srConfirm = nil;
		SRA_Say( "That mission is no longer available. Back to the list" );
		return;
	end
	local text:string = data.name .. ( data.district ~= nil and ( ", " .. data.district ) or "" ) .. " in " .. SRA_CityName( m_city );
	local turns:number = data.turns;
	m_srConfirm = nil;
	if entry.counter then
		OnCounterspySelected( SRA_MissionPlot( entry ) );
	else
		UnitManager.RequestOperation( m_spy, data.operation.Hash );		-- what the mission briefing's Accept button does
		UI.PlaySound( "UI_Spy_Mission_Accepted" );
	end
	SRA_Say( "Mission started: " .. text .. ( turns ~= nil and ( ", " .. SRA_Plural( turns, "turn", "turns" ) ) or "" ) );
end

local function SRA_Back()
	local pending:table = m_srConfirm;
	m_srConfirm = nil;
	if pending.kind == "travel" then OnCancel(); end		-- the game: forget the chosen city, back to the destination list
	m_srList.Focus( pending.key, "Back to the list" );
end

local function SRA_ReadConfirmDetail()
	local pending:table = m_srConfirm;
	if pending.kind == "mission" then
		local data:table = SRA_MissionData( pending.entry );
		SRA_Say( data ~= nil and SRA_MissionDetail( pending.entry, data ) or "No further details" );
		return;
	end
	local lines:table = {};
	for _, item in ipairs( SRA_MissionItems() ) do table.insert( lines, item.text ); end
	if #lines == 0 then SRA_Say( "No missions possible there" ); return; end
	SRA_Say( table.concat( lines, ". " ) );
end

local function SRA_Cancel()
	if m_currentChooserMode == EspionageChooserModes.DESTINATION_CHOOSER and m_city ~= nil then
		-- a mission list reached from the destination list (counterspy in an own city): Escape goes back one level
		OnCancel();
		m_srList.Reset();
		SRA_Say( "Back to destinations" );
		SRA_AnnounceList();
		return;
	end
	OnClose();
	SRA_Say( "Cancelled" );
end

local function SRA_OnActivate( item:table )
	if SRA_IsDestinationList() then SRA_SelectDestination( item ); else SRA_SelectMission( item ); end
end

function SRA_CreateList()
	m_srList = KeyNavList_Create{
		build = SRA_BuildItems,
		isActive = function() return m_AnimSupport ~= nil and m_AnimSupport.IsVisible() and m_srConfirm == nil; end,
		onActivate = SRA_OnActivate,
		onClose = SRA_Cancel,
	};
end

-- Called at the end of Open(): the game has just (re)built its lists; announce a moment later.
function SRA_ArmOpen()
	m_srConfirm = nil;
	m_srList.Reset();
	m_srOpenPending = true;
	m_srOpenDelay = SRA_OPEN_DELAY;
end

function SRA_ClearConfirm()
	m_srConfirm = nil;
end

function SRA_OnUpdate( deltaTime:number )
	if not m_srOpenPending then return; end
	if ContextPtr:IsHidden() or not m_AnimSupport.IsVisible() then m_srOpenPending = false; return; end
	m_srOpenDelay = m_srOpenDelay - deltaTime;
	if m_srOpenDelay > 0 then return; end
	m_srOpenPending = false;
	local ok:boolean, err = xpcall( SRA_AnnounceList, KeyNavErrorHandler );
	if not ok then print( "EspionageChooser announce error: " .. tostring( err ) ); end
end

function SRA_HandleInput( input:table )
	if m_AnimSupport == nil or not m_AnimSupport.IsVisible() then return false; end
	local msg:number = input:GetMessageType();
	if msg ~= KeyEvents.KeyDown and msg ~= KeyEvents.KeyUp then return false; end
	if m_srConfirm ~= nil then
		if msg == KeyEvents.KeyUp then
			local key:number = input:GetKey();
			local action = nil;
			if key == Keys.VK_RETURN then action = ( m_srConfirm.kind == "travel" ) and SRA_ConfirmTravel or SRA_ConfirmMission;
			elseif key == Keys.VK_ESCAPE then action = SRA_Back;
			elseif key == Keys.VK_SPACE then action = SRA_ReadConfirmDetail;
			elseif key == Keys.VK_UP or key == Keys.VK_DOWN then action = ( m_srConfirm.kind == "travel" ) and SRA_AskTravel or SRA_AskMission;		-- nothing to move to: repeat the question
			end
			if action ~= nil then
				local ok:boolean, err = xpcall( action, KeyNavErrorHandler );
				if not ok then print( "EspionageChooser error: " .. tostring( err ) ); end
			end
		end
		return true;
	end
	m_srList.HandleInput( input );
	return true;		-- everything else is swallowed while the chooser is shown
end

function SRA_InputHandler( input:table )
	if SRA_HandleInput( input ) then return true; end
	return m_AnimSupport.OnInputHandler( input );
end
print( "ScreenReaderAccess: EspionageChooser copy loaded" );

-- ===========================================================================
--	INIT
-- ===========================================================================
function Initialize()
	-- Lua Events
	SRListen( LuaEvents.EspionagePopup_MissionBriefingClosed, OnMissionBriefingClosed );		-- ScreenReaderAccess

	-- Control Events
	Controls.ConfirmButton:RegisterCallback( Mouse.eLClick, OnConfirmPlacement );
	Controls.ConfirmButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	Controls.CancelButton:RegisterCallback( Mouse.eLClick, OnCancel );
	Controls.CancelButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	Controls.CloseButton:RegisterCallback( Mouse.eLClick, OnClose );
	Controls.CloseButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);

	-- Game Engine Events	
	SRListen( Events.InterfaceModeChanged, OnInterfaceModeChanged );		-- ScreenReaderAccess
	SRListen( Events.UnitSelectionChanged, OnUnitSelectionChanged );		-- ScreenReaderAccess
	SRListen( Events.UnitActivityChanged, OnUnitActivityChanged );		-- ScreenReaderAccess
	SRListen( Events.LocalPlayerTurnEnd, OnLocalPlayerTurnEnd );		-- ScreenReaderAccess

	-- Animation controller
	m_AnimSupport = CreateScreenAnimation(Controls.SlideAnim);

	-- Animation controller events
	SRListen( Events.SystemUpdateUI, m_AnimSupport.OnUpdateUI );		-- ScreenReaderAccess
	ContextPtr:SetInputHandler(SRA_InputHandler, true);		-- ScreenReaderAccess (was m_AnimSupport.OnInputHandler)
	ContextPtr:SetUpdate(SRA_OnUpdate);		-- ScreenReaderAccess
	SRA_CreateList();		-- ScreenReaderAccess

	-- Hot-Reload Events
	ContextPtr:SetInitHandler(OnInit);
	ContextPtr:SetShutdown(OnShutdown);
	SRListen( LuaEvents.GameDebug_Return, OnGameDebugReturn );		-- ScreenReaderAccess
end
Initialize();
