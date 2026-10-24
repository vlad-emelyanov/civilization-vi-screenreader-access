-- Copyright 2017-2020, Firaxis Games
-- UI for managing and appointing Governors	

include("InstanceManager");
include("GameCapabilities"); 
include("TabSupport");
include("SupportFunctions");
include("Civ6Common");
include("ModalScreen_PlayerYieldsHelper");
include("GovernorSupport");
include("ScreenReader");	-- ScreenReaderAccess
include("KeyNavList");		-- ScreenReaderAccess

-- ===========================================================================
--	CONSTANTS
-- ===========================================================================
local RELOAD_CACHE_ID:string = "GovernorPanel"; -- Must be unique (usually the same as the file name)

m_GovernorApptAvailableHash = DB.MakeHash("NOTIFICATION_GOVERNOR_APPOINTMENT_AVAILABLE");
m_GovernorOpportunityAvailableHash = DB.MakeHash("NOTIFICATION_GOVERNOR_OPPORTUNITY_AVAILABLE");
m_GovernorPromotionAvailableHash = DB.MakeHash("NOTIFICATION_GOVERNOR_PROMOTION_AVAILABLE");
m_GovernorIdleHash = DB.MakeHash("NOTIFICATION_GOVERNOR_IDLE");
m_SecretSocietyLevelUpHash = DB.MakeHash("NOTIFICATION_SECRETSOCIETY_LEVEL_UP");

local PANEL_MAX_WIDTH = 1890;
local m_TopPanelConsideredHeight:number = 0;

-- ===========================================================================
--	VARIABLES
-- ===========================================================================
local m_governorIM			:table = InstanceManager:new("GovernorInstance",	"Content",	Controls.GovernorInstanceStack);
local m_societyGovernorIM	:table = InstanceManager:new("SocietyGovernorInstance",	"Content",	Controls.GovernorInstanceStack);
local m_governorPromotionIM :table = InstanceManager:new("PromotionInstance",	"Button");
local m_TopPanelConsideredHeight:number = 0;

-- Player ID and City ID sent by City Banner to be used to auto select a city when opening the assignment chooser
local m_CityBannerPlayerID:number = -1;
local m_CityBannerCityID:number = -1;

local m_srList			:table = nil;		-- ScreenReaderAccess: governor list
local m_srActions		:table = nil;		-- ScreenReaderAccess: actions of one governor
local m_srActionGov		:number = -1;		-- ScreenReaderAccess: governor index whose actions are open (-1 = governor list)
local m_srOpenPending	:boolean = false;	-- ScreenReaderAccess
local m_srOpenDelay		:number = 0;		-- ScreenReaderAccess
local m_srAppointWait	:number = nil;		-- ScreenReaderAccess: seconds until "the appointment did not happen" is said
local m_srAppointHash	:number = nil;		-- ScreenReaderAccess: governor hash the appointment waits for

-- ===========================================================================
function Refresh()

	local pPlayer = Players[Game.GetLocalPlayer()];
	if (pPlayer == nil) then
		return;
	end
		
	m_governorPromotionIM:ResetInstances();

	--
	-- display a list of governor candidates
	--
	m_governorIM:ResetInstances();
	m_societyGovernorIM:ResetInstances();

	local playerGovernors = pPlayer:GetGovernors();
	local governorPointsObtained = playerGovernors:GetGovernorPoints();
	local governorPointsSpent = playerGovernors:GetGovernorPointsSpent();
	local bCanAppoint = playerGovernors:CanAppoint();
	local bHasGovernors, tGovernorList = playerGovernors:GetGovernorList();

	Controls.GovernorTitlesAvailable:SetText(Locale.Lookup("LOC_GOVERNOR_GOVERNOR_TITLES_AVAILABLE", governorPointsObtained - governorPointsSpent));
	Controls.GovernorTitlesSpent:SetText(Locale.Lookup("LOC_GOVERNOR_GOVERNOR_TITLES_SPENT", governorPointsSpent));

	-- Add all secret societies (discovered or joined) before adding governors
	for _, pAppointedGovernor:table in ipairs(tGovernorList) do
		local eGovernorType:number = pAppointedGovernor:GetType();
		local kGovernorDef:table = GameInfo.Governors[eGovernorType];
		local bCanPromoteGovernor:boolean = playerGovernors:CanPromoteGovernor(kGovernorDef.Hash);
		if (IsCannotAssign(kGovernorDef)) then
			AddSecretGovernorAppointed(playerGovernors, pAppointedGovernor, kGovernorDef, bCanPromoteGovernor);
		end
	end

	for kGovernorDef:table in GameInfo.Governors() do
		local governorHash:number = kGovernorDef.Hash;
		if (not playerGovernors:HasGovernor(governorHash)) then
			if (playerGovernors:CanEverAppointGovernor(governorHash)) then
				if (IsCannotAssign(kGovernorDef)) then
					AddSecretGovernorCandidate(kGovernorDef, bCanAppoint);
				end
			end
		end
	end

	-- Add apointed governors
	for i, pAppointedGovernor:table in ipairs(tGovernorList) do
		local eGovernorType:number = pAppointedGovernor:GetType();
		local kGovernorDef:table = GameInfo.Governors[eGovernorType];
		local bCanPromoteGovernor:boolean = playerGovernors:CanPromoteGovernor(kGovernorDef.Hash);

		-- Check that we're not adding secret societies again
		if (not IsCannotAssign(kGovernorDef)) then
			AddGovernorAppointed(playerGovernors, pAppointedGovernor, kGovernorDef, bCanPromoteGovernor);
		end
	end

	-- Add appointable governors
	for kGovernorDef in GameInfo.Governors() do
		local governorHash:number = kGovernorDef.Hash;
		if (not playerGovernors:HasGovernor(governorHash)) then
			if (playerGovernors:CanEverAppointGovernor(governorHash)) then

				-- Check that we're not adding secret societies again
				if (not IsCannotAssign(kGovernorDef)) then
					AddGovernorCandidate(kGovernorDef, bCanAppoint);
				end
			end
		end
	end

	Controls.GovernorInstanceStack:CalculateSize();
	Controls.GovernorInstanceScrollPanel:CalculateSize();

	if Controls.GovernorPanelContainer:GetSizeX() > PANEL_MAX_WIDTH then
		Controls.GovernorPanelContainer:SetSizeX(PANEL_MAX_WIDTH);
	end

	-- From ModalScreen_PlayerYieldsHelper
	if not RefreshYields() then
		Controls.Vignette:SetSizeY(m_TopPanelConsideredHeight);
	end
end

-- ===========================================================================
function AddGovernorShared(governor:table)

	local pLocalPlayer = Players[Game.GetLocalPlayer()];
	local pPlayerGovernors = pLocalPlayer:GetGovernors();
	local turnsToEstablish = pPlayerGovernors:GetTurnsToEstablish(governor.Hash);

	governorInstance = m_governorIM:GetInstance();

	-- Update name, title, and portrait
	governorInstance.GovernorName:SetText(Locale.ToUpper(governor.Name));
	governorInstance.GovernorTitle:SetText(Locale.Lookup(governor.Title));
	governorInstance.GovernorPortrait:SetTexture(governor.PortraitImage);

	-- Update transition strength
	governorInstance.TransitionStrengthLabel:SetText(turnsToEstablish);

	-- Update identity pressure
	governorInstance.IdentityPressureLabel:SetText(governor.IdentityPressure);

	-- Return the governor instance
	return governorInstance;
end

-- ===========================================================================
function AddPromotionInstance( governorInstance:table, governorDefinition:table, promotion:table, hasPromotion:boolean )

	local promotionInstance = {};
	if hasPromotion then
		promotionInstance = m_governorPromotionIM:GetInstance(governorInstance.EarnedPromotionsStack);
	else
		promotionInstance = m_governorPromotionIM:GetInstance(governorInstance.AvailablePromotionsStack);
	end

	local hasModifier = false;
	for row in GameInfo.GovernorPromotionModifiers() do
		if(row.GovernorPromotionType == promotion.GovernorPromotionType) then
			hasModifier = true;
			break;
		end
	end

	local sDescription = "";
	if (not hasModifier) then
		sDescription = sDescription .. "<NOT IMPLEMENTED>";
	end
	local sName:string = Locale.Lookup(promotion.Name);
	sDescription = sName .. ": " .. sDescription .. Locale.Lookup(promotion.Description);
	if (IsPromotionHidden(promotion.Hash, Game.GetLocalPlayer(), governorDefinition.Index)) then
		sName = GetPromotionHiddenName(promotion.Hash);
		sDescription = GetPromotionHiddenDescription(promotion.Hash);
	end

	promotionInstance.PromotionName:SetText(sName);
	promotionInstance.Button:SetToolTipString(sDescription);
	promotionInstance.Button:SetDisabled(true);

	-- If this is our base ability use our governor specific promotion icon
	local iconName:string = "ICON_" .. governorDefinition.GovernorType .. "_PROMOTION";
	if not promotion.BaseAbility or not promotionInstance.PromotionIcon:SetIcon(iconName) then
		-- Fallback icon
		promotionInstance.PromotionIcon:SetIcon("ICON_GOVERNOR_GENERIC_PROMOTION");
	end

	-- Indicate if we have this promotion using vis states
	if hasPromotion then
		promotionInstance.Button:SetAlpha(1.0);
	else
		promotionInstance.Button:SetAlpha(0.5);
	end

	return promotionInstance;
end

-- ===========================================================================
function AddGovernorCandidate(governorDef:table, canAppoint:boolean)

	local governorInstance:table = AddGovernorShared(governorDef);

	-- Add all promotions this governor has
	for promotion in GameInfo.GovernorPromotionSets() do
		if promotion.GovernorType == governorDef.GovernorType then
			local promotionDef = GameInfo.GovernorPromotions[promotion.GovernorPromotion];
			AddPromotionInstance(governorInstance, governorDef, promotionDef, promotion.BaseAbility);
		end
	end

	-- Always use unassigned column/background for governor candidates
	governorInstance.Content:SetTexture("Governors_BackgroundTile_ColumnOff");
	governorInstance.GovernorColumns:SetTexture("Governors_Column_Off");

	governorInstance.AssignButton:SetHide(true);
	governorInstance.AppointButton:SetHide(false);

	if (canAppoint and not IsReadOnly()) then
		governorInstance.AppointButton:SetVoid1( governorDef.Index );
		governorInstance.AppointButton:RegisterCallback( Mouse.eLClick, OnAppointGovernor );
		governorInstance.AppointButton:SetDisabled(false);
		governorInstance.AppointButton:SetToolTipString("");
	else
		governorInstance.AppointButton:SetDisabled(true);
		if(IsReadOnly()) then
			governorInstance.AppointButton:SetToolTipString(Locale.Lookup(""));
		else
			governorInstance.AppointButton:SetToolTipString(Locale.Lookup("LOC_NO_GOVERNORS_TITLE_AVAILABLE"));
		end
	end

	SetGovernorStatus(governorInstance, governorDef);

	-- Setup details button
	governorInstance.GovernorDetailsButton:SetVoid1(governorDef.Index);
	governorInstance.GovernorDetailsButton:RegisterCallback(Mouse.eLClick, OnNameButton);
	governorInstance.GovernorDetailsButton:SetText(Locale.Lookup("LOC_GOVERNORS_SCREEN_VIEW_PROMOTIONS"));
	SetButtonTexture(governorInstance.GovernorDetailsButton, "Controls_Button");

	governorInstance.GovernorNeutralizedIndicator:SetHide(true);
	governorInstance.FadeOutOverlay:SetHide(false);
end

-- ===========================================================================
function AddSecretGovernorShared(governor:table)

	governorInstance = m_societyGovernorIM:GetInstance();

	-- Update name, title, and portrait
	governorInstance.GovernorName:SetText(Locale.ToUpper(governor.Name));
	governorInstance.GovernorTitle:SetText(Locale.Lookup(governor.Title));
	governorInstance.GovernorPortrait:SetTexture(governor.PortraitImage);

	-- Find the secret society for this governor to grab the society icon
	local kSecretSocietyDef:table = nil;
	for i, societyDef in ipairs(governor.SecretSocietyCollection) do
		if societyDef ~= nil then
			kSecretSocietyDef = societyDef;
			break;
		end
	end

	if kSecretSocietyDef then
		governorInstance.SocietyIcon:SetTexture(kSecretSocietyDef.SmallIcon);
	end

	-- Return the governor instance
	return governorInstance;
end

-- ===========================================================================
function AddSecretGovernorCandidate(governorDef:table, canAppoint:boolean)
	
	local governorInstance:table = AddSecretGovernorShared(governorDef);

	-- Add all promotions this governor has
	for promotion in GameInfo.GovernorPromotionSets() do
		if promotion.GovernorType == governorDef.GovernorType then
			local promotionDef = GameInfo.GovernorPromotions[promotion.GovernorPromotion];
			local pPromotionInst:table = AddPromotionInstance(governorInstance, governorDef, promotionDef, promotion.BaseAbility);
			pPromotionInst.Button:SetTexture("Secret_DataFrame");
		end
	end

	-- Always use unassigned column/background for governor candidates
	governorInstance.GovernorColumns:SetTexture("Governors_Column_Off");

	governorInstance.AppointButton:SetHide(false);

	if (canAppoint and not IsReadOnly()) then
		governorInstance.AppointButton:SetVoid1( governorDef.Index );
		governorInstance.AppointButton:RegisterCallback( Mouse.eLClick, OnAppointGovernor );
		governorInstance.AppointButton:SetDisabled(false);
		governorInstance.AppointButton:SetToolTipString("");
	else
		governorInstance.AppointButton:SetDisabled(true);
		if(IsReadOnly()) then
			governorInstance.AppointButton:SetToolTipString(Locale.Lookup(""));
		else
			governorInstance.AppointButton:SetToolTipString(Locale.Lookup("LOC_NO_GOVERNORS_TITLE_AVAILABLE"));
		end
	end

	-- Setup details button
	governorInstance.GovernorDetailsButton:SetVoid1(governorDef.Index);
	governorInstance.GovernorDetailsButton:RegisterCallback(Mouse.eLClick, OnNameButton);
	governorInstance.GovernorDetailsButton:SetText(Locale.Lookup("LOC_GOVERNORS_SCREEN_VIEW_PROMOTIONS"));
	SetButtonTexture(governorInstance.GovernorDetailsButton, "Controls_Button");

	governorInstance.FadeOutOverlay:SetHide(false);
end

-- ===========================================================================
function AddSecretGovernorAppointed(playerGovernors:table, governor:table, governorDefinition:table, canPromote:boolean)

	local governorInstance:table = AddSecretGovernorShared(governorDefinition);

	-- Add all promotions this governor has
	local hasAllPromotions:boolean = true;
	for promotion in GameInfo.GovernorPromotionSets() do
		if promotion.GovernorType == governorDefinition.GovernorType then
			local promotionDef = GameInfo.GovernorPromotions[promotion.GovernorPromotion];
			local hasPromotion:boolean = governor:HasPromotion(DB.MakeHash(promotion.GovernorPromotion));
			local pPromotionInst:table = AddPromotionInstance(governorInstance, governorDefinition, promotionDef, hasPromotion);
			pPromotionInst.Button:SetTexture("Secret_DataFrame");

			if not hasPromotion then
				hasAllPromotions = false;
			end
		end
	end

	governorInstance.AppointButton:SetHide(true);

	governorInstance.GovernorColumns:SetTexture("Governors_Column_On");

	-- Setup button to open governor details
	if canPromote and not hasAllPromotions then
		SetButtonTexture(governorInstance.GovernorDetailsButton, "Controls_Confirm");
		governorInstance.GovernorDetailsButton:SetText(Locale.Lookup("LOC_GOVERNORS_SCREEN_PROMOTE"));
	else
		SetButtonTexture(governorInstance.GovernorDetailsButton, "Controls_Button");
		governorInstance.GovernorDetailsButton:SetText(Locale.Lookup("LOC_GOVERNORS_SCREEN_VIEW_PROMOTIONS"));
	end

	governorInstance.GovernorDetailsButton:SetVoid1(governorDefinition.Index);
	governorInstance.GovernorDetailsButton:RegisterCallback(Mouse.eLClick, OnNameButton);

	governorInstance.FadeOutOverlay:SetHide(true);
end

-- ===========================================================================
function SetGovernorStatus(governorInstance:table, governorDef:table, governor:table)
	local status, statusDetails = GetGovernorStatus(governorDef, governor);
	governorInstance.GovernorStatus:SetText(status);
	governorInstance.GovernorStatusDetails:SetText(statusDetails);
end

-- ===========================================================================
function AddGovernorAppointed(playerGovernors:table, governor:table, governorDefinition:table, canPromote:boolean)

	local governorInstance:table = AddGovernorShared(governorDefinition);

	-- Add all promotions this governor has
	local hasAllPromotions:boolean = true;
	for promotion in GameInfo.GovernorPromotionSets() do
		if promotion.GovernorType == governorDefinition.GovernorType then
			local promotionDef = GameInfo.GovernorPromotions[promotion.GovernorPromotion];
			local hasPromotion:boolean = governor:HasPromotion(DB.MakeHash(promotion.GovernorPromotion));
			AddPromotionInstance(governorInstance, governorDefinition, promotionDef, hasPromotion);

			if not hasPromotion then
				hasAllPromotions = false;
			end
		end
	end

	governorInstance.AssignButton:SetHide(IsCannotAssign(governorDefinition));
	governorInstance.AppointButton:SetHide(true);

	-- Update assignment button
	governorInstance.AssignButton:SetDisabled(false);
	governorInstance.AssignButton:RegisterCallback(Mouse.eLClick, function() OnAssignButton(governorDefinition.Index, m_CityBannerPlayerID, m_CityBannerCityID); end);

	SetGovernorStatus(governorInstance, governorDefinition, governor);

	local pAssignedCity:table = governor:GetAssignedCity();
	if pAssignedCity then
		SetButtonTexture(governorInstance.AssignButton, "Controls_Button");
		governorInstance.AssignButton:SetText(Locale.Lookup("LOC_GOVERNORS_SCREEN_BUTTON_REASSIGN_GOVERNOR"));

		governorInstance.Content:SetTexture("Governors_BackgroundTile_ColumnOn");
		governorInstance.GovernorColumns:SetTexture("Governors_Column_On");
	else
		governorInstance.AssignButton:SetText(Locale.Lookup("LOC_GOVERNORS_SCREEN_BUTTON_ASSIGN_GOVERNOR"));

		-- If we have cities without any governors highlight the Assign buttons
		if AnyCitiesWithoutAGovernor() then
			SetButtonTexture(governorInstance.AssignButton, "Controls_Confirm");
		else
			SetButtonTexture(governorInstance.AssignButton, "Controls_Button");
		end

		governorInstance.Content:SetTexture("Governors_BackgroundTile_ColumnOff");
		governorInstance.GovernorColumns:SetTexture("Governors_Column_Off");
	end

	-- Setup button to open governor details
	if canPromote and not hasAllPromotions then
		SetButtonTexture(governorInstance.GovernorDetailsButton, "Controls_Confirm");
		governorInstance.GovernorDetailsButton:SetText(Locale.Lookup("LOC_GOVERNORS_SCREEN_PROMOTE"));
	else
		SetButtonTexture(governorInstance.GovernorDetailsButton, "Controls_Button");
		governorInstance.GovernorDetailsButton:SetText(Locale.Lookup("LOC_GOVERNORS_SCREEN_VIEW_PROMOTIONS"));
	end
	governorInstance.GovernorDetailsButton:SetVoid1(governorDefinition.Index);
	governorInstance.GovernorDetailsButton:RegisterCallback(Mouse.eLClick, OnNameButton);

	local numOfNeutralizedTurns:number = governor:GetNeutralizedTurns();
	if (numOfNeutralizedTurns > 0 or IsReadOnly()) then
		governorInstance.AssignButton:SetDisabled(true);
		if (numOfNeutralizedTurns > 0) then
			governorInstance.GovernorNeutralizedIndicator:SetHide(false);
			governorInstance.FadeOutOverlay:SetHide(false);
		else
			governorInstance.GovernorNeutralizedIndicator:SetHide(true);
			governorInstance.FadeOutOverlay:SetHide(true);
		end
	else
		governorInstance.AssignButton:SetDisabled(false);
		governorInstance.GovernorNeutralizedIndicator:SetHide(true);
		governorInstance.FadeOutOverlay:SetHide(true);
	end
end

-- ===========================================================================
function AnyCitiesWithoutAGovernor()
	local pLocalPlayerCities:table = Players[Game.GetLocalPlayer()]:GetCities();
	for i,pCity in pLocalPlayerCities:Members() do
		if pCity:GetAssignedGovernor() == nil then
			return true;
		end
	end

	return false;
end

-- ===========================================================================
function OnNameButton( governorIndex:number )
	LuaEvents.GovernorDetailsPanel_OpenDetails( governorIndex, IsReadOnly(), m_CityBannerPlayerID, m_CityBannerCityID );
	Controls.DetailsPanel:SetHide(false);
end

-- ===========================================================================
function OnAssignButton( governorIndex:number, playerID:number, cityID:number )
	LuaEvents.GovernorAssignmentChooser_RequestAssignment( governorIndex, playerID, cityID );
	Close();
end

-- ===========================================================================
-- The player explicitedly requested that the screen to close. This marks that the player has considered their governor title options and then closes the screen.
function PlayerRequestClose()
	local localPlayerID = Game.GetLocalPlayer();
	if (localPlayerID ~= -1) then
		local localPlayer = Players[localPlayerID];
		if (localPlayer ~= nil and localPlayer:GetGovernors() ~= nil and not localPlayer:GetGovernors():HasTitleBeenConsidered()) then
			localPlayer:GetGovernors():SetTitleConsidered(true);
		end
	end

	Close();
end

-- ===========================================================================
-- Close the Screen. This can happen from the player explicitedly closing the screen or an action that implicitedly closes the screen.
-- As such, do not mark the player as having considered their governor title options.
function Close()
	m_srOpenPending = false;		-- ScreenReaderAccess
	m_srAppointWait = nil;		-- ScreenReaderAccess
	if Controls.DetailsPanel:IsVisible() then
		Controls.DetailsPanel:SetHide(true);
	end

	if UIManager:DequeuePopup(ContextPtr) then
		UI.PlaySound("UI_Screen_Close");
		LuaEvents.GovernorPanel_Closed();
	end
end

-- ===========================================================================
function Open(playerID:number, cityID:number)
	-- playerID and cityID banner come from selecting a city banner
	-- in other situations they should be nil
	if playerID ~= nil and cityID ~= nil then
		m_CityBannerPlayerID = playerID;
		m_CityBannerCityID = cityID;
	else
		m_CityBannerPlayerID = -1;
		m_CityBannerCityID = -1;
	end

	Refresh();

	Controls.DetailsPanel:SetHide(true);
	if not UIManager:IsInPopupQueue(ContextPtr) then
		-- Queue the screen as a popup, but we want it to render at a desired location in the hierarchy, not on top of everything.
		local kParameters = {};
		kParameters.RenderAtCurrentParent = true;
		kParameters.InputAtCurrentParent = true;
		kParameters.AlwaysVisibleInQueue = true;
		UIManager:QueuePopup(ContextPtr, PopupPriority.Low, kParameters);
		UI.PlaySound("UI_Screen_Open");
	end

	LuaEvents.GovernorAssignmentChooser_Close();
	
	-- From Civ6_styles: FullScreenVignetteConsumer
	Controls.ScreenAnimIn:SetToBeginning();
	Controls.ScreenAnimIn:Play();
	
	LuaEvents.GovernorPanel_Opened();
	ContextPtr:ChangeParent(ContextPtr:LookUpControl("/InGame/Screens"));
	m_srActionGov = -1;			-- ScreenReaderAccess
	m_srOpenPending = true;		-- ScreenReaderAccess: announced from the update loop (Open is often called twice)
	m_srOpenDelay = 0.5;		-- ScreenReaderAccess: lets a pending assignment settle first
end

-- ===========================================================================
function OnGovernorAppointed(playerID, governorID)
	if ContextPtr:IsVisible() and playerID == Game.GetLocalPlayer() then
		Refresh();
		local governorDefinition:table = GameInfo.Governors[governorID];
		if governorDefinition ~= nil then OutputMessageToScreenReader( Locale.Lookup(governorDefinition.Name) .. " appointed" ); end		-- ScreenReaderAccess
		m_srAppointWait = nil;		-- ScreenReaderAccess
		if (governorDefinition ~= nil and not IsCannotAssign(governorDefinition)) then
			local pPlayer:object = Players[playerID];
			if (pPlayer == nil) then
				return;
			end
			local playerGovernors:object = pPlayer:GetGovernors();
			if (playerGovernors == nil) then
				return;
			end
			local appointedGovernor:object = playerGovernors:GetGovernor(governorDefinition.Hash);
			if (appointedGovernor ~= nil and appointedGovernor:GetNeutralizedTurns() > 0) then
				return;
			end
			LuaEvents.GovernorAssignmentChooser_RequestAssignment( governorID );
			Close();
		end
	end
end

-- ===========================================================================
function OnAppointGovernor(eGovernor:number)
	local pLocalPlayer = Players[Game.GetLocalPlayer()];
	if (pLocalPlayer ~= nil) then
		local kParameters:table = {};
		kParameters[PlayerOperations.PARAM_GOVERNOR_TYPE] = eGovernor;
		UI.RequestPlayerOperation(Game.GetLocalPlayer(), PlayerOperations.APPOINT_GOVERNOR, kParameters);

		Refresh();
	end
end

-- ===========================================================================
function OnAssignToCity(eGovernor:number, cityID:number)
	local pLocalPlayer = Players[Game.GetLocalPlayer()];
	if (pLocalPlayer ~= nil) then
		local kParameters:table = {};
		kParameters[PlayerOperations.PARAM_GOVERNOR_TYPE] = eGovernor;
		kParameters[PlayerOperations.PARAM_CITY_DEST] = cityID;
		UI.RequestPlayerOperation(Game.GetLocalPlayer(), PlayerOperations.ASSIGN_GOVERNOR, kParameters);
	end
end

-- ===========================================================================
function OnPromoteGovernor(eGovernor:number, ePromotion:number)
	local pLocalPlayer = Players[Game.GetLocalPlayer()];
	if (pLocalPlayer ~= nil) then
		local kParameters:table = {};
		kParameters[PlayerOperations.PARAM_GOVERNOR_TYPE] = eGovernor;
		kParameters[PlayerOperations.PARAM_GOVERNOR_PROMOTION_TYPE] = ePromotion;
		UI.RequestPlayerOperation(Game.GetLocalPlayer(), PlayerOperations.PROMOTE_GOVERNOR, kParameters);
	end
end


-- ===========================================================================
function OnToggleGovernorPanel(playerID:number, cityID:number)
	if ContextPtr:IsHidden() then
		Open(playerID, cityID);
	else
		Close();
	end
end

-- ===========================================================================
function OnProcessNotification(playerID:number, notificationID:number, activatedByUser:boolean)
	if playerID == Game.GetLocalPlayer() then -- Was it for us?
		local pNotification = NotificationManager.Find(playerID, notificationID);
		if (pNotification) then
			if (pNotification:GetType() == m_GovernorApptAvailableHash or
				pNotification:GetType() == m_GovernorOpportunityAvailableHash or
				pNotification:GetType() == m_GovernorPromotionAvailableHash or
				pNotification:GetType() == m_GovernorIdleHash or
				pNotification:GetType() == m_SecretSocietyLevelUpHash) then
				-- Open/refresh Governor Panel when we catch a governor notification
				Open();
			end
		end
	end
end

-- ===========================================================================
function OnProcessTurnBlocker( pNotification:table)
	if (pNotification ~= nil) then
		if (pNotification:GetPlayerID() ~= Game.GetLocalPlayer()) then
			return;
		end

		local notificationType = pNotification:GetType();

		if (pNotification:GetType() == m_GovernorApptAvailableHash or
			pNotification:GetType() == m_GovernorOpportunityAvailableHash or
			pNotification:GetType() == m_GovernorPromotionAvailableHash or
			pNotification:GetType() == m_GovernorIdleHash) then
			-- Open/refresh Governor Panel when we catch a governor notification
			Open();
		end
	end
end

-- ===========================================================================
--	UI Event
-- ===========================================================================
function OnInit( isReload:boolean )
	if isReload then		
		LuaEvents.GameDebug_GetValues( RELOAD_CACHE_ID );	
	end
end

-- =======================================================================================
--	UI Event
-- =======================================================================================
function OnShutdown()
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "isVisible", ContextPtr:IsVisible());
	SRA_RemoveListeners();		-- ScreenReaderAccess
end

-- ===========================================================================
--	LUA Event
--	Set cached values back after a hotload.
-- ===========================================================================s
function OnGameDebugReturn( context:string, contextTable:table )
	if context ~= RELOAD_CACHE_ID then
		return;
	end

	if contextTable["isVisible"] then
		ContextPtr:SetHide(not contextTable["isVisible"]);
	end

	Refresh();
end

-- ===========================================================================
--	ScreenReaderAccess: keyboard navigation and speech
--	Governor list (Up/Down/Home/End, Space = abilities, Enter = actions, Escape = close), then a small action list
--	for the focused governor. Everything is rebuilt from the game's state at key time.
-- ===========================================================================
local function SRA_Say( text:string, nointerrupt:boolean )
	OutputMessageToScreenReader( text, nointerrupt );
end

local function SRA_Clean( text:string )
	return CleanTextForSpeech( Locale.Lookup( text or "" ) );
end

local function SRA_TurnsText( turns:number )
	return turns .. ( turns == 1 and " turn" or " turns" );
end

-- ", established" / ", establishes in N turns" for an appointed governor in a city: one rule for every place that says it
-- (established = the game's flag or no turns left, remaining = the game's turns-to-establish minus the turns on site)
local function SRA_EstablishText( gov:table )
	local remaining:number = gov:GetTurnsToEstablish() - gov:GetTurnsOnSite();
	if gov:IsEstablished() or remaining <= 0 then return ", established"; end
	return ", establishes in " .. SRA_TurnsText( remaining );
end

-- Base ability and the promotions (with have / available / locked for an appointed governor).
local function SRA_GovernorDetail( def:table, governor:table, pg:table )
	local parts:table = {};
	for pass = 1, 2 do
		for set in GameInfo.GovernorPromotionSets() do
			if set.GovernorType == def.GovernorType then
				local promo:table = GameInfo.GovernorPromotions[ set.GovernorPromotion ];
				if ( pass == 1 ) == ( promo.BaseAbility == true ) then
					local name:string = SRA_Clean( promo.Name );
					local desc:string = SRA_Clean( promo.Description );
					if IsPromotionHidden( promo.Hash, Game.GetLocalPlayer(), def.Index ) then
						name = GetPromotionHiddenName( promo.Hash );
						desc = GetPromotionHiddenDescription( promo.Hash );
					end
					local line:string;
					if promo.BaseAbility then
						line = "Base ability: " .. desc;
					else
						line = name .. ": " .. desc;
						if governor ~= nil then
							if governor:HasPromotion( promo.Hash ) then
								line = line .. ", have";
							elseif pg:CanEarnPromotion( def.Hash, promo.Hash ) then
								line = line .. ", available";
							else
								line = line .. ", locked";
							end
						end
					end
					table.insert( parts, ( string.gsub( line, "[%.%s]+$", "" ) ) );
				end
			end
		end
	end
	return table.concat( parts, ". " );
end

-- Appointed governors first, then the candidates (secret society governors are left out).
function SRA_GovernorItems()
	local items:table = {};
	local pPlayer:table = Players[ Game.GetLocalPlayer() ];
	if pPlayer == nil then return items; end
	local pg:table = pPlayer:GetGovernors();
	if pg == nil then return items; end
	local canAppoint:boolean = pg:CanAppoint() and not IsReadOnly();
	local bHas, tList = pg:GetGovernorList();
	for _, gov in ipairs( tList or {} ) do
		local def:table = GameInfo.Governors[ gov:GetType() ];
		if def ~= nil and not IsCannotAssign( def ) then
			local text:string = SRA_Clean( def.Name ) .. ", " .. SRA_Clean( def.Title );
			local city:table = gov:GetAssignedCity();
			local neutral:number = gov:GetNeutralizedTurns();
			if neutral > 0 then
				text = text .. ", neutralized for " .. SRA_TurnsText( neutral );
			elseif city ~= nil then
				text = text .. ", in " .. SRA_Clean( city:GetName() );
				text = text .. SRA_EstablishText( gov );
			else
				text = text .. ", not assigned";
			end
			local hasAll:boolean = true;
			for set in GameInfo.GovernorPromotionSets() do
				if set.GovernorType == def.GovernorType and not gov:HasPromotion( GameInfo.GovernorPromotions[ set.GovernorPromotion ].Hash ) then
					hasAll = false;
				end
			end
			local canPromote:boolean = pg:CanPromoteGovernor( def.Hash ) and not hasAll and not IsReadOnly();
			if canPromote then text = text .. ", can promote"; end
			table.insert( items, { key = "gov:" .. def.Index, text = text, def = def, governor = gov, appointed = true, city = city,
				neutral = neutral > 0, canPromote = canPromote,
				detail = function() return SRA_Clean( def.Name ) .. ", " .. SRA_Clean( def.Title ) .. ". " .. SRA_GovernorDetail( def, gov, pg ); end } );
		end
	end
	for def in GameInfo.Governors() do
		if not pg:HasGovernor( def.Hash ) and pg:CanEverAppointGovernor( def.Hash ) and not IsCannotAssign( def ) then
			local text:string = SRA_Clean( def.Name ) .. ", " .. SRA_Clean( def.Title );
			if canAppoint then
				text = text .. ", can appoint";
			else
				text = text .. ", needs a governor title";
			end
			table.insert( items, { key = "gov:" .. def.Index, text = text, def = def, appointed = false, canAppoint = canAppoint,
				detail = function() return SRA_Clean( def.Name ) .. ", " .. SRA_Clean( def.Title ) .. ". " .. SRA_GovernorDetail( def, nil, pg ); end } );
		end
	end
	return items;
end

local function SRA_FindGovernorItem( index:number )
	for _, item in ipairs( SRA_GovernorItems() ) do
		if item.def.Index == index then return item; end
	end
	return nil;
end

local function SRA_ActionItems()
	local gi:table = SRA_FindGovernorItem( m_srActionGov );
	if gi == nil then return {}; end
	local section:string = "Actions for " .. SRA_Clean( gi.def.Name );
	local items:table = {};
	local function Add( key:string, text:string )
		table.insert( items, { key = key, text = text, section = section } );
	end
	if gi.appointed then
		if not gi.neutral and not IsReadOnly() then
			Add( "assign", SRA_Clean( gi.city ~= nil and "LOC_GOVERNORS_SCREEN_BUTTON_REASSIGN_GOVERNOR" or "LOC_GOVERNORS_SCREEN_BUTTON_ASSIGN_GOVERNOR" ) );
		end
	elseif gi.canAppoint then
		Add( "appoint", SRA_Clean( "LOC_GOVERNORS_SCREEN_BUTTON_APPOINT_GOVERNOR" ) );
	end
	if gi.canPromote then
		Add( "promote", SRA_Clean( "LOC_GOVERNORS_SCREEN_PROMOTE" ) );
	else
		Add( "promotions", SRA_Clean( "LOC_GOVERNORS_SCREEN_VIEW_PROMOTIONS" ) );
	end
	Add( "abilities", "Abilities" );
	return items;
end

local function SRA_OnActionActivate( item:table )
	local index:number = m_srActionGov;
	local gi:table = SRA_FindGovernorItem( index );
	if gi == nil then return; end
	if item.key == "abilities" then
		SRA_Say( gi.detail() );
	elseif item.key == "appoint" then
		m_srActionGov = -1;
		m_srAppointWait = 3;
		m_srAppointHash = gi.def.Hash;
		OnAppointGovernor( index );
	elseif item.key == "assign" then
		m_srActionGov = -1;
		OnAssignButton( index, m_CityBannerPlayerID, m_CityBannerCityID );
	else
		OnNameButton( index );
	end
end

local function SRA_OnGovernorActivate( item:table )
	m_srActionGov = item.def.Index;
	m_srActions.Reset();
	m_srActions.Focus( nil );
end

local function SRA_OnActionsClose()
	m_srActionGov = -1;
	m_srList.Focus( m_srList.GetFocusKey(), "Back" );
end

local function SRA_OnListClose()
	PlayerRequestClose();
	m_srList.Reset();
	SRA_Say( "Governors closed" );
end

function SRA_CreateLists()
	local function Active( wantActions:boolean )
		return function()
			return not ContextPtr:IsHidden() and not Controls.DetailsPanel:IsVisible() and ( m_srActionGov ~= -1 ) == wantActions;
		end
	end
	m_srList = KeyNavList_Create{ build = SRA_GovernorItems, isActive = Active( false ), onActivate = SRA_OnGovernorActivate, onClose = SRA_OnListClose };
	m_srActions = KeyNavList_Create{ build = SRA_ActionItems, isActive = Active( true ), onActivate = SRA_OnActionActivate, onClose = SRA_OnActionsClose };
end

-- "Governors. 2 titles available. Magnus, The Steward, not assigned, 1 of 5"
local function SRA_Announce()
	m_srActionGov = -1;
	local pPlayer:table = Players[ Game.GetLocalPlayer() ];
	local items:table = SRA_GovernorItems();
	if pPlayer == nil or #items == 0 then
		SRA_Say( "Governors. Nothing available", true );
		return;
	end
	m_srList.Open( "Governors", m_srList.GetFocusKey(), true );
	local index:number = 1;
	for i, item in ipairs( items ) do
		if item.key == m_srList.GetFocusKey() then index = i; end
	end
	local pg:table = pPlayer:GetGovernors();
	local titles:number = pg:GetGovernorPoints() - pg:GetGovernorPointsSpent();
	local head:string = ( titles > 0 ) and ( titles .. ( titles == 1 and " title" or " titles" ) .. " available" ) or "No titles available";
	SRA_Say( "Governors. " .. head .. ". " .. items[ index ].text .. ", " .. index .. " of " .. #items, true );
end

function SRA_OnUpdate( deltaTime:number )
	if m_srAppointWait ~= nil then
		m_srAppointWait = m_srAppointWait - deltaTime;
		if m_srAppointWait <= 0 then
			m_srAppointWait = nil;
			-- only when the governor really is not appointed (the event may have been missed, or the screen closed)
			local pPlayer:table = Players[ Game.GetLocalPlayer() ];
			if m_srAppointHash ~= nil and pPlayer ~= nil and not pPlayer:GetGovernors():HasGovernor( m_srAppointHash ) then
				SRA_Say( "The appointment did not happen" );
			end
		end
	end
	if m_srOpenPending and not ContextPtr:IsHidden() then
		m_srOpenDelay = m_srOpenDelay - deltaTime;
		if m_srOpenDelay > 0 then return; end
		m_srOpenPending = false;
		local ok:boolean, err = xpcall( SRA_Announce, KeyNavErrorHandler );
		if not ok then print( "Governors announce error: " .. tostring(err) ); end
	end
end

-- Handles the key for the governor / action list; every other keyboard event is swallowed while the screen is open
-- (the details child context handles its own keys).
function SRA_HandleInput( pInputStruct:table )
	if ContextPtr:IsHidden() or Controls.DetailsPanel:IsVisible() then return false; end
	if m_srList.HandleInput( pInputStruct ) or m_srActions.HandleInput( pInputStruct ) then return true; end
	local msg:number = pInputStruct:GetMessageType();
	return msg == KeyEvents.KeyDown or msg == KeyEvents.KeyUp;
end

-- Hot reload leaves the old instance's listeners registered: remove every one on shutdown.
function SRA_RemoveListeners()
	LuaEvents.GameDebug_Return.Remove( OnGameDebugReturn );
	Events.GovernorAppointed.Remove( OnGovernorAppointed );
	Events.GovernorAssigned.Remove( OnGovernorAssigned );
	Events.GovernorChanged.Remove( OnGovernorChanged );
	Events.GovernorPointsChanged.Remove( OnGovernorPointsChanged );
	Events.GovernorPromoted.Remove( OnGovernorPromoted );
	Events.NotificationActivated.Remove( OnProcessNotification );
	Events.LocalPlayerTurnBegin.Remove( OnLocalPlayerTurnBegin );
	Events.LocalPlayerTurnEnd.Remove( OnLocalPlayerTurnEnd );
	LuaEvents.GovernorPanel_Toggle.Remove( OnToggleGovernorPanel );
	LuaEvents.GovernorPanel_Close.Remove( Close );
	LuaEvents.GovernorPanel_Open.Remove( Open );
	LuaEvents.GovernorPanel_CancelAssignment.Remove( Open );
	LuaEvents.GovernorPanel_ClosedDetails.Remove( Open );
	LuaEvents.GovernorPanel_AssignDetails.Remove( Close );
	LuaEvents.ActionPanel_ActivateNotification.Remove( OnProcessTurnBlocker );
end
-- End ScreenReaderAccess

-- ===========================================================================
--	UI Input Event Handler
-- ===========================================================================
function OnInputHandler( pInputStruct:table )

	if ContextPtr:IsHidden() then return; end

	if SRA_HandleInput( pInputStruct ) then return true; end		-- ScreenReaderAccess

	local key = pInputStruct:GetKey();
	local msg = pInputStruct:GetMessageType();
	if msg == KeyEvents.KeyUp and key == Keys.VK_ESCAPE then 
		PlayerRequestClose();
		return true;
	end;
	return false;
end

-- ===========================================================================
function OnLocalPlayerTurnEnd()
	m_srAppointWait = nil;		-- ScreenReaderAccess
	if GameConfiguration.IsHotseat() and ContextPtr:IsVisible() then
		Close();
	end
end

-- ===========================================================================
function OnGovernorAssigned(cityPlayer, cityID, ePlayer, eGovernor)

	if ContextPtr:IsVisible() and ePlayer == Game.GetLocalPlayer() then
		Refresh();
	end
end

-- ===========================================================================
function OnGovernorChanged(ePlayer, eGovernor)

	if ContextPtr:IsVisible() and ePlayer == Game.GetLocalPlayer() then
		Refresh();
	end	
end

-- ===========================================================================
function OnGovernorPointsChanged(ePlayer, iPointDelta)

	if ContextPtr:IsVisible() and ePlayer == Game.GetLocalPlayer() then
		Refresh();
	end	
end

-- ===========================================================================
function OnGovernorPromoted(ePlayer, eGovernor, ePromotion)

	if ContextPtr:IsVisible() and ePlayer == Game.GetLocalPlayer() then
		Refresh();
	end	
end

-- ===========================================================================
function OnLocalPlayerTurnBegin()

	if ContextPtr:IsVisible() then
		Refresh();
	end	
end

-- ===========================================================================
function IsReadOnly()
	local pWorldCongress:table = Game.GetWorldCongress();
	return pWorldCongress:IsInSession();
end

-- ===========================================================================
function Initialize()

	-- Start off hidden
	ContextPtr:SetHide(true);
	ContextPtr:SetInitHandler( OnInit );
	ContextPtr:SetShutdown( OnShutdown );
	ContextPtr:SetInputHandler( OnInputHandler, true );
	ContextPtr:SetUpdate( SRA_OnUpdate );		-- ScreenReaderAccess
	SRA_CreateLists();							-- ScreenReaderAccess

	-- Lua Events
	LuaEvents.GameDebug_Return.Add( OnGameDebugReturn );

	-- GAME EVENTS --
	Events.GovernorAppointed.Add( OnGovernorAppointed );
	Events.GovernorAssigned.Add( OnGovernorAssigned );
	Events.GovernorChanged.Add( OnGovernorChanged );
	Events.GovernorPointsChanged.Add( OnGovernorPointsChanged );
	Events.GovernorPromoted.Add( OnGovernorPromoted );
	Events.NotificationActivated.Add(OnProcessNotification);
	Events.LocalPlayerTurnBegin.Add( OnLocalPlayerTurnBegin );	
	Events.LocalPlayerTurnEnd.Add( OnLocalPlayerTurnEnd );	


	-- UI EVENTS --
	LuaEvents.GovernorPanel_Toggle.Add( OnToggleGovernorPanel );
	LuaEvents.GovernorPanel_Close.Add( Close );
	LuaEvents.GovernorPanel_Open.Add( Open );
	LuaEvents.GovernorPanel_CancelAssignment.Add( Open );
	LuaEvents.GovernorPanel_ClosedDetails.Add( Open );
	LuaEvents.GovernorPanel_AssignDetails.Add( Close );

	LuaEvents.ActionPanel_ActivateNotification.Add(	OnProcessTurnBlocker );

	Controls.ModalScreenClose:RegisterCallback(Mouse.eLClick, PlayerRequestClose);

	m_TopPanelConsideredHeight = Controls.Vignette:GetSizeY() - TOP_PANEL_OFFSET;
	
	Refresh();
end
if HasCapability("CAPABILITY_GOVERNORS") then
	Initialize();
end

