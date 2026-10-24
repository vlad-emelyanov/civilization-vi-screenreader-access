-- ===========================================================================
-- Diplomacy Trade View Manager
-- ===========================================================================
include( "InstanceManager" );
include( "Colors" );
include( "Civ6Common" ); -- AutoSizeGridButton
include( "SupportFunctions" );
include( "PopupDialog" );
include( "ToolTipHelper_PlayerYields" );
include( "CivilizationIcon" );
include( "GreatWorksSupport" );
include( "ScreenReader" );		-- ScreenReaderAccess
include( "KeyNavList" );		-- ScreenReaderAccess
include( "DealSpeech" );		-- ScreenReaderAccess
include( "SRListen" );		-- ScreenReaderAccess


-- ===========================================================================
--	Globals
-- ===========================================================================
g_LocalPlayer =	nil;
g_OtherPlayer =	nil;
g_AvailableGroups = {};
g_IconOnlyIM = InstanceManager:new( "IconOnly",  "SelectButton", Controls.IconOnlyContainer );
g_IconAndTextIM	= InstanceManager:new( "IconAndText",  "SelectButton", Controls.IconAndTextContainer );
g_ValueEditDealItemID = -1;		-- The ID of the deal item that is being value edited.
g_ValueEditDealItemControlTable = nil; -- The control table of the deal item that is being edited.

-- These are initialized in CreateGroupTypes
DealItemGroupTypes = nil;
AvailableDealItemGroupTypes = nil;

g_uiMyOffers = {};
g_uiTheirOffers = {};

-- ===========================================================================
--	VARIABLES
-- ===========================================================================
local ms_PlayerPanelIM		:table		= InstanceManager:new( "PlayerAvailablePanel",  "Root" );
local ms_LeftRightListIM	:table		= InstanceManager:new( "LeftRightList",  "List", Controls.LeftRightListContainer );
local ms_TopDownListIM		:table		= InstanceManager:new( "TopDownList",  "List", Controls.TopDownListContainer );
local ms_AgreementOptionIM	:table		= InstanceManager:new( "AgreementOptionInstance",  "AgreementOptionButton", Controls.ValueEditStack );
local ms_CityDetailsIM		:table		= InstanceManager:new( "CityIconAndDetails", "CityDetailsContainer", Controls.IconAndTextContainer );
local ms_MinimizedSectionIM :table		= InstanceManager:new( "MinimizedSection","MinimizedSectionContainer" );

local OTHER_PLAYER = 0;
local LOCAL_PLAYER = 1;

-- Begin ScreenReaderAccess change: the available items as plain records, filled by the Populate* functions
-- below (one record per icon, with the callback its button registers); the keyboard lists at the end of the
-- file are built from them. Cleared in OnShow.
local m_srAvail:table = { [OTHER_PLAYER] = {}, [LOCAL_PLAYER] = {} };	-- by player type
local m_srOptions:table = {};	-- the entries of the agreement option popup (alliance type, war target ...)

local function SRA_AddAvail( player:table, rec:table )
	table.insert( m_srAvail[ GetPlayerType( player ) ], rec );
end

-- The game gives no text for an agreement / city / great work that cannot be added: name the validation result.
local function SRA_InvalidReason( entry:table )
	local result = entry.ValidationResult;
	if result ~= nil and DealValidationResult ~= nil then
		local ok:boolean, name = pcall( function()
			for n, v in pairs( DealValidationResult ) do
				if v == result then return n; end
			end
			return nil;
		end );
		if ok and name ~= nil then return string.lower( ( string.gsub( tostring( name ), "_", " " ) ) ); end
	end
	return "not possible right now";
end

local function SRA_IsAvailableDisabled( entry:table )
	return not entry.IsValid and entry.ValidationResult ~= DealValidationResult.MISSING_DEPENDENCY;
end
-- End ScreenReaderAccess change

ms_OtherPlayerID =	-1;
local ms_OtherPlayerIsHuman = false;

ms_InitiatedByPlayerID = -1;

ms_bIsGift = false;
ms_bIsDemand = false;
local ms_bExiting = false;

local ms_LastIncomingDealProposalAction = DealProposalAction.PENDING;

local m_kPopupDialog			:table; -- Will use custom "popup" since in leader mode the Popup stack is disabled.

local ms_DealGroups = {};

local ms_DealAgreementsGroup = {};

local ms_DefaultOneTimeGoldAmount = 100;

local ms_DefaultMultiTurnGoldAmount = 10;
local ms_DefaultMultiTurnGoldDuration = 30;

local ms_bForceUpdateOnCommit = false;

local ms_bDontUpdateOnBack = false;

local MAX_DEAL_ITEM_EDIT_HEIGHT = 300;

local m_kCollapsedCityDetails : table = {};

--Panel resizing variables
local m_StartingMouseX	: number;
local m_StartingMouseY	: number;
local m_OffersStartSizeY: number;
local m_InvStartSizeY	: number;

local m_MaxDragResizeY : number = 81;
local m_MinDragResizeY : number = 193; -- Will be dynamically set to account for different resolutions

-- ===========================================================================
function SetIconToSize(iconControl, iconName, iconSize)
	if iconSize == nil then
		iconSize = 50;
	end
	local x, y, szIconName, iconSize = IconManager:FindIconAtlasNearestSize(iconName, iconSize, true);
	iconControl:SetTexture(x, y, szIconName);
	iconControl:SetSizeVal(iconSize, iconSize);
end

-- ===========================================================================
function InitializeDealGroups()

	for i = 1, table.count(AvailableDealItemGroupTypes), 1 do
		g_AvailableGroups[i] = {};
	end

	for i = 1, table.count(DealItemGroupTypes), 1 do
		ms_DealGroups[i] = {};
	end

end

-- ===========================================================================
function GetPlayerType(player : table)
	if (player:GetID() == g_LocalPlayer:GetID()) then
		return LOCAL_PLAYER;
	end

	return OTHER_PLAYER;
end

-- ===========================================================================
function GetPlayerOfType(playerType : number)
	if (playerType == LOCAL_PLAYER) then
		return g_LocalPlayer;
	end

	return g_OtherPlayer;
end

-- ===========================================================================
function GetOtherPlayer(player : table)
	if (player ~= nil and player:GetID() == g_OtherPlayer:GetID()) then
		return g_LocalPlayer;
	end

	return g_OtherPlayer;
end

-- ===========================================================================
function SetDefaultLeaderDialogText()
	if (ms_bIsDemand == true and ms_InitiatedByPlayerID == ms_OtherPlayerID) then
		SetLeaderDialog("LOC_DIPLO_DEMAND_INTRO", "");
	else
		SetLeaderDialog("LOC_DIPLO_DEAL_INTRO", "");
	end
end

-- ===========================================================================
function ProposeWorkingDeal(bIsAutoPropose : boolean)
	if (bIsAutoPropose == nil) then
		bIsAutoPropose = false;
	end

	if (not DealManager.HasPendingDeal(g_LocalPlayer:GetID(), g_OtherPlayer:GetID())) then
		if (ms_bIsDemand) then
			DealManager.SendWorkingDeal(DealProposalAction.DEMANDED, g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
		else
			if (bIsAutoPropose) then
				DealManager.SendWorkingDeal(DealProposalAction.INSPECT, g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
			else
				DealManager.SendWorkingDeal(DealProposalAction.PROPOSED, g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
			end
		end
	end
end

-- ===========================================================================
function RequestEqualizeWorkingDeal()
	if (not DealManager.HasPendingDeal(g_LocalPlayer:GetID(), g_OtherPlayer:GetID())) then
		DealManager.SendWorkingDeal(DealProposalAction.EQUALIZE, g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
	end
end

-- ===========================================================================
function DealIsEmpty()
	local pDeal = DealManager.GetWorkingDeal(DealDirection.OUTGOING, g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
	if (pDeal == nil or pDeal:GetItemCount() == 0) then
		return true;
	end

	return false;
end

-- ===========================================================================
-- Update the proposed working deal.  This is called as items are changed in the deal.
-- It is primarily used to 'auto-propose' the deal when working with an AI.
function UpdateProposedWorkingDeal()
	if (ms_LastIncomingDealProposalAction ~= DealProposalAction.PENDING or IsAutoPropose()) then 

		local pDeal = DealManager.GetWorkingDeal(DealDirection.OUTGOING, g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
		if (pDeal == nil or pDeal:GetItemCount() == 0 or ms_bIsDemand) then
			-- Is a demand or no items, restart
			ms_LastIncomingDealProposalAction = DealProposalAction.PENDING;
			UpdateDealStatus();
		else
			if (IsAutoPropose()) then
				ProposeWorkingDeal(true);
			end
		end
	end
end

-- ===========================================================================
function UpdateOtherPlayerText(otherPlayerSays)
	local bHide = true;
	if (g_OtherPlayer ~= nil and otherPlayerSays ~= nil) then
		local playerConfig = PlayerConfigurations[g_OtherPlayer:GetID()];
		if (playerConfig ~= nil) then
			-- leader icon
			local otherPlayerController = CivilizationIcon:AttachInstance(Controls.OtherPlayerBubbleIcon);
			otherPlayerController:UpdateIconFromPlayerID(g_OtherPlayer:GetID());

			-- Set the leader name
			local leaderDesc = playerConfig:GetLeaderName();
			Controls.OtherPlayerBubbleName:SetText(Locale.ToUpper(Locale.Lookup("LOC_DIPLOMACY_DEAL_OTHER_PLAYER_SAYS", leaderDesc)));
		end
	end
	-- When we get dialog for what the leaders say during a trade, we can add it here!
end

-- ===========================================================================
function OnToggleCollapseGroup(iconList : table)
	if (iconList.ListStack:IsHidden()) then
		iconList.ListStack:SetHide(false);
	else
		iconList.ListStack:SetHide(true);
	end

	iconList.List:CalculateSize();
end
-- ===========================================================================
function CreateHorizontalGroup(rootStack : table, title : string)
	local iconList = ms_LeftRightListIM:GetInstance(rootStack);
	if (title == nil or title == "") then
		iconList.Title:SetHide(true);		-- No title
	else
		iconList.TitleText:LocalizeAndSetText(title);
	end
	iconList.List:CalculateSize();

	return iconList;
end

-- ===========================================================================
function CreateVerticalGroup(rootStack : table, title : string)
	local iconList = ms_TopDownListIM:GetInstance(rootStack);
	if (title == nil or title == "") then
		iconList.Title:SetHide(true);		-- No title
	else
		iconList.TitleText:LocalizeAndSetText(title);
	end
	iconList.List:CalculateSize();

	return iconList;
end


-- ===========================================================================
function CreatePlayerAvailablePanel(playerType : number, rootControl : table)

	--local playerPanel = ms_PlayerPanelIM:GetInstance(rootControl);

	g_AvailableGroups[AvailableDealItemGroupTypes.GOLD][playerType]				= g_AvailableGroups[AvailableDealItemGroupTypes.FAVOR][playerType];
	g_AvailableGroups[AvailableDealItemGroupTypes.LUXURY_RESOURCES][playerType]	= CreateHorizontalGroup(rootControl, "LOC_DIPLOMACY_DEAL_LUXURY_RESOURCES");
	g_AvailableGroups[AvailableDealItemGroupTypes.STRATEGIC_RESOURCES][playerType] = CreateHorizontalGroup(rootControl, "LOC_DIPLOMACY_DEAL_STRATEGIC_RESOURCES");
	g_AvailableGroups[AvailableDealItemGroupTypes.AGREEMENTS][playerType]			= CreateVerticalGroup(rootControl, "LOC_DIPLOMACY_DEAL_AGREEMENTS");
	g_AvailableGroups[AvailableDealItemGroupTypes.CITIES][playerType]				= CreateVerticalGroup(rootControl, "LOC_DIPLOMACY_DEAL_CITIES");
	g_AvailableGroups[AvailableDealItemGroupTypes.OTHER_PLAYERS][playerType]		= CreateVerticalGroup(rootControl, "LOC_DIPLOMACY_DEAL_OTHER_PLAYERS");
	g_AvailableGroups[AvailableDealItemGroupTypes.GREAT_WORKS][playerType]			= CreateVerticalGroup(rootControl, "LOC_DIPLOMACY_DEAL_GREAT_WORKS");
	g_AvailableGroups[AvailableDealItemGroupTypes.CAPTIVES][playerType]			= CreateVerticalGroup(rootControl, "LOC_DIPLOMACY_DEAL_CAPTIVES");

	rootControl:CalculateSize();

	return playerPanel;
end

-- ===========================================================================
function CreatePlayerDealPanel(playerType : number, rootControl : table)
--This creates the containers for the offer area...
	--ms_DealGroups[DealItemGroupTypes.RESOURCES][playerType]	= CreateHorizontalGroup(rootControl);
	--ms_DealGroups[DealItemGroupTypes.AGREEMENTS][playerType]	= CreateVerticalGroup(rootControl);
	--**********************************************************************
	-- Currently putting them all in the same control.
	ms_DealGroups[DealItemGroupTypes.RESOURCES][playerType] = rootControl;
	ms_DealGroups[DealItemGroupTypes.AGREEMENTS][playerType] = rootControl;
	ms_DealGroups[DealItemGroupTypes.CITIES][playerType] = rootControl;
	ms_DealGroups[DealItemGroupTypes.GREAT_WORKS][playerType] = rootControl;
	ms_DealGroups[DealItemGroupTypes.CAPTIVES][playerType] = rootControl;

end

-- ===========================================================================
function OnValuePulldownCommit(forType)

	local pDeal = DealManager.GetWorkingDeal(DealDirection.OUTGOING, g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
	if (pDeal ~= nil) then

		local pDealItem = pDeal:FindItemByID(g_ValueEditDealItemID);
		if (pDealItem ~= nil) then
			pDealItem:SetValueType( forType );
			
			local valueName = pDealItem:GetValueTypeNameID();
			if (g_ValueEditDealItemControlTable ~= nil) then
				-- Keep the text on the icon, that is currently hidden, up to date too.
				g_ValueEditDealItemControlTable.ValueText:LocalizeAndSetText(pDealItem:GetValueTypeNameID(valueName));
			end

			UpdateDealStatus();
			UpdateProposedWorkingDeal();
		end
	end

	Controls.ValueEditPopupBackground:SetHide(true);

end

-- ===========================================================================
function SetValueText(uiIcon, pDealItem)

	if (uiIcon.ValueText ~= nil) then
		local valueName = pDealItem:GetValueTypeNameID();
		if (valueName == nil) then
			if (pDealItem:HasPossibleValues()) then
				valueName = "LOC_DIPLOMACY_DEAL_CLICK_TO_CHANGE_DEAL_PARAMETER";
			end
		end
		if (valueName ~= nil) then
			uiIcon.ValueText:LocalizeAndSetText(valueName);
			uiIcon.ValueText:SetHide(false);
		else
			uiIcon.ValueText:SetHide(true);
		end
	end
end

-- ===========================================================================
function CreatePanels()

	-- Create the Other Player Panels
	CreatePlayerAvailablePanel(OTHER_PLAYER, Controls.TheirInventoryStack);

	-- Create the Local Player Panels
	CreatePlayerAvailablePanel(LOCAL_PLAYER, Controls.MyInventoryStack);

	CreatePlayerDealPanel(OTHER_PLAYER, g_uiTheirOffers);
	CreatePlayerDealPanel(LOCAL_PLAYER, g_uiMyOffers);

	Controls.EqualizeDeal:RegisterCallback( Mouse.eLClick, OnEqualizeDeal );
	Controls.EqualizeDeal:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	Controls.AcceptDeal:RegisterCallback( Mouse.eLClick, OnProposeOrAcceptDeal );
	Controls.AcceptDeal:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	Controls.DemandDeal:RegisterCallback( Mouse.eLClick, OnProposeOrAcceptDeal );
	Controls.DemandDeal:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	Controls.RefuseDeal:RegisterCallback(Mouse.eLClick, OnRefuseDeal);
	Controls.RefuseDeal:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	Controls.ResumeGame:RegisterCallback(Mouse.eLClick, OnResumeGame);
	Controls.ResumeGame:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);

end

function CreateGroupTypes()
	AvailableDealItemGroupTypes = {
	    GOLD                    = 1,
	    LUXURY_RESOURCES        = 2,
	    STRATEGIC_RESOURCES			= 3,
	    AGREEMENTS              = 4,
	    CITIES                  = 5,
	    OTHER_PLAYERS           = 6,
	    GREAT_WORKS             = 7,
	    CAPTIVES                = 8,
	};

	DealItemGroupTypes = {
	    GOLD                    = 1,
	    RESOURCES								= 2,
	    AGREEMENTS							= 3,
	    CITIES									= 4,
	    GREAT_WORKS							= 5,
	    CAPTIVES								= 6
	};
end

-- ===========================================================================
-- Find the 'instance' table from the control
function FindIconInstanceFromControl(rootControl : table)

	if (rootControl ~= nil) then
		local controlTable = g_IconOnlyIM:FindInstanceByControl(rootControl);
		if (controlTable == nil) then
			controlTable = g_IconAndTextIM:FindInstanceByControl(rootControl);
		end

		return controlTable;
	end

	return nil;
end

-- ===========================================================================
-- Show or hide the "amount text" or the "Value Text" sub-control of the supplied control instance
function SetHideValueText(controlTable : table, bHide : boolean)

	if (controlTable ~= nil) then
		if (controlTable.AmountText ~= nil) then
			controlTable.AmountText:SetHide(bHide);
		end
		if (controlTable.ValueText ~= nil) then
			controlTable.ValueText:SetHide(bHide);
		end
	end
end

-- ===========================================================================
-- Detach the value edit overlay from anything it is attached to.
function ClearValueEdit()

	SetHideValueText(g_ValueEditDealItemControlTable, false);

	g_ValueEditDealItemControlTable = nil
	g_ValueEditDealItemID = -1;

end

-- ===========================================================================
function UpdateDealStatus()
	local bDealValid = false;
	ClearValueEdit();
	local pDeal = DealManager.GetWorkingDeal(DealDirection.OUTGOING, g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
	if (pDeal ~= nil) then
		if (pDeal:GetItemCount() > 0) then
			bDealValid = true;
		end
	end

	if (bDealValid) then
		if pDeal:Validate() ~= DealValidationResult.VALID then
			bDealValid = false;
		end
	end

	Controls.EqualizeDeal:SetHide(ms_bIsDemand);

	-- Have we sent out a deal?
	local bHasPendingDeal = DealManager.HasPendingDeal(g_LocalPlayer:GetID(), g_OtherPlayer:GetID());

	if (not bHasPendingDeal and ms_LastIncomingDealProposalAction == DealProposalAction.PENDING) then
		-- We have yet to send out a deal.
		Controls.AcceptDeal:SetHide(true);
		local showDemand = bDealValid and ms_bIsDemand;
		Controls.DemandDeal:SetHide(not showDemand);
	else	
		local cantAccept = (ms_LastIncomingDealProposalAction ~= DealProposalAction.ACCEPTED and ms_LastIncomingDealProposalAction ~= DealProposalAction.PROPOSED and ms_LastIncomingDealProposalAction ~= DealProposalAction.ADJUSTED) or not bDealValid or bHasPendingDeal;
		Controls.AcceptDeal:SetHide(cantAccept);
		if (ms_bIsDemand) then
			if (g_LocalPlayer:GetID() == ms_InitiatedByPlayerID) then
				-- Local human is making a demand
				if (ms_LastIncomingDealProposalAction == DealProposalAction.ACCEPTED) then
					Controls.DemandDeal:SetHide(cantAccept);
					-- The other player has accepted the demand, but we must enact it.
					-- We won't have the human need to press the accept button, just do it and exit.
					OnProposeOrAcceptDeal();
					return;
				else
					Controls.AcceptDeal:SetHide(true);
					Controls.DemandDeal:SetHide(false);
				end
			else
				Controls.DemandDeal:SetHide(true);
			end
		else
			Controls.DemandDeal:SetHide(true);
		end
	end
	-- Hide/show directions if either side has no items
	local itemsFromLocal : number = pDeal:GetItemCount(g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
	local itemsFromOther : number = pDeal:GetItemCount(g_OtherPlayer:GetID(), g_LocalPlayer:GetID());
	g_uiMyOffers.DirectionsBracket:SetHide( itemsFromLocal > 0);
	g_uiTheirOffers.DirectionsBracket:SetHide( itemsFromOther > 0);

	UpdateProposalButtons(bDealValid);

	ResizeDealAndButtons();
end

-- ===========================================================================
function ResizeDealAndButtons()

	-- Find the widest deal button text and size others to match
	local refuseX, refuseY = AutoSizeGridButton(Controls.RefuseDeal,200,32,10,"1");
	local equalizeX, equalizeY = AutoSizeGridButton(Controls.EqualizeDeal,200,32,10,"1");
	local acceptX, acceptY = AutoSizeGridButton(Controls.AcceptDeal,200,41,10,"1");

	local minX = refuseX;
	if not Controls.EqualizeDeal:IsHidden() and minX < equalizeX then
		minX = equalizeX;
	end
	if not Controls.AcceptDeal:IsHidden() and minX < acceptX then
		minX = acceptX;
	end

	if Controls.RefuseDeal:GetSizeX() < minX then
		Controls.RefuseDeal:SetSizeX(minX);
	end
	if Controls.EqualizeDeal:GetSizeX() < minX then
		Controls.EqualizeDeal:SetSizeX(minX);
	end
	if Controls.AcceptDeal:GetSizeX() < minX then
		Controls.AcceptDeal:SetSizeX(minX);
	end

	Controls.DealOptionsStack:CalculateSize();

	g_uiTheirOffers.OfferStack:CalculateSize();
	Controls.TheirOfferScroll:CalculateSize();

	g_uiMyOffers.OfferStack:CalculateSize();
	Controls.MyOfferScroll:CalculateSize();
end

-- ===========================================================================
-- The Human has ask to have the deal equalized.  Well, what the AI is 
-- willing to take.
function OnEqualizeDeal()
	ClearValueEdit();
	RequestEqualizeWorkingDeal();
end

-- ===========================================================================
-- Propose the deal, if this is the first time, or accept it, if the other player has
-- accepted it.
function OnProposeOrAcceptDeal()

	ClearValueEdit();

	if (ms_LastIncomingDealProposalAction == DealProposalAction.PENDING or
		ms_LastIncomingDealProposalAction == DealProposalAction.REJECTED or 
		ms_LastIncomingDealProposalAction == DealProposalAction.EQUALIZE_FAILED) then
		ProposeWorkingDeal();
		UpdateDealStatus();
		UI.PlaySound("Confirm_Bed_Positive");
	else		
		if (ms_LastIncomingDealProposalAction == DealProposalAction.ACCEPTED or ms_LastIncomingDealProposalAction == DealProposalAction.PROPOSED or ms_LastIncomingDealProposalAction == DealProposalAction.ADJUSTED) then
			-- Any adjustments?
			if (DealManager.AreWorkingDealsEqual(g_LocalPlayer:GetID(), g_OtherPlayer:GetID())) then
				-- Yes, we can accept
				-- if deal will trigger war, prompt user before confirming deal
				local sendDealAndContinue = function() 
					-- Send the deal.  This will also send out a POSITIVE response statement
					DealManager.SendWorkingDeal(DealProposalAction.ACCEPTED, g_LocalPlayer:GetID(), g_OtherPlayer:GetID());		
					OnContinue();
					UI.PlaySound("Confirm_Bed_Positive");
				end;

				local pDeal = DealManager.GetWorkingDeal(DealDirection.OUTGOING, g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
				local pJointWarItem = pDeal:FindItemByType(DealItemTypes.AGREEMENTS, DealAgreementTypes.JOINT_WAR);
				if DealAgreementTypes.JOINT_WAR and pJointWarItem then
					local iWarType = pJointWarItem:GetParameterValue("WarType");

					if (iWarType == nil) then iWarType = WarTypes.FORMAL_WAR; end

					local targetPlayerID = pJointWarItem:GetValueType();
					if (targetPlayerID >= 0) then
						LuaEvents.DiplomacyActionView_ConfirmWarDialog(g_LocalPlayer:GetID(), targetPlayerID, iWarType, sendDealAndContinue);
					else
						UI.DataError("Invalid Player ID to declare Joint War to: " .. targetPlayerID);
					end
				else
					local pThirdPartyWarItem = pDeal:FindItemByType(DealItemTypes.AGREEMENTS, DealAgreementTypes.THIRD_PARTY_WAR);
					if (DealAgreementTypes.THIRD_PARTY_WAR and pThirdPartyWarItem) then
						local iWarType = pThirdPartyWarItem:GetParameterValue("WarType");

						if (iWarType == nil) then iWarType = WarTypes.FORMAL_WAR; end

						local targetPlayerID = pThirdPartyWarItem:GetValueType();
						if (targetPlayerID >= 0) then
							LuaEvents.DiplomacyActionView_ConfirmWarDialog(g_LocalPlayer:GetID(), targetPlayerID, iWarType, sendDealAndContinue);
						else
							UI.DataError("Invalid Player ID to declare Third Party War to: " .. targetPlayerID);
						end
					else
						sendDealAndContinue();
					end			
				end	
			else
				-- No, send an adjustment and stay in the deal view.
				DealManager.SendWorkingDeal(DealProposalAction.ADJUSTED, g_LocalPlayer:GetID(), g_OtherPlayer:GetID());		
				UpdateDealStatus();
			end
		end
	end
end

-- ===========================================================================
function OnRefuseDeal(bForceClose)

	if (bForceClose == nil) then
		bForceClose = false;
	end

	local localPlayerID : number = Game.GetLocalPlayer();
	local otherPlayerID : number = g_OtherPlayer:GetID();
	local bHasPendingDeal = DealManager.HasPendingDeal(localPlayerID, otherPlayerID);

	local sessionID = DiplomacyManager.FindOpenSessionID(localPlayerID, otherPlayerID);
	if (sessionID ~= nil) then
		if (not ms_OtherPlayerIsHuman and not bHasPendingDeal) then
			-- Refusing an AI's deal
			ClearValueEdit();

			if (ms_InitiatedByPlayerID == ms_OtherPlayerID) then
				-- AI started this, so tell them that we don't want the deal
				if (bForceClose == true) then
					-- Forcing the close, usually because the turn timer expired
					DealManager.SendWorkingDeal(DealProposalAction.REJECTED, localPlayerID, otherPlayerID);
					DiplomacyManager.CloseSession(sessionID);
					StartExitAnimation();
				else
					local pDeal : table = DealManager.GetWorkingDeal(DealDirection.OUTGOING, localPlayerID, otherPlayerID);
					if(pDeal:HasUnacceptableItems())then
						for pDealItem in pDeal:Items() do
							if(pDealItem:IsUnacceptable() and pDealItem:GetFromPlayerID() == localPlayerID)then
								DealManager.SendWorkingDeal(DealProposalAction.REJECTED_PERMANENT, localPlayerID, otherPlayerID);
								return;
							end
						end
					end
					DiplomacyManager.AddResponse(sessionID, localPlayerID, "NEGATIVE");
				end
			else
				-- Else close the session
				DiplomacyManager.CloseSession(sessionID);
				StartExitAnimation();
			end
		else
			if (ms_OtherPlayerIsHuman) then
				if (bHasPendingDeal) then
					-- Canceling the deal with the other player.
					DealManager.SendWorkingDeal(DealProposalAction.CLOSED, localPlayerID, otherPlayerID);
				else
					if (ms_InitiatedByPlayerID ~= localPlayerID) then
						-- Refusing the deal with the other player.
						DealManager.SendWorkingDeal(DealProposalAction.REJECTED, localPlayerID, otherPlayerID);
					end
				end

				DiplomacyManager.CloseSession(sessionID);
				StartExitAnimation();
			end				
		end
	else
		-- We have lost our session!
		if (not ContextPtr:IsHidden()) then
			if (not ms_bExiting) then
				OnResumeGame();
			end
		end		
	end

end

-- ===========================================================================
function OnResumeGame()

	-- Exiting back to wait for a response
	ClearValueEdit();

	local sessionID = DiplomacyManager.FindOpenSessionID(Game.GetLocalPlayer(), g_OtherPlayer:GetID());
	if (sessionID ~= nil) then
		DiplomacyManager.CloseSession(sessionID);
	end

	-- Start the exit animation, it will call OnContinue when complete
	StartExitAnimation();
end

-- ===========================================================================
function OnExitFadeComplete()
	if(Controls.TradePanelFade:IsReversing()) then
		Controls.TradePanelFade:SetSpeed(2);
		Controls.TradePanelSlide:SetSpeed(2);

		OnContinue();
	end
end
Controls.TradePanelFade:RegisterEndCallback(OnExitFadeComplete);
-- ===========================================================================
-- Change the value number edit by a delta
function OnValueAmountEditDelta(dealItemID:number, delta:number)

	local pDeal = DealManager.GetWorkingDeal(DealDirection.OUTGOING, g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
	if (pDeal ~= nil) then

		local pDealItem = pDeal:FindItemByID(dealItemID);
		if (pDealItem ~= nil) then
			local iNewAmount = tonumber(Controls.ValueAmountEditBox:GetText() or 0) + delta;
			iNewAmount = clip(iNewAmount, 1, pDealItem:GetMaxAmount());
			Controls.ValueAmountEditBox:SetText(tostring(iNewAmount));
		end
	end
end

-- ===========================================================================
-- Detach the value edit if it is attached to the control
function DetachValueEdit(itemID: number)

	if (itemID == g_ValueEditDealItemID) then
		ClearValueEdit();
	end

end

-- ===========================================================================
function IsItemValueEditable(itemType: number)
	return itemType == DealItemTypes.GOLD or itemType == DealItemTypes.RESOURCES;
end

-- ===========================================================================
function GetItemTypeIcon(pDealItem: table)
	local itemType = pDealItem:GetType();
	if (itemType == DealItemTypes.GOLD) then
		return "ICON_YIELD_GOLD_5";
	elseif (itemType == DealItemTypes.RESOURCES) then
		local resourceType = pDealItem:GetValueType();
		local resourceDesc = GameInfo.Resources[resourceType];
		return "ICON_" .. resourceDesc.ResourceType;
	end
	return nil;
end

-- ===========================================================================
-- Reattach the value edit overlay to the control set it is editing.
function ReAttachValueEdit()

	if (g_ValueEditDealItemControlTable ~= nil) then

		SetHideValueText(g_ValueEditDealItemControlTable, true);

		-- Display the number in the value edit field
		local pDeal = DealManager.GetWorkingDeal(DealDirection.OUTGOING, g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
		if (pDeal ~= nil) then

			local pDealItem = pDeal:FindItemByID(g_ValueEditDealItemID);
			if (pDealItem ~= nil) then

				local itemID = pDealItem:GetID();
				local itemType = pDealItem:GetType();
				if (IsItemValueEditable(itemType)) then
					-- Hide/show everything for GOLD and RESOURCE options
					ms_AgreementOptionIM:ResetInstances();
					Controls.ValueEditIconGrid:SetHide(false);
					Controls.ValueAmountEditBoxContainer:SetHide(false);

					local iDuration = pDealItem:GetDuration();

					Controls.ValueEditHeaderLabel:SetText(Locale.Lookup("LOC_DIPLOMACY_DEAL_HOW_MANY"));
			
					if (iDuration == 0) then
						---- One time
						Controls.ValueEditValueText:SetHide(true);
					else
						---- Multi-turn
						Controls.ValueEditValueText:LocalizeAndSetText("LOC_DIPLOMACY_DEAL_FOR_TURNS", iDuration);
						Controls.ValueEditValueText:SetHide(false);
					end

					SetIconToSize(Controls.ValueEditIcon, GetItemTypeIcon(pDealItem));
		
					Controls.ValueEditAmountText:SetText(tostring(pDealItem:GetAmount()));
					Controls.ValueEditAmountText:SetHide(false);

					Controls.ValueAmountEditBox:SetText(tostring(pDealItem:GetAmount()));
					Controls.ValueEditButton:RegisterCallback( Mouse.eLClick, function() OnValueEditButton(itemID); end );
					Controls.ValueAmountEditLeftButton:RegisterCallback( Mouse.eLClick, function() OnValueAmountEditDelta(itemID, -1); end );
					Controls.ValueAmountEditRightButton:RegisterCallback( Mouse.eLClick, function() OnValueAmountEditDelta(itemID, 1); end );
				elseif (itemType == DealItemTypes.AGREEMENTS) then
					local subType = pDealItem:GetSubType();
					local iDuration = pDealItem:GetDuration();

					ShowAgreementOptionPopup(subType, iDuration, pDealItem:GetFromPlayerID());
				else
					-- The value of the item cannot be adjusted so don't show a popup
					return;
				end
			end
		end			

		Controls.ValueEditIconGrid:DoAutoSize();

		ResizeValueEditScrollPanel();

		Controls.ValueEditPopup:DoAutoSize();
		Controls.ValueEditPopupBackground:SetHide(false);
	end

end

-- ===========================================================================
-- Attach the value edit overlay to a control set.
function AttachValueEdit(rootControl : table, dealItemID : number)

	ClearValueEdit();

	local pDeal = DealManager.GetWorkingDeal(DealDirection.OUTGOING, g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
	if (pDeal ~= nil) then

		local pDealItem = pDeal:FindItemByID(dealItemID);
		if (pDealItem ~= nil) then
			-- Do we have something to edit?
			if (pDealItem:HasPossibleValues() or pDealItem:HasPossibleAmounts()) then
				-- Yes
				g_ValueEditDealItemControlTable = FindIconInstanceFromControl(rootControl);
				g_ValueEditDealItemID = dealItemID;

				ReAttachValueEdit();
			end
		end
	end

end

-- ===========================================================================
-- Update the deal panel for a player
function UpdateDealPanel(player)
	
	-- If we modify the deal without sending it to the AI then reset the status to PENDING
	ms_LastIncomingDealProposalAction = DealProposalAction.PENDING;

	UpdateDealStatus();

	PopulatePlayerDealPanel(g_uiTheirOffers, g_OtherPlayer);
	PopulatePlayerDealPanel(g_uiMyOffers, g_LocalPlayer);
	
	ResizeDealAndButtons();

end

-- ===========================================================================
function OnClickAvailableOneTimeGold(player, iAddAmount : number)

	if ((ms_bIsDemand == true or ms_bIsGift == true) and ms_InitiatedByPlayerID == ms_OtherPlayerID) then
		-- Can't modifiy demand that is not ours
		return;
	end

	local pDeal = DealManager.GetWorkingDeal(DealDirection.OUTGOING, g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
	if (pDeal ~= nil) then

		local pPlayerTreasury = player:GetTreasury();
		local bFound = false;
		
		-- Already there?
		local dealItems = pDeal:FindItemsByType(DealItemTypes.GOLD, DealItemSubTypes.NONE, player:GetID());
		local pDealItem;
		if (dealItems ~= nil) then
			for i, pDealItem in ipairs(dealItems) do
				if (pDealItem:GetDuration() == 0) then
					-- Already have a one time gold.  Up the amount
					iAddAmount = pDealItem:GetAmount() + iAddAmount;
					iAddAmount = clip(iAddAmount, nil, pDealItem:GetMaxAmount());
					if (iAddAmount ~= pDealItem:GetAmount()) then
						pDealItem:SetAmount(iAddAmount);
						bFound = true;
						break;
					else
						return;		-- No change, just exit
					end
				end
			end
		end

		-- Doesn't exist yet, add it.
		if (not bFound) then

			-- Going to add anything?
			pDealItem = pDeal:AddItemOfType(DealItemTypes.GOLD, player:GetID());
			if (pDealItem ~= nil) then

				-- Set the duration, so the max amount calculation knows what we are doing
				pDealItem:SetDuration(0);

				-- Adjust the gold to our max
				iAddAmount = clip(iAddAmount, nil, pDealItem:GetMaxAmount());
				if (iAddAmount > 0) then
					pDealItem:SetAmount(iAddAmount);
					bFound = true;
				else
					-- It is empty, remove it.
					local itemID = pDealItem:GetID();
					pDeal:RemoveItemByID(itemID);
				end
			end
		end


		if (bFound) then
			UpdateProposedWorkingDeal();
			UpdateDealPanel(player);
		end
	end
end

-- ===========================================================================
function OnClickAvailableMultiTurnGold(player, iAddAmount : number, iDuration : number)

	if ((ms_bIsDemand == true or ms_bIsGift == true) and ms_InitiatedByPlayerID == ms_OtherPlayerID) then
		-- Can't modifiy demand that is not ours
		return;
	end

	local pDeal = DealManager.GetWorkingDeal(DealDirection.OUTGOING, g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
	if (pDeal ~= nil) then

		local pPlayerTreasury = player:GetTreasury();

		local bFound = false;
		UI.PlaySound("UI_GreatWorks_Put_Down");

		-- Already there?
		local dealItems = pDeal:FindItemsByType(DealItemTypes.GOLD, DealItemSubTypes.NONE, player:GetID());
		local pDealItem;
		if (dealItems ~= nil) then
			for i, pDealItem in ipairs(dealItems) do
				if (pDealItem:GetDuration() ~= 0) then
					-- Already have a multi-turn gold.  Up the amount
					iAddAmount = pDealItem:GetAmount() + iAddAmount;
					iAddAmount = clip(iAddAmount, nil, pDealItem:GetMaxAmount());
					if (iAddAmount ~= pDealItem:GetAmount()) then
						pDealItem:SetAmount(iAddAmount);
						bFound = true;
						break;
					else
						return;		-- No change, just exit
					end
				end
			end
		end

		-- Doesn't exist yet, add it.
		if (not bFound) then
			-- Going to add anything?
			pDealItem = pDeal:AddItemOfType(DealItemTypes.GOLD, player:GetID());
			if (pDealItem ~= nil) then

				-- Set the duration, so the max amount calculation knows what we are doing
				pDealItem:SetDuration(iDuration);

				-- Adjust the gold to our max
				iAddAmount = clip(iAddAmount, nil, pDealItem:GetMaxAmount());

				if (iAddAmount > 0) then
					pDealItem:SetAmount(iAddAmount);
					bFound = true;
				else
					-- It is empty, remove it.
					local itemID = pDealItem:GetID();
					pDeal:RemoveItemByID(itemID);
				end
			end
		end

		if (bFound) then
			UpdateProposedWorkingDeal();
			UpdateDealPanel(player);
		end
	end
end

-- ===========================================================================
-- Clip val to be within the range of min and max
function clip(val: number, min: number, max: number)
	if min and val < min then
		val = min;
	elseif max and val > max then
		val = max;
	end
	return val;
end

-- ===========================================================================
-- Check to see if the deal should be auto-proposed.
function IsAutoPropose()
	if (not ms_OtherPlayerIsHuman) then
		local pDeal : table = DealManager.GetWorkingDeal(DealDirection.OUTGOING, g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
		pDeal:Validate();
		if (pDeal ~= nil and not ms_bIsDemand and pDeal:IsValid() and not DealManager.HasPendingDeal(g_LocalPlayer:GetID(), g_OtherPlayer:GetID())) then
			local itemsFromLocal : number = pDeal:GetItemCount(g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
			local itemsFromOther : number = pDeal:GetItemCount(g_OtherPlayer:GetID(), g_LocalPlayer:GetID());

			if (itemsFromLocal > 0 or itemsFromOther > 0) then
				return true;
			end
		end
	end
	return false;
end

-- ===========================================================================
-- Check the state of the deal and show/hide the special proposal buttons for a possible gift (not actually possible until XP2)
function UpdateProposalButtonsForGift(itemsFromLocal : number, itemsFromOther : number)
	if (itemsFromLocal == 0 and itemsFromOther > 0) then
		return true;
	end

	return false;
end

-- ===========================================================================
-- Check the state of the deal and show/hide the special proposal buttons
function UpdateProposalButtons(bDealValid)

	local bDealIsPending : boolean = DealManager.HasPendingDeal(g_LocalPlayer:GetID(), g_OtherPlayer:GetID());

	if (bDealValid and (not bDealIsPending or not ms_OtherPlayerIsHuman)) then
		Controls.ResumeGame:SetHide(true);
		local pDeal : table = DealManager.GetWorkingDeal(DealDirection.OUTGOING, g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
		Controls.EqualizeDeal:SetHide(ms_bIsDemand);
		if (pDeal ~= nil) then

			local itemsFromLocal : number = pDeal:GetItemCount(g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
			local itemsFromOther : number = pDeal:GetItemCount(g_OtherPlayer:GetID(), g_LocalPlayer:GetID());
			ms_bIsGift = pDeal:IsGift() and itemsFromOther > 0;

			if (not ms_bIsDemand) then
				if (not ms_OtherPlayerIsHuman) then
					-- Dealing with an AI
					if (pDeal:HasUnacceptableItems()) then
						Controls.EqualizeDeal:SetHide(true);
						Controls.AcceptDeal:SetHide(true);
						SetLeaderDialog("LOC_DIPLO_DEAL_UNACCEPTABLE_DEAL", "");
					elseif (itemsFromLocal > 0 and itemsFromOther == 0) then
						-- One way gift?

						if ms_LastIncomingDealProposalAction == DealProposalAction.EQUALIZE_FAILED then
							-- Equalize failed, hide the button, and we can't accept now!
							-- Except... not.
							-- The AI will yield EQUALIZE_FAILED if it would have accepted the gift without modifications.
							-- The AI does not distinguish between 'this gift is fine as is' and 'i would not give you anything for that'.
							Controls.AcceptDeal:SetShow(false);
							Controls.EqualizeDeal:SetShow(false);
							SetLeaderDialog("LOC_DIPLO_DEAL_LEADER_GIFT_EQUALIZE_FAILED", "");
						elseif ms_LastIncomingDealProposalAction == DealProposalAction.REJECTED then
							-- Most likely autoproposed, there's a chance for an equalize. No accept, again.
							Controls.AcceptDeal:SetShow(false);
							Controls.EqualizeDeal:SetShow(true);
							Controls.EqualizeDeal:LocalizeAndSetText("LOC_DIPLOMACY_DEAL_WHAT_WOULD_IT_TAKE");
							Controls.EqualizeDeal:LocalizeAndSetToolTip("LOC_DIPLOMACY_DEAL_WHAT_IT_WILL_TAKE_TOOLTIP");
							SetLeaderDialog("LOC_DIPLO_MAKE_DEAL_AI_REFUSE_DEAL_ANY_ANY", "");
						else
							-- No immediate complaints, I guess we can show both equalize and accept.
							Controls.AcceptDeal:SetShow(true);
							Controls.AcceptDeal:LocalizeAndSetText("LOC_DIPLOMACY_DEAL_GIFT_DEAL");
							Controls.EqualizeDeal:SetShow(true);
							Controls.EqualizeDeal:LocalizeAndSetText("LOC_DIPLOMACY_DEAL_WHAT_WOULD_YOU_GIVE_ME");
							Controls.EqualizeDeal:LocalizeAndSetToolTip("LOC_DIPLO_DEAL_WHAT_WOULD_YOU_GIVE_ME_TOOLTIP");
							SetLeaderDialog("LOC_DIPLO_DEAL_LEADER_GIFT", "LOC_DIPLO_DEAL_LEADER_GIFT_EFFECT");
						end
					elseif ms_bIsGift then -- Incoming gift
						Controls.EqualizeDeal:SetShow(false);
					else
						if (UpdateProposalButtonsForGift(itemsFromLocal, itemsFromOther)) then
							-- AI was unable to equalize for the requested items so hide the equalize button
							if ms_LastIncomingDealProposalAction == DealProposalAction.EQUALIZE_FAILED then
								Controls.EqualizeDeal:SetHide(true);
								SetLeaderDialog("LOC_DIPLO_DEAL_LEADER_EQUALIZE_FAILED", "");
							else
								Controls.EqualizeDeal:SetHide(false);
								SetLeaderDialog("LOC_DIPLO_DEAL_UNFAIR", "");
							end

							Controls.EqualizeDeal:LocalizeAndSetText("LOC_DIPLOMACY_DEAL_WHAT_WOULD_IT_TAKE");
							Controls.EqualizeDeal:LocalizeAndSetToolTip("LOC_DIPLOMACY_DEAL_WHAT_IT_WILL_TAKE_TOOLTIP");
							Controls.AcceptDeal:SetHide(true); --If either of the above buttons are showing, disable the main accept button

						else	--Something is being offered on both sides
							-- Show equalize button if the accept button is hidden and the AI already hasn't attempted to equalize the deal
							if Controls.AcceptDeal:IsHidden() and ms_LastIncomingDealProposalAction ~= DealProposalAction.EQUALIZE_FAILED then
								Controls.EqualizeDeal:SetHide(false);
								Controls.EqualizeDeal:LocalizeAndSetText("LOC_DIPLOMACY_MAKE_DEAL_EQUITABLE");
								Controls.EqualizeDeal:LocalizeAndSetToolTip("LOC_DIPLOMACY_MAKE_DEAL_EQUITABLE_TOOLTIP");
							else
								Controls.EqualizeDeal:SetHide(true);
								if ms_LastIncomingDealProposalAction == DealProposalAction.PROPOSED then
									SetLeaderDialog("LOC_DIPLO_DEAL_INTRO_AI", "");
								elseif ms_LastIncomingDealProposalAction == DealProposalAction.ACCEPTED then
									SetLeaderDialog("LOC_DIPLO_MAKE_DEAL_AI_ACCEPT_DEAL_ANY_ANY", "");
								elseif ms_LastIncomingDealProposalAction == DealProposalAction.ADJUSTED then
									SetLeaderDialog("LOC_DIPLO_DEAL_LEADER_EQUALIZE_SUCCEEDED", "");
								else
									SetLeaderDialog("LOC_DIPLO_DEAL_LEADER_EQUALIZE_FAILED", "");
								end
							end

							Controls.AcceptDeal:LocalizeAndSetText("LOC_DIPLOMACY_DEAL_ACCEPT_DEAL");
						end
					end
				else
					-- Dealing with another human

					Controls.EqualizeDeal:SetHide(true);
					Controls.AcceptDeal:SetHide(false);

					if (ms_LastIncomingDealProposalAction == DealProposalAction.PENDING) then
						-- Just starting the deal
						if (itemsFromLocal > 0 and itemsFromOther == 0) then
							-- Is this one way to them?
							g_uiMyOffers.Directions:SetHide(true);
							g_uiTheirOffers.Directions:SetHide(false);
							Controls.AcceptDeal:LocalizeAndSetText("LOC_DIPLOMACY_DEAL_GIFT_DEAL");
						else
							-- Everything else is a proposal to another human
							g_uiMyOffers.Directions:SetHide(true);
							g_uiTheirOffers.Directions:SetHide(true);
							Controls.AcceptDeal:LocalizeAndSetText("LOC_DIPLOMACY_DEAL_PROPOSE_DEAL");
						end
						-- Make sure the leader text is set to something appropriate.
						SetDefaultLeaderDialogText();
					else
						g_uiMyOffers.Directions:SetHide(true);
						g_uiTheirOffers.Directions:SetHide(true);
						-- Are the incoming and outgoing deals the same?
						if (DealManager.AreWorkingDealsEqual(g_LocalPlayer:GetID(), g_OtherPlayer:GetID())) then 
							Controls.AcceptDeal:LocalizeAndSetText("LOC_DIPLOMACY_DEAL_ACCEPT_DEAL");
						else
							Controls.AcceptDeal:LocalizeAndSetText("LOC_DIPLOMACY_DEAL_PROPOSE_DEAL");
						end
					end
				end
			else
				-- Is a Demand
				if (ms_InitiatedByPlayerID == ms_OtherPlayerID) then
					g_uiMyOffers.Directions:SetHide(true);
					g_uiTheirOffers.Directions:SetHide(true);
					SetDefaultLeaderDialogText();
				else
					if (itemsFromOther == 0) then
						g_uiTheirOffers.Directions:SetHide(false);
					else
						g_uiTheirOffers.Directions:SetHide(true);
					end
					-- Demand against another player
					SetLeaderDialog("LOC_DIPLO_DEAL_LEADER_DEMAND", "LOC_DIPLO_DEAL_LEADER_DEMAND_EFFECT");
				end
			end
		else
			-- Make sure the leader text is set to something appropriate.
			SetDefaultLeaderDialogText();
		end
	else															
		--There isn't a valid deal, or we are just viewing a pending deal.
		local bIsViewing : boolean = (bDealIsPending and ms_OtherPlayerIsHuman);

		local itemsFromLocal : number = 0;
		local itemsFromOther : number = 0;

		local pDeal : table = DealManager.GetWorkingDeal(DealDirection.OUTGOING, g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
		if (pDeal ~= nil) then
			itemsFromLocal = pDeal:GetItemCount(g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
			itemsFromOther = pDeal:GetItemCount(g_OtherPlayer:GetID(), g_LocalPlayer:GetID());
		end

		g_uiMyOffers.Directions:SetHide( bIsViewing or itemsFromLocal > 0);
		g_uiTheirOffers.Directions:SetHide( bIsViewing or itemsFromOther > 0);
		Controls.EqualizeDeal:SetHide(true);
		Controls.AcceptDeal:SetHide(true);
		Controls.DemandDeal:SetHide(true);

		if (not DealIsEmpty() and not bDealValid) then
			-- Set have the other leader tell them that the deal has invalid items.
			SetLeaderDialog("LOC_DIPLOMACY_DEAL_INVALID", "");
		else
			SetDefaultLeaderDialogText();
		end
			
		Controls.ResumeGame:SetHide(not bIsViewing);
	end

	if (bDealIsPending and ms_OtherPlayerIsHuman) then
		if (ms_bIsDemand) then
			Controls.RefuseDeal:LocalizeAndSetText("LOC_DIPLOMACY_DEAL_CANCEL_DEMAND");
		elseif ms_bIsGift then -- Incoming gift
			Controls.RefuseDeal:LocalizeAndSetText("LOC_DIPLOMACY_DEAL_REFUSE_GIFT");
		else
			Controls.RefuseDeal:LocalizeAndSetText("LOC_DIPLOMACY_DEAL_CANCEL_DEAL");
		end
	else
		-- Did the other player start this or the local player?
		if (ms_InitiatedByPlayerID == ms_OtherPlayerID) then
			if (not bDealValid) then
				-- Our changes have made the deal invalid, say cancel instead
				Controls.RefuseDeal:LocalizeAndSetText("LOC_DIPLOMACY_DEAL_CANCEL_DEAL");
			else
				if (ms_bIsDemand) then
					Controls.AcceptDeal:LocalizeAndSetText("LOC_DIPLOMACY_DEAL_ACCEPT_DEMAND");
					Controls.RefuseDeal:LocalizeAndSetText("LOC_DIPLOMACY_DEAL_REFUSE_DEMAND");
				elseif ms_bIsGift then -- Incoming gift
					Controls.AcceptDeal:LocalizeAndSetText("LOC_DIPLOMACY_DEAL_ACCEPT_GIFT");
					Controls.RefuseDeal:LocalizeAndSetText("LOC_DIPLOMACY_DEAL_REFUSE_GIFT");
				else
					Controls.RefuseDeal:LocalizeAndSetText("LOC_DIPLOMACY_DEAL_REFUSE_DEAL");
				end
			end
		else
			Controls.RefuseDeal:LocalizeAndSetText("LOC_DIPLOMACY_DEAL_EXIT_DEAL");
		end
	end
	Controls.DealOptionsStack:CalculateSize();

	if (ms_bIsDemand) then
		if (ms_InitiatedByPlayerID == ms_OtherPlayerID) then
			-- Demand from the other player and we are responding
			Controls.MyOfferLabel:SetHide(false);
			Controls.TheirOfferLabel:SetHide(true);
			g_uiTheirOffers.OfferStack:SetHide(true);
			g_uiMyOffers.OfferStack:SetHide(false);
		else
			-- Demand from us, to the other player
			Controls.MyOfferLabel:SetHide(true);
			g_uiMyOffers.OfferStack:SetHide(true);
			Controls.TheirOfferLabel:SetHide(false);
			g_uiTheirOffers.OfferStack:SetHide(false);
		end
	else
		Controls.MyOfferLabel:SetHide(false);
		Controls.TheirOfferLabel:SetHide(false);
		g_uiTheirOffers.OfferStack:SetHide(false);
		g_uiMyOffers.OfferStack:SetHide(false);
	end
end

-- ===========================================================================
function PopulateAvailableGold(player : table, iconList : table)

	local availableItemCount : number = 0;

	local eFromPlayerID : number = player:GetID();
	local eToPlayerID : number = GetOtherPlayer(player):GetID();

	local pForDeal : table = DealManager.GetWorkingDeal(DealDirection.OUTGOING, g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
	local possibleResources : table = DealManager.GetPossibleDealItems(eFromPlayerID, eToPlayerID, DealItemTypes.GOLD, pForDeal);
	if (possibleResources ~= nil) then
		for i, entry in ipairs(possibleResources) do
			if (entry.Duration == 0) then
				-- One time gold
				local playerTreasury:table	= player:GetTreasury();
				local goldBalance	:number = math.floor(playerTreasury:GetGoldBalance());

				if (not ms_bIsDemand) then
					-- One time gold
					local uiIcon : table = g_IconOnlyIM:GetInstance(iconList.ListStack);
					uiIcon.AmountText:SetHide(false);
					uiIcon.AmountText:SetText(goldBalance);
					uiIcon.SelectButton:SetToolTipString(nil);		-- We recycle the entries, so make sure this is clear.
					SetIconToSize(uiIcon.Icon, "ICON_YIELD_GOLD_5");
					uiIcon.SelectButton:RegisterCallback( Mouse.eLClick, function() OnClickAvailableOneTimeGold(player, ms_DefaultOneTimeGoldAmount); end );
					uiIcon.SelectButton:RegisterCallback( Mouse.eLClick, function() OnClickAvailableOneTimeGold(player, ms_DefaultOneTimeGoldAmount); end );
					uiIcon.RemoveButton:SetHide(true);
					uiIcon.StopAskingButton:SetHide(true);
					uiIcon.Icon:SetColor(1,1,1);
					availableItemCount = availableItemCount + 1;
					SRA_AddAvail( player, { key = "gold:0", kind = "gold", amount = goldBalance, duration = 0,		-- ScreenReaderAccess
						hint = "Enter adds " .. ms_DefaultOneTimeGoldAmount .. " gold. Change the amount in the Deal section with Left and Right",
						callback = function() OnClickAvailableOneTimeGold(player, ms_DefaultOneTimeGoldAmount); end } );
				end
			else
				-- Multi-turn gold
				uiIcon = g_IconAndTextIM:GetInstance(iconList.ListStack);
				SetIconToSize(uiIcon.Icon, "ICON_YIELD_GOLD_5");
				uiIcon.IconText:LocalizeAndSetText("LOC_DIPLOMACY_DEAL_GOLD_PER_TURN");
				uiIcon.SelectButton:SetToolTipString(nil);		-- We recycle the entries, so make sure this is clear.
				uiIcon.SelectButton:RegisterCallback( Mouse.eLClick, function() OnClickAvailableMultiTurnGold(player, ms_DefaultMultiTurnGoldAmount, ms_DefaultMultiTurnGoldDuration); end );
				uiIcon.ValueText:SetHide(true);
				uiIcon.RemoveButton:SetHide(true);
				uiIcon.StopAskingButton:SetHide(true);
				uiIcon.Icon:SetColor(1,1,1);

				iconList.ListStack:CalculateSize();

				availableItemCount = availableItemCount + 1;
				SRA_AddAvail( player, { key = "gold:" .. tostring( entry.Duration ), kind = "gold", amount = ( ( entry.MaxAmount or 0 ) > 0 ) and entry.MaxAmount or nil, duration = entry.Duration,		-- ScreenReaderAccess
					hint = "Enter adds " .. ms_DefaultMultiTurnGoldAmount .. " gold per turn for " .. ms_DefaultMultiTurnGoldDuration .. " turns. Change the amount in the Deal section with Left and Right",
					callback = function() OnClickAvailableMultiTurnGold(player, ms_DefaultMultiTurnGoldAmount, ms_DefaultMultiTurnGoldDuration); end } );
			end
		end
	end

	return availableItemCount;
end

-- ===========================================================================
function OnClickAvailableBasic(itemType, player, valueType)

	if ((ms_bIsDemand == true or ms_bIsGift == true) and ms_InitiatedByPlayerID == ms_OtherPlayerID) then
		-- Can't modifiy demand that is not ours
		return;
	end

	local pDeal = DealManager.GetWorkingDeal(DealDirection.OUTGOING, g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
	if (pDeal ~= nil) then

		-- Already there?
		local pDealItem = pDeal:FindItemByValueType(itemType, DealItemSubTypes.NONE, valueType, player:GetID());
		if (pDealItem == nil) then
			-- No
			pDealItem = pDeal:AddItemOfType(itemType, player:GetID());
			if (pDealItem ~= nil) then
				pDealItem:SetValueType(valueType);
				UpdateDealPanel(player);
				UpdateProposedWorkingDeal();
			end
		end
	end
end

-- ===========================================================================
function OnClickAvailableResource(player, resourceType)

	if (ms_bIsDemand == true and ms_InitiatedByPlayerID == ms_OtherPlayerID) then
		-- Can't modifiy demand that is not ours
		return;
	end

	local pDeal : table = DealManager.GetWorkingDeal(DealDirection.OUTGOING, g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
	if (pDeal ~= nil) then

		-- Already there?
		local dealItems : table = pDeal:FindItemsByType(DealItemTypes.RESOURCES, DealItemSubTypes.NONE, player:GetID());
		local pDealItem : table;
		if (dealItems ~= nil) then
			for i, pDealItem in ipairs(dealItems) do
				if pDealItem:GetValueType() == resourceType then
					-- Check for non-zero duration.  There may already be a one-time transfer of the resource if a city is in the deal.
					if (pDealItem:GetDuration() ~= 0) then
						return;	-- Already in there.
					end
				end
			end
		end

		local pPlayerResources : table = player:GetResources();
		-- Get the total amount of the resource we have. This does not take into account anything already in the deal.
		local amount : number = pPlayerResources:GetResourceAmount( resourceType );
		if (amount > 0) then
				
			pDealItem = pDeal:AddItemOfType(DealItemTypes.RESOURCES, player:GetID());
			if (pDealItem ~= nil) then
				-- Add one
				pDealItem:SetValueType(resourceType);
				pDealItem:SetAmount(1);
				pDealItem:SetDuration(30);	-- Default to this many turns		

				-- After we add the item, test to see if the item is valid, it is possible that we have exceeded the amount of resources we can trade.
				if not pDealItem:IsValid() then
					pDeal:RemoveItemByID(pDealItem:GetID());
					pDealItem = nil;
				else
					UI.PlaySound("UI_GreatWorks_Put_Down");
				end

				UpdateDealPanel(player);
				UpdateProposedWorkingDeal();
			end
		end
	end
end

-- ===========================================================================
function OnClickAvailableAgreement(player, agreementType, agreementTurns)

	if ((ms_bIsDemand == true or ms_bIsGift == true) and ms_InitiatedByPlayerID == ms_OtherPlayerID) then
		-- Can't modifiy demand that is not ours
		return;
	end

	local pDeal = DealManager.GetWorkingDeal(DealDirection.OUTGOING, g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
	if (pDeal ~= nil) then

		-- Already there?
		local pDealItem = pDeal:FindItemByType(DealItemTypes.AGREEMENTS, agreementType, player:GetID());
		if (pDealItem == nil) then
			if (agreementType == DealAgreementTypes.JOINT_WAR or
				agreementType == DealAgreementTypes.THIRD_PARTY_WAR or
				agreementType == DealAgreementTypes.RESEARCH_AGREEMENT ) then
				ShowAgreementOptionPopup(agreementType, agreementTurns, player:GetID());
			else
				-- No
				pDealItem = pDeal:AddItemOfType(DealItemTypes.AGREEMENTS, player:GetID());
				if (pDealItem ~= nil) then
					pDealItem:SetSubType(agreementType);
					pDealItem:SetDuration(agreementTurns);

					UpdateDealPanel(player);
					UpdateProposedWorkingDeal();
					UI.PlaySound("UI_GreatWorks_Put_Down");
				end
			end
		end
	end
end

-- ===========================================================================
function OnSelectAgreementOption(agreementType, agreementTurns, agreementValue, agreementParameters, fromPlayerId)
	local pDeal = DealManager.GetWorkingDeal(DealDirection.OUTGOING, g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
	if (pDeal ~= nil) then

		-- Already there?
		local pDealItem = pDeal:FindItemByType(DealItemTypes.AGREEMENTS, agreementType, fromPlayerId);
		if (pDealItem ~= nil) then
            -- deal manager doesn't update properly unless we delete the deal item
            -- and add a new one.
			if (not pDealItem:IsLocked()) then
                local itemID = pDealItem:GetID();
                DetachValueEdit(itemID);
				pDeal:RemoveItemByID(itemID);
                pDealItem = pDeal:AddItemOfType(DealItemTypes.AGREEMENTS, fromPlayerId);
            end
        else
            pDealItem = pDeal:AddItemOfType(DealItemTypes.AGREEMENTS, fromPlayerId);
		end

        if (pDealItem ~= nil) then
            pDealItem:SetSubType(agreementType);
            pDealItem:SetDuration(agreementTurns);
            pDealItem:SetValueType(agreementValue);

            if (agreementType == DealAgreementTypes.JOINT_WAR or
                agreementType == DealAgreementTypes.THIRD_PARTY_WAR) then
                pDealItem:SetParameterValue("WarType", agreementParameters.WarType);
            end

    		UpdateDealPanel(g_LocalPlayer);
    		UpdateProposedWorkingDeal();
    		UI.PlaySound("UI_GreatWorks_Put_Down");
        end

   		Controls.ValueEditPopupBackground:SetHide(true);
	end
end

-- ===========================================================================
function ShowAgreementOptionPopup(agreementType, agreementTurns, fromPlayerId)

	-- Hide/show everything for AGREEMENTS options
	ms_AgreementOptionIM:ResetInstances();
	m_srOptions = {};		-- ScreenReaderAccess
	Controls.ValueEditIconGrid:SetHide(true);
	Controls.ValueAmountEditBoxContainer:SetHide(true);

    -- don't update when backing out of this
    ms_bDontUpdateOnBack = true;

	if agreementType == DealAgreementTypes.RESEARCH_AGREEMENT then
		Controls.ValueEditHeaderLabel:SetText(Locale.Lookup("LOC_DIPLOMACY_DEAL_SELECT_TECH"));
	elseif agreementType == DealAgreementTypes.ALLIANCE then
		Controls.ValueEditHeaderLabel:SetText(Locale.Lookup("LOC_DIPLOMACY_DEAL_SELECT_ALLIANCE"));
	else
		Controls.ValueEditHeaderLabel:SetText(Locale.Lookup("LOC_DIPLOMACY_DEAL_SELECT_TARGET"));
	end

	local toPlayerId = g_LocalPlayer:GetID();
	if (toPlayerId == fromPlayerId ) then
		toPlayerId = g_OtherPlayer:GetID();
	end
	local pForDeal = DealManager.GetWorkingDeal(DealDirection.OUTGOING, g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
	local possibleValues = DealManager.GetPossibleDealItems(fromPlayerId, toPlayerId, DealItemTypes.AGREEMENTS, agreementType, pForDeal);
	if (possibleValues ~= nil) then
		for i, entry in ipairs(possibleValues) do
			local instance:table = ms_AgreementOptionIM:GetInstance();

			local szDisplayName = "";
			local szItemName = Locale.Lookup(entry.ForTypeDisplayName);
			if (entry.SubType == DealAgreementTypes.RESEARCH_AGREEMENT) then
				local eTech = GameInfo.Technologies[entry.ForType].Index;
				local iTurns = 	g_LocalPlayer:GetDiplomacy():ComputeResearchAgreementTurns(g_OtherPlayer, eTech);
				szDisplayName = Locale.Lookup("LOC_DIPLOMACY_DEAL_PARAMETER_WITH_TURNS", szItemName, iTurns);
				instance.AgreementOptionIcon:SetIcon("ICON_" .. entry.ForTypeName);
				instance.AgreementOptionIcon:SetHide(false);
			else
				if (entry.SubType == DealAgreementTypes.JOINT_WAR or
					entry.SubType == DealAgreementTypes.THIRD_PARTY_WAR) then
					szDisplayName = szItemName;

					-- Have a type of war that describes the joint war?
					if entry.Parameters ~= nil then
						if entry.Parameters.WarType ~= nil then
							local warDef = GameInfo.Wars[entry.Parameters.WarType];
							if warDef ~= nil then
								szDisplayName = szDisplayName .. "[newline]" .. Locale.Lookup(warDef.Name);
							end
						end
					end

					instance.AgreementOptionIcon:SetHide(true);
				else
					szDisplayName = szItemName;
					instance.AgreementOptionIcon:SetHide(true);
				end
			end

			instance.AgreementOptionLabel:SetText(szDisplayName);

			if agreementType == DealAgreementTypes.ALLIANCE then
				local allianceLevel:number = g_LocalPlayer:GetDiplomacy():GetAllianceLevel(g_OtherPlayer);
				local allianceData:table = GameInfo.Alliances[entry.ForTypeName];
				local tooltip = Game.GetGameDiplomacy():GetAllianceBenefitsString(allianceData.Index, allianceLevel, true);
				instance.AgreementOptionButton:SetToolTipString(tooltip);
			else
				instance.AgreementOptionButton:SetToolTipString("");
			end

			local agreementValueType = entry.ForType;
			local agreementParameters = entry.Parameters;
			instance.AgreementOptionButton:RegisterCallback(Mouse.eLClick, function()
				OnSelectAgreementOption(agreementType, agreementTurns, agreementValueType, agreementParameters, fromPlayerId);
			end);
			-- Begin ScreenReaderAccess change
			table.insert( m_srOptions, { key = "opt:" .. tostring( i ), text = szDisplayName, tooltip = ( agreementType == DealAgreementTypes.ALLIANCE ) and instance.AgreementOptionButton:GetToolTipString() or nil,
				callback = function() OnSelectAgreementOption(agreementType, agreementTurns, agreementValueType, agreementParameters, fromPlayerId); end } );
			-- End ScreenReaderAccess change

			Controls.ValueEditButton:RegisterCallback( Mouse.eLClick, OnAgreementBackButton );
		end
	end

	Controls.ValueEditIconGrid:DoAutoSize();

	ResizeValueEditScrollPanel();

	Controls.ValueEditPopup:DoAutoSize();
	Controls.ValueEditPopupBackground:SetHide(false);
end

-- ===========================================================================
function ResizeValueEditScrollPanel()
	-- Resize scroll panel to a maximum height of five agreement options
	Controls.ValueEditStack:CalculateSize();
	if Controls.ValueEditStack:GetSizeY() > MAX_DEAL_ITEM_EDIT_HEIGHT then
		Controls.ValueEditScrollPanel:SetSizeY(MAX_DEAL_ITEM_EDIT_HEIGHT);
	else
		Controls.ValueEditScrollPanel:SetSizeY(Controls.ValueEditStack:GetSizeY());
	end
	Controls.ValueEditScrollPanel:CalculateSize();
end

-- ===========================================================================
function OnAgreementBackButton()
    if not ms_bDontUpdateOnBack then
        UpdateDealPanel(g_LocalPlayer);
        UpdateProposedWorkingDeal();
    end
    ms_bDontUpdateOnBack = false;
	Controls.ValueEditPopupBackground:SetHide(true);
end

-- ===========================================================================
function OnClickAvailableGreatWork(player, valueType, greatWorkType)
	if ((ms_bIsDemand == true or ms_bIsGift == true) and ms_InitiatedByPlayerID == ms_OtherPlayerID) then
		-- Can't modifiy demand that is not ours
		return;
	end

	local pDeal = DealManager.GetWorkingDeal(DealDirection.OUTGOING, g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
	if (pDeal ~= nil) then

		-- Already there?
		local pDealItem = pDeal:FindItemByValueType(DealItemTypes.GREATWORK, DealItemSubTypes.NONE, valueType, player:GetID());
		if (pDealItem == nil) then
			-- No
			pDealItem = pDeal:AddItemOfType(DealItemTypes.GREATWORK, player:GetID());
			if (pDealItem ~= nil) then
				pDealItem:SetSubType(greatWorkType);
				pDealItem:SetValueType(valueType);
				UpdateDealPanel(player);
				UpdateProposedWorkingDeal();
			end
		end
	end
	UI.PlaySound("UI_GreatWorks_Put_Down");

end

-- ===========================================================================
function OnClickAvailableCaptive(player, type)

	OnClickAvailableBasic(DealItemTypes.CAPTIVE, player, type);
	UI.PlaySound("UI_GreatWorks_Put_Down");

end

-- ===========================================================================
function OnClickAvailableCity(player, valueType, subType)

	if ((ms_bIsDemand == true or ms_bIsGift == true) and ms_InitiatedByPlayerID == ms_OtherPlayerID) then
		-- Can't modifiy demand that is not ours
		return;
	end

	local pDeal = DealManager.GetWorkingDeal(DealDirection.OUTGOING, g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
	if (pDeal ~= nil) then

		-- Already there?
		local pDealItem = pDeal:FindItemByValueType(DealItemTypes.CITIES, subType, valueType, player:GetID());
		if (pDealItem == nil) then
			-- No
			local otherPlayerID = g_OtherPlayer:GetID();
			if (otherPlayerID == player:GetID()) then
				otherPlayerID = g_LocalPlayer:GetID();
			end

			pDealItem = pDeal:AddItemOfType(DealItemTypes.CITIES, player:GetID(), otherPlayerID, subType, valueType);
			if (pDealItem ~= nil) then
				pDealItem:SetSubType(subType);
				pDealItem:SetValueType(valueType);
				if (not pDealItem:IsValid(pDeal)) then
					pDeal:RemoveItemByID(pDealItem:GetID());
				end
				UpdateDealPanel(player);
				UpdateProposedWorkingDeal();
			end
		end
	end

	UI.PlaySound("UI_GreatWorks_Put_Down");

end

-- ===========================================================================
function OnRemoveDealItem(player, itemID)

	if (ms_bIsDemand == true and ms_InitiatedByPlayerID == ms_OtherPlayerID) then
		-- Can't remove it
		return;
	end

	DetachValueEdit(itemID);

	local pDeal = DealManager.GetWorkingDeal(DealDirection.OUTGOING, g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
	if (pDeal ~= nil) then

		local pDealItem = pDeal:FindItemByID(itemID);
		if (pDealItem ~= nil) then
			if (not pDealItem:IsLocked()) then
				if (pDeal:RemoveItemByID(itemID)) then
					UpdateDealPanel(player);
					UpdateProposedWorkingDeal();
					UI.PlaySound("UI_GreatWorks_Pick_Up");
				end
			end
		end
	end
end

-- ===========================================================================
function OnSetDealItemUnacceptable(itemID : number)
	m_kPopupDialog:Close(); -- Close and reset the popup in case it's open

	m_kPopupDialog:AddText(Locale.Lookup("LOC_DIPLO_DEAL_STOP_ASKING_POPUP_TEXT"));
	m_kPopupDialog:AddTitle(Locale.ToUpper(Locale.Lookup("LOC_DIPLO_DEAL_STOP_ASKING_POPUP_TITLE")))
	m_kPopupDialog:AddButton(Locale.Lookup("LOC_OK_BUTTON"), function() OnConfirmSetDealItemUnacceptable(itemID); end);
	m_kPopupDialog:AddButton(Locale.Lookup("LOC_NO_BUTTON"), function() m_kPopupDialog:Close(); end);

	m_kPopupDialog:Open();
end

-- ===========================================================================
function OnConfirmSetDealItemUnacceptable(itemID : number)
	local pDeal : table = DealManager.GetWorkingDeal(DealDirection.OUTGOING, g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
	pDeal:SetUnacceptableItemByID(itemID);
	DealManager.SendWorkingDeal(DealProposalAction.INSPECT, g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
	UpdateDealPanel();
end

-- ===========================================================================
function OnSelectValueDealItem(player, itemID, controlInstance)

	if (ms_bIsDemand == true and ms_InitiatedByPlayerID == ms_OtherPlayerID) then
		-- Can't edit it
		return;
	end

	if (controlInstance ~= nil) then
		AttachValueEdit(controlInstance, itemID);
	end
end

-- ===========================================================================
function OnValueEditButton(itemID)
	local pDeal = DealManager.GetWorkingDeal(DealDirection.OUTGOING, g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
	if pDeal then
		local pDealItem = pDeal:FindItemByID(itemID);
		if pDealItem then
			local newAmount:number = tonumber(Controls.ValueAmountEditBox:GetText());
			newAmount = clip(newAmount, 1, pDealItem:GetMaxAmount());

			if (newAmount ~= pDealItem:GetAmount()) then
				local subtype = pDealItem:GetSubType();
				local duration = pDealItem:GetDuration();
				local valueType = pDealItem:GetValueType();
				local fromPlayerId = pDealItem:GetFromPlayerID();
				local type = pDealItem:GetType();
                if (not pDealItem:IsLocked()) then
                    DetachValueEdit(itemID);
                    pDeal:RemoveItemByID(itemID);
                    pDealItem = pDeal:AddItemOfType(type, fromPlayerId);
                    pDealItem:SetSubType(subtype);
                    pDealItem:SetDuration(duration);
                    pDealItem:SetValueType(valueType);
                end

				pDealItem:SetAmount(newAmount);
				ms_bForceUpdateOnCommit = true;
				UpdateProposedWorkingDeal();
			end

			if g_ValueEditDealItemControlTable then
				g_ValueEditDealItemControlTable.AmountText:SetText(newAmount);
				g_ValueEditDealItemControlTable.AmountText:SetHide(false);
			end
			UpdateDealStatus();
			UpdateDealPanel(g_LocalPlayer);
		end
	end

	Controls.ValueEditPopupBackground:SetHide(true);
end

-- ===========================================================================
function PopulateAvailableResources(player : table, iconList : table, className : string)

	local availableItemCount : number = 0;
	local pForDeal : table = DealManager.GetWorkingDeal(DealDirection.OUTGOING, g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
	local possibleResources : table = DealManager.GetPossibleDealItems(player:GetID(), GetOtherPlayer(player):GetID(), DealItemTypes.RESOURCES, pForDeal);
	if (possibleResources ~= nil) then
		for i, entry in ipairs(possibleResources) do
	
			local resourceDesc : table = GameInfo.Resources[entry.ForType];
			if (resourceDesc ~= nil) then
				-- Do we have some and is it a luxury item?
				if (entry.MaxAmount > 0 and resourceDesc.ResourceClassType == className ) then
					local uiIcon : table = g_IconOnlyIM:GetInstance(iconList.ListStack);
					SetIconToSize(uiIcon.Icon, "ICON_" .. resourceDesc.ResourceType);
					uiIcon.AmountText:SetText(tostring(entry.MaxAmount));
					uiIcon.AmountText:SetHide(false);
					uiIcon.RemoveButton:SetHide(true);
					uiIcon.StopAskingButton:SetHide(true);
					uiIcon.Icon:SetColor(1,1,1);

					local resourceType : number = entry.ForType;
					-- What to do when double clicked/tapped.
					uiIcon.SelectButton:RegisterCallback( Mouse.eLClick, function() OnClickAvailableResource(player, resourceType); end );
					-- Set a tool tip
					if entry.IsValid then
						uiIcon.SelectButton:LocalizeAndSetToolTip(resourceDesc.Name);
                        uiIcon.SelectButton:SetDisabled(false);
					else
                        local tempstr : string = Locale.Lookup(resourceDesc.Name).."[NEWLINE][COLOR_RED]";
					    if player ~= g_LocalPlayer then
                            tempstr = tempstr .. Locale.Lookup("LOC_DEAL_PLAYER_HAS_NO_CAP_ROOM");
	                        uiIcon.SelectButton:SetToolTipString(tempstr);
						else
                            tempstr = tempstr .. Locale.Lookup("LOC_DEAL_AI_HAS_NO_CAP_ROOM");
	                        uiIcon.SelectButton:SetToolTipString(tempstr);
						end
                        uiIcon.SelectButton:SetDisabled(true);
						uiIcon.Icon:SetColor(0.5, 0.5, 0.5);
					end

					-- Begin ScreenReaderAccess change
					local srRec:table = { key = "res:" .. resourceType, kind = "resource", name = Locale.Lookup( resourceDesc.Name ), amount = entry.MaxAmount,
						class = ( className == "RESOURCECLASS_LUXURY" ) and "Luxury" or ( ( className == "RESOURCECLASS_STRATEGIC" ) and "Strategic" or nil ),
						enabled = entry.IsValid, callback = function() OnClickAvailableResource(player, resourceType); end };
					if not entry.IsValid then
						srRec.reason = Locale.Lookup( ( player:GetID() ~= g_LocalPlayer:GetID() ) and "LOC_DEAL_PLAYER_HAS_NO_CAP_ROOM" or "LOC_DEAL_AI_HAS_NO_CAP_ROOM" );
					end
					local pOtherResources:table = GetOtherPlayer( player ):GetResources();
					if pOtherResources ~= nil and pOtherResources:GetResourceAmount( resourceType ) <= 0 then
						srRec.otherNone = ( player:GetID() == g_LocalPlayer:GetID() ) and "they" or "you";
					end
					SRA_AddAvail( player, srRec );
					-- End ScreenReaderAccess change

					availableItemCount = availableItemCount + 1;
				end
			end
		end

		iconList.ListStack:CalculateSize();
	end

	-- Hide if empty
	iconList.GetTopControl():SetHide( iconList.ListStack:GetSizeX()==0 );

	return availableItemCount;
end

-- ===========================================================================
function PopulateAvailableLuxuryResources(player : table, iconList : table)

	local availableItemCount : number = 0;
	availableItemCount = availableItemCount + PopulateAvailableResources(player, iconList, "RESOURCECLASS_LUXURY");
	return availableItemCount;
end

-- ===========================================================================
function PopulateAvailableStrategicResources(player : table, iconList : table)

	local availableItemCount : number = 0;
	availableItemCount = availableItemCount + PopulateAvailableResources(player, iconList, "RESOURCECLASS_STRATEGIC");
	return availableItemCount; 
end

-- ===========================================================================
function PopulateAvailableAgreements(player : table, iconList : table)

	local availableItemCount : number = 0;
	local pForDeal : table = DealManager.GetWorkingDeal(DealDirection.OUTGOING, g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
	local possibleAgreements : table = DealManager.GetPossibleDealItems(player:GetID(), GetOtherPlayer(player):GetID(), DealItemTypes.AGREEMENTS, pForDeal);
	local uiMinimizedSection : table = ms_MinimizedSectionIM:GetInstance(iconList.List);

	if (possibleAgreements ~= nil) then
		for i, entry in ipairs(possibleAgreements) do
			local agreementType : number = entry.SubType;

			local agreementDuration : number = entry.Duration;
			local uiIcon : table = g_IconAndTextIM:GetInstance(iconList.ListStack);
			local uiMinimizedIcon : table = g_IconOnlyIM:GetInstance(uiMinimizedSection.MinimizedSectionStack);

			local info: table = GameInfo.DiplomaticActions[ agreementType ];
			if (info ~= nil) then
				SetIconToSize(uiIcon.Icon, "ICON_".. info.DiplomaticActionType, 38);
				SetIconToSize(uiMinimizedIcon.Icon, "ICON_".. info.DiplomaticActionType, 38);
			end
			uiIcon.AmountText:SetHide(true);
			uiIcon.IconText:LocalizeAndSetText(entry.SubTypeName);
			uiIcon.SelectButton:SetDisabled( not entry.IsValid and entry.ValidationResult ~= DealValidationResult.MISSING_DEPENDENCY );	-- Hide if invalid, unless it is just missing a dependency, the user will update that when it is added to the deal.
			uiIcon.ValueText:SetHide(true);
			uiIcon.RemoveButton:SetHide(true);
			uiIcon.StopAskingButton:SetHide(true);

			uiMinimizedIcon.AmountText:SetHide(true);
			uiMinimizedIcon.SelectButton:SetDisabled( not entry.IsValid and entry.ValidationResult ~= DealValidationResult.MISSING_DEPENDENCY );	-- Hide if invalid, unless it is just missing a dependency, the user will update that when it is added to the deal.
			uiMinimizedIcon.RemoveButton:SetHide(true);
			uiMinimizedIcon.StopAskingButton:SetHide(true);
			uiMinimizedIcon.Icon:SetColor(1,1,1);

			-- What to do when double clicked/tapped.
			uiIcon.SelectButton:RegisterCallback( Mouse.eLClick, function() OnClickAvailableAgreement(player, agreementType, agreementDuration); end );
			uiMinimizedIcon.SelectButton:RegisterCallback( Mouse.eLClick, function() OnClickAvailableAgreement(player, agreementType, agreementDuration); end );

			-- Set a tool tip if their is a duration
			local szTooltip : string;
			if (entry.Duration > 0) then
				szTooltip = Locale.Lookup("LOC_DIPLOMACY_DEAL_PARAMETER_WITH_TURNS", entry.SubTypeName, entry.Duration);
				uiIcon.SelectButton:SetToolTipString(szTooltip);
			else
				szTooltip = Locale.Lookup(entry.SubTypeName);
				uiIcon.SelectButton:SetToolTipString(nil);
			end
			uiMinimizedIcon.SelectButton:SetToolTipString(szTooltip);

			-- Begin ScreenReaderAccess change
			local srDisabled:boolean = SRA_IsAvailableDisabled( entry );
			SRA_AddAvail( player, { key = "agr:" .. agreementType, kind = "agreement", name = Locale.Lookup( entry.SubTypeName ), duration = agreementDuration,
				enabled = not srDisabled, reason = srDisabled and SRA_InvalidReason( entry ) or nil, tooltip = szTooltip,
				callback = function() OnClickAvailableAgreement(player, agreementType, agreementDuration); end } );
			-- End ScreenReaderAccess change

			availableItemCount = availableItemCount + 1;
		end

		iconList.ListStack:CalculateSize();
	end

	uiMinimizedSection.MinimizedSectionContainer:SetHide(iconList.ListStack:IsVisible());
	iconList.HeaderExpandButton:RegisterCallback(Mouse.eLClick, function() OnDealsHeaderCollapseButton(iconList.ListStack, uiMinimizedSection.MinimizedSectionContainer, iconList.HeaderExpandButton); end);
	iconList.HeaderExpandButton:SetHide(table.count(iconList.ListStack:GetChildren()) == 1);

	-- Hide if empty
	iconList.GetTopControl():SetHide( iconList.ListStack:GetSizeX()==0 );

	return availableItemCount;
end

-- ===========================================================================
function MakeCityToolTip(player : table, cityID : number)
	local pCity = player:GetCities():FindID( cityID );
	if (pCity == nil) then	
		UI.DataError("Unable to find city object to make tooltip for cityID: "..tostring(cityID));
		return "";
	end

	local szToolTip : string = Locale.Lookup("LOC_DEAL_CITY_POPULATION_TOOLTIP", pCity:GetPopulation());
	local districtNames : table = {};
	local pCityDistricts : table = pCity:GetDistricts();
	if (pCityDistricts ~= nil) then

		for i, pDistrict in pCityDistricts:Members() do
			local pDistrictDef = GameInfo.Districts[ pDistrict:GetType() ];
			if (pDistrictDef ~= nil) then
				local districtType:string = pDistrictDef.DistrictType;
				-- Skip the city center and any wonder districts
				if (districtType ~= "DISTRICT_CITY_CENTER" and districtType ~= "DISTRICT_WONDER") then
					local iconAndName : string = Locale.Lookup("[ICON_"..pDistrictDef.PrimaryKey.."]")..Locale.Lookup(pDistrictDef.Name);
					table.insert(districtNames, iconAndName);
				end
			end
		end
	end

	if (#districtNames > 0) then
		szToolTip = szToolTip .."[NEWLINE]  -----------------------" .. "[NEWLINE]" .. Locale.Lookup("LOC_DEAL_CITY_DISTRICTS_TOOLTIP");
		for i, name in ipairs(districtNames) do
			szToolTip = szToolTip .. "[NEWLINE]" .. Locale.Lookup(name);
		end
	end

	-- Add Resources
	local extractedResources = player:GetResources():GetResourcesExtractedByCity( cityID, ResultFormat.SUMMARY );
	if extractedResources ~= nil and #extractedResources > 0 then
		szToolTip = szToolTip .. "[NEWLINE]  -----------------------" .. "[NEWLINE]" .. Locale.Lookup("LOC_DEAL_CITY_RESOURCES_TOOLTIP");
		for i, entry in ipairs(extractedResources) do
			local resourceDesc = GameInfo.Resources[entry.ResourceType];
			if resourceDesc ~= nil then
				szToolTip = szToolTip .. "[NEWLINE]" .. Locale.Lookup(resourceDesc.Name) .. " : " .. tostring(entry.Amount);
			end
		end
	end

	-- Add Great Works
	local cityGreatWorks = player:GetCulture():GetGreatWorksInCity( cityID );
	if cityGreatWorks ~= nil and #cityGreatWorks > 0 then
		szToolTip = szToolTip .. "[NEWLINE]  -----------------------" .. "[NEWLINE]" .. Locale.Lookup("LOC_DEAL_CITY_GREAT_WORKS_TOOLTIP");
		for i, entry in ipairs(cityGreatWorks) do
			local greatWorksDesc = GameInfo.GreatWorks[entry.GreatWorksType];
			if greatWorksDesc ~= nil then
				szToolTip = szToolTip .. "[NEWLINE]" .. Locale.Lookup(greatWorksDesc.Name);
			end
		end
	end

	return szToolTip;	
end

-- ===========================================================================
function PopulateAvailableCities(player : table, iconList : table)

	local availableItemCount : number = 0;
	local pForDeal : table = DealManager.GetWorkingDeal(DealDirection.OUTGOING, g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
	local possibleItems : table = DealManager.GetPossibleDealItems(player:GetID(), GetOtherPlayer(player):GetID(), DealItemTypes.CITIES, pForDeal);
	local uiMinimizedSection : table = ms_MinimizedSectionIM:GetInstance(iconList.List);

	if (possibleItems ~= nil) then
		for i, entry in ipairs(possibleItems) do

			local type : number = entry.ForType;
			local subType : number = entry.SubType;
			local uiIcon : table = g_IconAndTextIM:GetInstance(iconList.ListStack);
			local uiMinimizedIcon : table = g_IconOnlyIM:GetInstance(uiMinimizedSection.MinimizedSectionStack);

			SetIconToSize(uiIcon.Icon, "ICON_BUILDINGS", 45);
			SetIconToSize(uiMinimizedIcon.Icon, "ICON_BUILDINGS", 45);

			uiIcon.AmountText:SetHide(true);
			uiIcon.IconText:LocalizeAndSetText(entry.ForTypeName);
			uiIcon.SelectButton:SetDisabled( not entry.IsValid and entry.ValidationResult ~= DealValidationResult.MISSING_DEPENDENCY );	-- Hide if invalid, unless it is just missing a dependency, the user will update that when it is added to the deal.
			uiIcon.ValueText:SetHide(true);
			uiIcon.RemoveButton:SetHide(true);
			uiIcon.StopAskingButton:SetHide(true);

			uiMinimizedIcon.AmountText:SetHide(true);
			uiMinimizedIcon.SelectButton:SetDisabled( not entry.IsValid and entry.ValidationResult ~= DealValidationResult.MISSING_DEPENDENCY );	-- Hide if invalid, unless it is just missing a dependency, the user will update that when it is added to the deal.
			uiMinimizedIcon.RemoveButton:SetHide(true);
			uiMinimizedIcon.StopAskingButton:SetHide(true);
			uiMinimizedIcon.Icon:SetColor(1,1,1);

			-- What to do when double clicked/tapped.
			uiIcon.SelectButton:RegisterCallback( Mouse.eLClick, function() OnClickAvailableCity(player, type, subType); end );
			uiMinimizedIcon.SelectButton:RegisterCallback( Mouse.eLClick, function() OnClickAvailableCity(player, type, subType); end );

			-- Since we're ceding this city make sure to look for this city in the current owners city list
			if entry.SubType == 1 then -- CitySubTypes:CEDE_OCCUPIED
				uiIcon.SelectButton:SetToolTipString( MakeCityToolTip(GetOtherPlayer(player), type) );
				uiMinimizedIcon.SelectButton:SetToolTipString(Locale.Lookup(entry.ForTypeName).."[NEWLINE]"..MakeCityToolTip(GetOtherPlayer(player), type ));
			else
				uiIcon.SelectButton:SetToolTipString( MakeCityToolTip(player, type) );
				uiMinimizedIcon.SelectButton:SetToolTipString(Locale.Lookup(entry.ForTypeName).."[NEWLINE]"..MakeCityToolTip(player, type ));
			end

			-- Begin ScreenReaderAccess change
			local srDisabled:boolean = SRA_IsAvailableDisabled( entry );
			SRA_AddAvail( player, { key = "city:" .. type .. ":" .. subType, kind = "city", name = Locale.Lookup( entry.ForTypeName ),
				enabled = not srDisabled, reason = srDisabled and SRA_InvalidReason( entry ) or nil,
				tooltip = function() return MakeCityToolTip( ( subType == 1 ) and GetOtherPlayer( player ) or player, type ); end,
				callback = function() OnClickAvailableCity(player, type, subType); end } );
			-- End ScreenReaderAccess change

			availableItemCount = availableItemCount + 1;
		end

		iconList.ListStack:CalculateSize();
	end

	uiMinimizedSection.MinimizedSectionContainer:SetHide(iconList.ListStack:IsVisible());
	iconList.HeaderExpandButton:RegisterCallback(Mouse.eLClick, function() OnDealsHeaderCollapseButton(iconList.ListStack, uiMinimizedSection.MinimizedSectionContainer, iconList.HeaderExpandButton); end);
	iconList.HeaderExpandButton:SetHide(table.count(iconList.ListStack:GetChildren()) == 1);

	-- Hide if empty
	iconList.GetTopControl():SetHide( iconList.ListStack:GetSizeX()==0 );

	return availableItemCount;
end

-- ===========================================================================
function PopulateAvailableOtherPlayers(player : table, iconList : table)

	local availableItemCount : number = 0;
	-- Hide if empty
	iconList.GetTopControl():SetHide( iconList.ListStack:GetSizeX()==0 );

	return availableItemCount;
end

-- ===========================================================================
function GetGreatWorkIcon(GreatWorkDesc : table, GreatWorkBackupString : string)
	return "ICON_" .. GreatWorkBackupString;
end

-- ===========================================================================
function GetGreatWorkTooltip(GreatWorkDesc : table, defaultToolTip : string)
	return defaultToolTip;
end

-- ===========================================================================
function PopulateAvailableGreatWorks(player : table, iconList : table)

	local availableItemCount : number = 0;
	local pForDeal : table = DealManager.GetWorkingDeal(DealDirection.OUTGOING, g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
	local possibleItems : table = DealManager.GetPossibleDealItems(player:GetID(), GetOtherPlayer(player):GetID(), DealItemTypes.GREATWORK, pForDeal);
	local uiMinimizedSection : table = ms_MinimizedSectionIM:GetInstance(iconList.List);

	if (possibleItems ~= nil) then
		for i, entry in ipairs(possibleItems) do
			local greatWorkDesc : table = GameInfo.GreatWorks[entry.ForTypeDescriptionID];
			if (greatWorkDesc ~= nil) then
				local type : number = entry.ForType;
				local uiIcon : table = g_IconAndTextIM:GetInstance(iconList.ListStack);
				local uiMinimizedIcon : table = g_IconOnlyIM:GetInstance(uiMinimizedSection.MinimizedSectionStack);
				local iconName : string = GetGreatWorkIcon(greatWorkDesc, greatWorkDesc.GreatWorkType);

				SetIconToSize(uiIcon.Icon, iconName, 45);
				SetIconToSize(uiMinimizedIcon.Icon, iconName, 45);

				uiIcon.AmountText:SetHide(true);
				uiIcon.IconText:LocalizeAndSetText(entry.ForTypeName);
				uiIcon.SelectButton:SetDisabled( not entry.IsValid and entry.ValidationResult ~= DealValidationResult.MISSING_DEPENDENCY );	-- Hide if invalid, unless it is just missing a dependency, the user will update that when it is added to the deal.
				uiIcon.ValueText:SetHide(true);
				uiIcon.RemoveButton:SetHide(true);
				uiIcon.StopAskingButton:SetHide(true);

				uiMinimizedIcon.AmountText:SetHide(true);
				uiMinimizedIcon.SelectButton:SetDisabled( not entry.IsValid and entry.ValidationResult ~= DealValidationResult.MISSING_DEPENDENCY );	-- Hide if invalid, unless it is just missing a dependency, the user will update that when it is added to the deal.
				uiMinimizedIcon.RemoveButton:SetHide(true);
				uiMinimizedIcon.StopAskingButton:SetHide(true);
				uiMinimizedIcon.Icon:SetColor(1,1,1);

				-- What to do when double clicked/tapped.
				uiIcon.SelectButton:RegisterCallback( Mouse.eLClick, function() OnClickAvailableGreatWork(player, type, entry.ForTypeDescriptionID); end );
				uiMinimizedIcon.SelectButton:RegisterCallback( Mouse.eLClick, function() OnClickAvailableGreatWork(player, type, entry.ForTypeDescriptionID); end );
				-- Set a tool tip
				
				local greatWorkTooltip : string = GetGreatWorkTooltip(greatWorkDesc, GreatWorksSupport_GetBasicTooltip(entry.ForType, false));
				uiIcon.SelectButton:SetToolTipString(greatWorkTooltip);

				local minimizedTooltip : string = Locale.Lookup(entry.ForTypeName) .. "[NEWLINE]"..greatWorkTooltip;
				uiMinimizedIcon.SelectButton:SetToolTipString(minimizedTooltip);

				-- Begin ScreenReaderAccess change
				local srDisabled:boolean = SRA_IsAvailableDisabled( entry );
				SRA_AddAvail( player, { key = "gw:" .. type, kind = "greatwork", name = Locale.Lookup( entry.ForTypeName ),
					enabled = not srDisabled, reason = srDisabled and SRA_InvalidReason( entry ) or nil, tooltip = greatWorkTooltip,
					callback = function() OnClickAvailableGreatWork(player, type, entry.ForTypeDescriptionID); end } );
				-- End ScreenReaderAccess change

				availableItemCount = availableItemCount + 1;
			end
		end

		iconList.ListStack:CalculateSize();
	end

	uiMinimizedSection.MinimizedSectionContainer:SetHide(iconList.ListStack:IsVisible());
	iconList.HeaderExpandButton:RegisterCallback(Mouse.eLClick, function() OnDealsHeaderCollapseButton(iconList.ListStack, uiMinimizedSection.MinimizedSectionContainer, iconList.HeaderExpandButton); end);
	iconList.HeaderExpandButton:SetHide( table.count(iconList.ListStack:GetChildren()) == 1 );

	-- Hide if empty
	iconList.GetTopControl():SetHide( iconList.ListStack:GetSizeX()==0 );

	return availableItemCount;

end

-- ===========================================================================
function PopulateAvailableCaptives(player : table, iconList : table)

	local availableItemCount : number = 0;

	local pForDeal : table = DealManager.GetWorkingDeal(DealDirection.OUTGOING, g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
	local possibleItems : table = DealManager.GetPossibleDealItems(player:GetID(), GetOtherPlayer(player):GetID(), DealItemTypes.CAPTIVE, pForDeal);
	local uiMinimizedSection : table = ms_MinimizedSectionIM:GetInstance(iconList.List);

	if (possibleItems ~= nil) then
		for i, entry in ipairs(possibleItems) do

			local type : number = entry.ForType;
			local uiIcon : table = g_IconAndTextIM:GetInstance(iconList.ListStack);
			local uiMinimizedIcon : table = g_IconOnlyIM:GetInstance(uiMinimizedSection.MinimizedSectionStack);

			SetIconToSize(uiIcon.Icon, "ICON_UNIT_SPY");
			SetIconToSize(uiMinimizedIcon.Icon, "ICON_UNIT_SPY");

			uiIcon.AmountText:SetHide(true);
			if (entry.ForTypeName ~= nil ) then
				uiIcon.IconText:LocalizeAndSetText(entry.ForTypeName);
				uiMinimizedIcon.SelectButton:LocalizeAndSetToolTip(entry.ForTypeName);
			end
			uiIcon.SelectButton:SetDisabled( not entry.IsValid and entry.ValidationResult ~= DealValidationResult.MISSING_DEPENDENCY );	-- Hide if invalid, unless it is just missing a dependency, the user will update that when it is added to the deal.
			uiIcon.ValueText:SetHide(true);
			uiIcon.RemoveButton:SetHide(true);
			uiIcon.StopAskingButton:SetHide(true);

			uiMinimizedIcon.AmountText:SetHide(true);
			uiMinimizedIcon.SelectButton:SetDisabled( not entry.IsValid and entry.ValidationResult ~= DealValidationResult.MISSING_DEPENDENCY );	-- Hide if invalid, unless it is just missing a dependency, the user will update that when it is added to the deal.
			uiMinimizedIcon.RemoveButton:SetHide(true);
			uiMinimizedIcon.StopAskingButton:SetHide(true);
			uiMinimizedIcon.Icon:SetColor(1,1,1);

			-- What to do when double clicked/tapped.
			uiIcon.SelectButton:RegisterCallback( Mouse.eLClick, function() OnClickAvailableCaptive(player, type); end );
			uiMinimizedIcon.SelectButton:RegisterCallback( Mouse.eLClick, function() OnClickAvailableCaptive(player, type); end );

			uiIcon.SelectButton:SetToolTipString(nil);		-- We recycle the entries, so make sure this is clear.

			-- Begin ScreenReaderAccess change
			local srDisabled:boolean = SRA_IsAvailableDisabled( entry );
			SRA_AddAvail( player, { key = "cap:" .. type, kind = "captive", name = ( entry.ForTypeName ~= nil ) and Locale.Lookup( entry.ForTypeName ) or "Captive",
				enabled = not srDisabled, reason = srDisabled and SRA_InvalidReason( entry ) or nil,
				callback = function() OnClickAvailableCaptive(player, type); end } );
			-- End ScreenReaderAccess change

			availableItemCount = availableItemCount + 1;
		end

		iconList.ListStack:CalculateSize();
	end

	uiMinimizedSection.MinimizedSectionContainer:SetHide(iconList.ListStack:IsVisible());
	iconList.HeaderExpandButton:RegisterCallback(Mouse.eLClick, function() OnDealsHeaderCollapseButton(iconList.ListStack, uiMinimizedSection.MinimizedSectionContainer, iconList.HeaderExpandButton); end);
	iconList.HeaderExpandButton:SetHide( table.count(iconList.ListStack:GetChildren()) == 1 );

	-- Hide if empty
	iconList.GetTopControl():SetHide( iconList.ListStack:GetSizeX()==0 );

	return availableItemCount;
end

-- ===========================================================================
function PopulatePlayerAvailablePanel(rootControl : table, player : table)

	local availableItemCount : number = 0;

	if (player ~= nil) then
	
		local playerType : number = GetPlayerType(player);
		if (ms_bIsDemand and player:GetID() == ms_InitiatedByPlayerID) then
			-- This is a demand, so hide all the demanding player's items
			for i = 1, table.count(AvailableDealItemGroupTypes), 1 do
				g_AvailableGroups[i][playerType].GetTopControl():SetHide(true);
			end
		else
			g_AvailableGroups[AvailableDealItemGroupTypes.GOLD][playerType].GetTopControl():SetHide(false);

			availableItemCount = availableItemCount + PopulateAvailableGold(player, g_AvailableGroups[AvailableDealItemGroupTypes.GOLD][playerType]);
			availableItemCount = availableItemCount + PopulateAvailableLuxuryResources(player, g_AvailableGroups[AvailableDealItemGroupTypes.LUXURY_RESOURCES][playerType]);
			availableItemCount = availableItemCount + PopulateAvailableStrategicResources(player, g_AvailableGroups[AvailableDealItemGroupTypes.STRATEGIC_RESOURCES][playerType]);

			if (not ms_bIsDemand) then
				availableItemCount = availableItemCount + PopulateAvailableAgreements(player, g_AvailableGroups[AvailableDealItemGroupTypes.AGREEMENTS][playerType]);
			else
				g_AvailableGroups[AvailableDealItemGroupTypes.AGREEMENTS][playerType].GetTopControl():SetHide(true);
			end

			availableItemCount = availableItemCount + PopulateAvailableCities(player, g_AvailableGroups[AvailableDealItemGroupTypes.CITIES][playerType]);

			if (not ms_bIsDemand) then
				availableItemCount = availableItemCount + PopulateAvailableOtherPlayers(player, g_AvailableGroups[AvailableDealItemGroupTypes.OTHER_PLAYERS][playerType]);
			else
				g_AvailableGroups[AvailableDealItemGroupTypes.OTHER_PLAYERS][playerType].GetTopControl():SetHide(false);
			end

			availableItemCount = availableItemCount + PopulateAvailableGreatWorks(player, g_AvailableGroups[AvailableDealItemGroupTypes.GREAT_WORKS][playerType]);
			availableItemCount = availableItemCount + PopulateAvailableCaptives(player, g_AvailableGroups[AvailableDealItemGroupTypes.CAPTIVES][playerType]);

		end

		rootControl:CalculateSize();

	end

	return availableItemCount; 
end

-- ===========================================================================
function PopulateDealBasic(player : table, iconList : table, populateType : number, iconName : string)

	local pDeal : table = DealManager.GetWorkingDeal(DealDirection.OUTGOING, g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
	local playerType : number = GetPlayerType(player);
	if (pDeal ~= nil) then
	g_IconAndTextIM:ReleaseInstanceByParent(iconList.CaptivesDealsStack);
	g_IconOnlyIM:ReleaseInstanceByParent(iconList.MinimizedCaptivesDealsStack);
		
		local pDealItem : table;
		for pDealItem in pDeal:Items() do
			local type : number = pDealItem:GetType();
			if (pDealItem:GetFromPlayerID() == player:GetID()) then
				local iDuration : number = pDealItem:GetDuration();
				local dealItemID : number = pDealItem:GetID();
				
				if (type == populateType) then
					local uiIcon : table = g_IconAndTextIM:GetInstance(iconList.CaptivesDealsStack);
					SetIconToSize(uiIcon.Icon, iconName);
					uiIcon.AmountText:SetHide(true);

					local uiMinimizedIcon : table = g_IconOnlyIM:GetInstance(iconList.MinimizedCaptivesDealsStack);
					SetIconToSize(uiMinimizedIcon.Icon, iconName);
					uiMinimizedIcon.AmountText:SetHide(true);

					local typeName : string = pDealItem:GetValueTypeNameID();
					if (typeName ~= nil) then
						uiIcon.IconText:LocalizeAndSetText(typeName);
					end

					-- Show/hide unacceptable item notification
					uiIcon.UnacceptableIcon:SetHide(not pDealItem:IsUnacceptable());
					uiIcon.RemoveButton:SetHide(false);
				
					uiIcon.RemoveButton:RegisterCallback(Mouse.eLClick, function(void1, void2, self) OnRemoveDealItem(player, dealItemID, self); end)
					uiIcon.SelectButton:RegisterCallback(Mouse.eRClick, function(void1, void2, self) OnRemoveDealItem(player, dealItemID, self); end);
					uiIcon.SelectButton:RegisterCallback( Mouse.eLClick, function(void1, void2, self) OnSelectValueDealItem(player, dealItemID, self); end );

					uiIcon.SelectButton:SetToolTipString(nil);		-- We recycle the entries, so make sure this is clear.
					uiIcon.SelectButton:SetDisabled(false);
					uiIcon.StopAskingButton:SetHide(true);

					uiMinimizedIcon.UnacceptableIcon:SetHide(not pDealItem:IsUnacceptable());
					uiMinimizedIcon.RemoveButton:SetHide(false);

					uiMinimizedIcon.RemoveButton:RegisterCallback(Mouse.eLClick, function(void1, void2, self) OnRemoveDealItem(player, dealItemID, self); end)
					uiMinimizedIcon.SelectButton:RegisterCallback(Mouse.eRClick, function(void1, void2, self) OnRemoveDealItem(player, dealItemID, self); end);
					uiMinimizedIcon.SelectButton:RegisterCallback( Mouse.eLClick, function(void1, void2, self) OnSelectValueDealItem(player, dealItemID, self); end );

					uiMinimizedIcon.SelectButton:SetToolTipString(Locale.Lookup(typeName));		-- We recycle the entries, so make sure this is clear.
					uiMinimizedIcon.SelectButton:SetDisabled(false);
					uiMinimizedIcon.StopAskingButton:SetHide(true);
					uiMinimizedIcon.Icon:SetColor(1,1,1);
				end
			end
		end

		local itemCount : number = table.count(iconList.CaptivesDealsStack:GetChildren());

		if(itemCount <= 1 and iconList.CaptivesDealsStack:IsHidden())then
			OnDealsHeaderCollapseButton(iconList.CaptivesDealsStack, iconList.MinimizedCaptivesDealsStack, iconList.CaptivesDealsExpandButton);
		end

		iconList.CaptivesDealsExpandButton:SetHide(not (itemCount > 1));
		iconList.CaptivesDealsGrid:SetHide(itemCount == 0);
		iconList.CaptivesDealsHeader:SetHide(itemCount == 0);

		iconList.OfferStack:CalculateSize();

	end

end

-- ===========================================================================
function GetParentItemTransferToolTip(parentDealItem)
	local szToolTip = "";

	-- If it is from a city, put the city name in the tool tip.
	if (parentDealItem:GetType() == DealItemTypes.CITIES) then

		local cityTypeName = parentDealItem:GetValueTypeNameID();
		if (cityTypeName ~= nil) then
			local cityName = Locale.Lookup(cityTypeName);
			local szTransfer = Locale.Lookup("LOC_DEAL_ITEM_TRANSFERRED_WITH_CITY_TOOLTIP", cityName);

			szToolTip = "[NEWLINE]" .. szTransfer;
		end
	end

	return szToolTip;
end
-- ===========================================================================
function PopulateDealResources(player : table, iconList : table)
	local pDeal : table = DealManager.GetWorkingDeal(DealDirection.OUTGOING, g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
	local playerType : number = GetPlayerType(player);
	if (pDeal ~= nil) then
		g_IconOnlyIM:ReleaseInstanceByParent(iconList.OneTimeDealsStack);
		g_IconOnlyIM:ReleaseInstanceByParent(iconList.For30TurnsDealsStack);

		local pDealItem : table;
		for pDealItem in pDeal:Items() do

			local type : number = pDealItem:GetType();
			if (pDealItem:GetFromPlayerID() == player:GetID()) then
				local iDuration : number = pDealItem:GetDuration();
				local dealItemID : number = pDealItem:GetID();
				-- Gold?
				if (type == DealItemTypes.GOLD) then
					local uiIcon : table;
					if (iDuration == 0) then
						-- One time
						uiIcon = g_IconOnlyIM:GetInstance(iconList.OneTimeDealsStack);
					else
						-- Multi-turn
						uiIcon = g_IconOnlyIM:GetInstance(iconList.For30TurnsDealsStack);

					end
					SetIconToSize(uiIcon.Icon, "ICON_YIELD_GOLD_5");
					uiIcon.AmountText:SetText(tostring(pDealItem:GetAmount()));
					uiIcon.AmountText:SetHide(false);
					uiIcon.StopAskingButton:SetHide(true);
					uiIcon.Icon:SetColor(1,1,1);

					-- Show/hide unacceptable item notification
					uiIcon.UnacceptableIcon:SetHide(not pDealItem:IsUnacceptable());
					uiIcon.RemoveButton:SetHide(false);
				
					uiIcon.RemoveButton:RegisterCallback(Mouse.eLClick, function(void1, void2, self) OnRemoveDealItem(player, dealItemID, self); end)
					uiIcon.SelectButton:RegisterCallback(Mouse.eRClick, function(void1, void2, self) OnRemoveDealItem(player, dealItemID, self); end);
					uiIcon.SelectButton:RegisterCallback( Mouse.eLClick, function(void1, void2, self) OnSelectValueDealItem(player, dealItemID, self); end );
					uiIcon.SelectButton:SetToolTipString(nil);		-- We recycle the entries, so make sure this is clear.
					uiIcon.SelectButton:SetDisabled(false);
					if (dealItemID == g_ValueEditDealItemID) then
						g_ValueEditDealItemControlTable = uiIcon;
					end
				else
					if (type == DealItemTypes.RESOURCES) then

						local resourceType :number = pDealItem:GetValueType();
						local uiIcon : table;
						if (iDuration == 0) then
							-- One time
							uiIcon = g_IconOnlyIM:GetInstance(iconList.OneTimeDealsStack);
						else
							-- Multi-turn
							uiIcon = g_IconOnlyIM:GetInstance(iconList.For30TurnsDealsStack);
						end
						local resourceDesc : table = GameInfo.Resources[resourceType];
						SetIconToSize(uiIcon.Icon, "ICON_" .. resourceDesc.ResourceType);
						uiIcon.AmountText:SetText(tostring(pDealItem:GetAmount()));
						uiIcon.AmountText:SetHide(false);
						uiIcon.StopAskingButton:SetHide(true);
						uiIcon.Icon:SetColor(1,1,1);

						-- Show/hide unacceptable item notification
						uiIcon.UnacceptableIcon:SetHide(not pDealItem:IsUnacceptable());

						local szToolTip : string = Locale.Lookup(resourceDesc.Name);

						local parentDealItem : table = pDeal:GetItemParent(pDealItem);

						if parentDealItem == nil then
							-- No parent, the user can click on the item to change it.
							uiIcon.RemoveButton:SetHide(false);
				
							uiIcon.RemoveButton:RegisterCallback(Mouse.eLClick, function(void1, void2, self) OnRemoveDealItem(player, dealItemID, self); end)
							uiIcon.SelectButton:RegisterCallback(Mouse.eRClick, function(void1, void2, self) OnRemoveDealItem(player, dealItemID, self); end);
							uiIcon.SelectButton:RegisterCallback( Mouse.eLClick, function(void1, void2, self) OnSelectValueDealItem(player, dealItemID, self); end );
							uiIcon.SelectButton:SetDisabled(false);
						else
							-- indicate number is per turn in the tooltip (TTP #44289)
							if (iDuration == 0) then
								local resourceTypeName : string = pDealItem:GetValueTypeID();
								local kConsumption : table = GameInfo.Resource_Consumption[resourceTypeName];
								if kConsumption ~= nil then
									if kConsumption.Accumulate then
										szToolTip = szToolTip.."[NEWLINE]"..Locale.Lookup("LOC_HUD_REPORTS_PER_TURN", kConsumption.ImprovedExtractionRate);
									end
								end
							end

							uiIcon.SelectButton:ClearCallback( Mouse.eRClick );		-- Clear, we are re-using control instances
							uiIcon.SelectButton:ClearCallback( Mouse.eLClick );

							szToolTip = szToolTip .. GetParentItemTransferToolTip(parentDealItem);
						end

						-- Set a tool tip
						uiIcon.SelectButton:SetToolTipString(szToolTip);

						-- KWG: Make a way for the icon manager to have categories, so the API is like this
						-- uiIcon.Icon:SetTexture(IconManager:FindIconAtlasForType(IconTypes.RESOURCE, resourceType));

						if (dealItemID == g_ValueEditDealItemID) then
							g_ValueEditDealItemControlTable = uiIcon;
						end
					end --end else if the item isn't gold
				end -- end for each item in dael
			end -- end if deal
		end

		iconList.OneTimeDealsHeader:SetHide(table.count(iconList.OneTimeDealsStack:GetChildren()) == 0);
		iconList.For30TurnsDealsHeader:SetHide(table.count(iconList.For30TurnsDealsStack:GetChildren()) == 0);

		iconList.OfferStack:CalculateSize();

	end

end

-- ===========================================================================
function PopulateDealAgreements(player : table, iconList : table)

	local pDeal : table = DealManager.GetWorkingDeal(DealDirection.OUTGOING, g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
	local playerType : number = GetPlayerType(player);
	if (pDeal ~= nil) then
		g_IconAndTextIM:ReleaseInstanceByParent(iconList.AgreementDealsStack);
		g_IconOnlyIM:ReleaseInstanceByParent(iconList.MinimizedAgreementDealsStack);
		local pDealItem : table;
		for pDealItem in pDeal:Items() do

			local type : number = pDealItem:GetType();
			if (pDealItem:GetFromPlayerID() == player:GetID()) then
				local dealItemID : number = pDealItem:GetID();
				-- Agreement?
				if (type == DealItemTypes.AGREEMENTS) then
					local uiMinimizedIcon : table = g_IconOnlyIM:GetInstance(iconList.MinimizedAgreementDealsStack);
					local uiIcon : table = g_IconAndTextIM:GetInstance(iconList.AgreementDealsStack);
					local info: table = GameInfo.DiplomaticActions[ pDealItem:GetSubType() ];
					if (info ~= nil) then
						SetIconToSize(uiIcon.Icon, "ICON_".. info.DiplomaticActionType, 38);
						SetIconToSize(uiMinimizedIcon.Icon, "ICON_".. info.DiplomaticActionType, 38);
					end

					uiIcon.AmountText:SetHide(true);
					uiMinimizedIcon.AmountText:SetHide(true);
					uiMinimizedIcon.Icon:SetColor(1,1,1);

					local subTypeDisplayName : string = pDealItem:GetSubTypeNameID();
					if (subTypeDisplayName ~= nil) then
						uiIcon.IconText:LocalizeAndSetText(subTypeDisplayName);
						-- For alliances, it's useful to show the alliance type in the tooltip for the minimized version
						if pDealItem:GetSubType() == DealAgreementTypes.ALLIANCE and pDealItem:GetValueTypeNameID() ~= nil then
							local toolTip : string = Locale.Lookup(subTypeDisplayName).."[NEWLINE]"..Locale.Lookup(pDealItem:GetValueTypeNameID());
							uiMinimizedIcon.SelectButton:SetToolTipString(toolTip);
						else
							uiMinimizedIcon.SelectButton:SetToolTipString(Locale.Lookup(subTypeDisplayName));
						end
					end
					uiIcon.SelectButton:SetToolTipString(nil);		-- We recycle the entries, so make sure this is clear.

					-- Show/hide unacceptable item notification
					uiIcon.UnacceptableIcon:SetHide(not pDealItem:IsUnacceptable());
					uiMinimizedIcon.UnacceptableIcon:SetHide(not pDealItem:IsUnacceptable());
					
					if(pDealItem:IsLocked())then
						uiIcon.RemoveButton:SetHide(true);
						uiIcon.SelectButton:ClearCallback(Mouse.eRClick);

						uiMinimizedIcon.RemoveButton:SetHide(true);
						uiMinimizedIcon.SelectButton:ClearCallback(Mouse.eRClick);
					else
						uiIcon.RemoveButton:SetHide(false);
						uiIcon.RemoveButton:RegisterCallback(Mouse.eLClick, function(void1, void2, self) OnRemoveDealItem(player, dealItemID, self); end);
						uiIcon.SelectButton:RegisterCallback(Mouse.eRClick, function(void1, void2, self) OnRemoveDealItem(player, dealItemID, self); end);

						uiMinimizedIcon.RemoveButton:SetHide(false);
						uiMinimizedIcon.RemoveButton:RegisterCallback(Mouse.eLClick, function(void1, void2, self) OnRemoveDealItem(player, dealItemID, self); end);
						uiMinimizedIcon.SelectButton:RegisterCallback(Mouse.eRClick, function(void1, void2, self) OnRemoveDealItem(player, dealItemID, self); end);
					end

					-- Populate the value pulldown
					SetValueText(uiIcon, pDealItem);

					local toolTip : string = uiMinimizedIcon.SelectButton:GetToolTipString();
					if(info.DiplomaticActionType == "DIPLOACTION_JOINT_WAR")then
						toolTip = toolTip .. "[NEWLINE]" .. Locale.Lookup(pDealItem:GetValueTypeNameID());
						uiMinimizedIcon.SelectButton:SetToolTipString(toolTip);
					end

					if(info.DiplomaticActionType == "DIPLOACTION_JOINT_WAR" and pDealItem:GetFromPlayerID() == g_OtherPlayer:GetID()) then
						uiIcon.SelectButton:SetDisabled(true);
						uiIcon.SelectButton:SetToolTipString(Locale.Lookup("LOC_JOINT_WAR_CANNOT_EDIT_THEIRS_TOOLTIP"));
						uiMinimizedIcon.SelectButton:SetDisabled(true);
						
						toolTip = toolTip .. "[NEWLINE]" .. Locale.Lookup("LOC_JOINT_WAR_CANNOT_EDIT_THEIRS_TOOLTIP");
						uiMinimizedIcon.SelectButton:SetToolTipString(toolTip);
					else
						uiIcon.SelectButton:SetDisabled(false);
						uiIcon.SelectButton:RegisterCallback( Mouse.eLClick, function(void1, void2, self) OnSelectValueDealItem(player, dealItemID, self); end );

						uiMinimizedIcon.SelectButton:SetDisabled(false);
						uiMinimizedIcon.SelectButton:RegisterCallback( Mouse.eLClick, function(void1, void2, self) OnSelectValueDealItem(player, dealItemID, self); end );
					end

					if(ms_InitiatedByPlayerID ~= g_LocalPlayer:GetID() and pDealItem:GetFromPlayerID() == Game.GetLocalPlayer() and not ms_OtherPlayerIsHuman and not pDealItem:IsUnacceptable())then
						uiIcon.StopAskingButton:SetHide(false);
						uiMinimizedIcon.StopAskingButton:SetHide(false);
						
						uiIcon.StopAskingButton:RegisterCallback(Mouse.eLClick, function() OnSetDealItemUnacceptable(dealItemID); end);
						uiMinimizedIcon.StopAskingButton:RegisterCallback(Mouse.eLClick, function() OnSetDealItemUnacceptable(dealItemID); end);
					else
						uiIcon.StopAskingButton:SetHide(true);
						uiMinimizedIcon.StopAskingButton:SetHide(true);
					end
				end
			end
		end

		local itemCount : number = table.count(iconList.AgreementDealsStack:GetChildren());

		if(itemCount <= 1 and iconList.AgreementDealsStack:IsHidden())then
			OnDealsHeaderCollapseButton(iconList.AgreementDealsStack, iconList.MinimizedAgreementDealsStack, iconList.AgreementDealsExpandButton);
		end

		iconList.AgreementDealsExpandButton:SetHide(not (itemCount > 1));
		iconList.AgreementDealsGrid:SetHide(itemCount == 0);
		iconList.AgreementDealsHeader:SetHide(itemCount == 0);
		iconList.OfferStack:CalculateSize();

	end

end

-- ===========================================================================
function PopulateDealGreatWorks(player : table, iconList : table)

	local pDeal : table = DealManager.GetWorkingDeal(DealDirection.OUTGOING, g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
	local playerType : number = GetPlayerType(player);
	if (pDeal ~= nil) then
		g_IconAndTextIM:ReleaseInstanceByParent(iconList.GreatWorksDealsStack);
		g_IconOnlyIM:ReleaseInstanceByParent(iconList.MinimizedGreatWorksDealsStack);
		local pDealItem : table;
		for pDealItem in pDeal:Items() do

			local type = pDealItem:GetType();
			if (pDealItem:GetFromPlayerID() == player:GetID()) then
				local iDuration : number = pDealItem:GetDuration();
				local dealItemID : number = pDealItem:GetID();
				
				if (type == DealItemTypes.GREATWORK) then
					local uiIcon : table = g_IconAndTextIM:GetInstance(iconList.GreatWorksDealsStack);
					local uiMinimizedIcon : table = g_IconOnlyIM:GetInstance(iconList.MinimizedGreatWorksDealsStack);
					local greatWorkDesc : table = GameInfo.GreatWorks[pDealItem:GetSubType()];
					local iconName : string = GetGreatWorkIcon(greatWorkDesc, pDealItem:GetValueTypeID());

					SetIconToSize(uiIcon.Icon, iconName, 45);
					SetIconToSize(uiMinimizedIcon.Icon, iconName, 45);

					uiIcon.AmountText:SetHide(true);
					uiMinimizedIcon.AmountText:SetHide(true);
					uiMinimizedIcon.Icon:SetColor(1,1,1);

					local typeName : string = pDealItem:GetValueTypeNameID();

					local strTooltip :string = "";

					if (typeName ~= nil) then
						uiIcon.IconText:LocalizeAndSetText(typeName);
						strTooltip = Locale.Lookup( GreatWorksSupport_GetBasicTooltip(pDealItem:GetValueType(), false) );
					else
						uiIcon.IconText:SetText(nil);
					end

					uiIcon.ValueText:SetHide(true);
					
					-- Show/hide unacceptable item notification
					uiIcon.UnacceptableIcon:SetHide(not pDealItem:IsUnacceptable());
					uiMinimizedIcon.UnacceptableIcon:SetHide(not pDealItem:IsUnacceptable());

					local parentDealItem : table = pDeal:GetItemParent(pDealItem);

					if parentDealItem == nil then
						-- No parent, we can remove independently
						uiIcon.RemoveButton:SetHide(false);
						uiIcon.RemoveButton:RegisterCallback(Mouse.eLClick, function(void1, void2, self) OnRemoveDealItem(player, dealItemID, self); end);
						uiIcon.SelectButton:RegisterCallback(Mouse.eRClick, function(void1, void2, self) OnRemoveDealItem(player, dealItemID, self); end);
						uiIcon.SelectButton:RegisterCallback( Mouse.eLClick, function(void1, void2, self) OnSelectValueDealItem(player, dealItemID, self); end );
						uiIcon.SelectButton:SetDisabled(false);

						uiMinimizedIcon.RemoveButton:SetHide(false);
						uiMinimizedIcon.RemoveButton:RegisterCallback(Mouse.eLClick, function(void1, void2, self) OnRemoveDealItem(player, dealItemID, self); end);
						uiMinimizedIcon.SelectButton:RegisterCallback(Mouse.eRClick, function(void1, void2, self) OnRemoveDealItem(player, dealItemID, self); end);
						uiMinimizedIcon.SelectButton:SetDisabled(false);
					else
						uiIcon.SelectButton:ClearCallback( Mouse.eRClick );
						uiIcon.SelectButton:ClearCallback( Mouse.eLClick );

						uiMinimizedIcon.SelectButton:ClearCallback( Mouse.eRClick );
						uiMinimizedIcon.SelectButton:ClearCallback( Mouse.eLClick );

						-- Add on to the tool tip to show why it is there.
						strTooltip = strTooltip .. GetParentItemTransferToolTip(parentDealItem);
					end

					local itemTooltip : string = GetGreatWorkTooltip(greatWorkDesc, strTooltip);

					uiIcon.SelectButton:SetToolTipString(itemTooltip);
					uiMinimizedIcon.SelectButton:SetToolTipString(itemTooltip);

					if(ms_InitiatedByPlayerID ~= g_LocalPlayer:GetID() and pDealItem:GetFromPlayerID() == Game.GetLocalPlayer() and not ms_OtherPlayerIsHuman and not pDealItem:IsUnacceptable())then
						uiIcon.StopAskingButton:SetHide(false);
						uiMinimizedIcon.StopAskingButton:SetHide(false);

						uiIcon.StopAskingButton:RegisterCallback(Mouse.eLClick, function() OnSetDealItemUnacceptable(dealItemID); end);
						uiMinimizedIcon.StopAskingButton:RegisterCallback(Mouse.eLClick, function() OnSetDealItemUnacceptable(dealItemID); end);
					else
						uiIcon.StopAskingButton:SetHide(true);
						uiMinimizedIcon.StopAskingButton:SetHide(true);
					end
				end
			end
		end

		local itemCount : number = table.count(iconList.GreatWorksDealsStack:GetChildren());

		if(itemCount <= 1 and iconList.GreatWorksDealsStack:IsHidden())then
			OnDealsHeaderCollapseButton(iconList.GreatWorksDealsStack, iconList.MinimizedGreatWorksDealsStack, iconList.GreatWorksDealsExpandButton);
		end

		iconList.GreatWorksDealsExpandButton:SetHide(not (itemCount > 1));
		iconList.GreatWorksDealsGrid:SetHide(itemCount == 0);
		iconList.GreatWorksDealsHeader:SetHide(itemCount == 0);
		iconList.OfferStack:CalculateSize();

	end

end

-- ===========================================================================
function PopulateDealCaptives(player : table, iconList : table)

	PopulateDealBasic(player, iconList, DealItemTypes.CAPTIVE, "ICON_UNIT_SPY");

end

-- ===========================================================================
function PopulateDealCities(player : table, iconList : table)

	local pDeal : table = DealManager.GetWorkingDeal(DealDirection.OUTGOING, g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
	local playerType : number = GetPlayerType(player);
	if (pDeal ~= nil) then

		ms_CityDetailsIM:ReleaseInstanceByParent(iconList.CityDealsStack);
		g_IconOnlyIM:ReleaseInstanceByParent(iconList.MinimizedCityDealsStack);

		local pDealItem : table;
		for pDealItem in pDeal:Items() do

			local type : number = pDealItem:GetType();
			if (pDealItem:GetFromPlayerID() == player:GetID()) then
				local dealItemID : number = pDealItem:GetID();
				
				if (type == DealItemTypes.CITIES) then
					local uiMinimizedIcon : table = g_IconOnlyIM:GetInstance(iconList.MinimizedCityDealsStack);
					SetIconToSize(uiMinimizedIcon.Icon, "ICON_BUILDINGS");

					local uiIcon : table = ms_CityDetailsIM:GetInstance(iconList.CityDealsStack);
					SetIconToSize(uiIcon.Icon, "ICON_BUILDINGS");
					uiIcon.AmountText:SetHide(true);
					local typeName : string = pDealItem:GetValueTypeNameID();
					if (typeName ~= nil) then
						uiIcon.IconText:LocalizeAndSetText(typeName);
					end

					-- Show/hide unacceptable item notification
					uiIcon.UnacceptableIcon:SetHide(not pDealItem:IsUnacceptable());
					uiMinimizedIcon.UnacceptableIcon:SetHide(not pDealItem:IsUnacceptable());

					if(pDealItem:IsLocked())then
						uiIcon.RemoveButton:SetHide(true);
						uiIcon.SelectButton:ClearCallback(Mouse.eRClick);

						uiMinimizedIcon.RemoveButton:SetHide(true);
						uiMinimizedIcon.SelectButton:ClearCallback(Mouse.eRClick);
					else
						uiIcon.RemoveButton:SetHide(false);
						uiIcon.RemoveButton:RegisterCallback(Mouse.eLClick, function(void1, void2, self) OnRemoveDealCity(typeName, player, dealItemID, self); end);
						uiIcon.SelectButton:RegisterCallback(Mouse.eRClick, function(void1, void2, self) OnRemoveDealCity(typeName, player, dealItemID, self); end);

						uiMinimizedIcon.RemoveButton:SetHide(false);
						uiMinimizedIcon.SelectButton:RegisterCallback(Mouse.eRClick, function(void1, void2, self) OnRemoveDealItem(player, dealItemID, self); end);
					end

					uiIcon.SelectButton:RegisterCallback( Mouse.eLClick, function(void1, void2, self) OnSelectValueDealItem(player, dealItemID, self); end );
					uiIcon.SelectButton:SetDisabled(false);
					
					
					
					uiMinimizedIcon.RemoveButton:RegisterCallback(Mouse.eLClick, function(void1, void2, self) OnRemoveDealItem(player, dealItemID, self); end);
					uiMinimizedIcon.SelectButton:SetDisabled(false);
					uiMinimizedIcon.Icon:SetColor(1,1,1);

					uiIcon.SelectButton:SetToolTipString( MakeCityToolTip(player, pDealItem:GetValueType() ) );
					uiMinimizedIcon.SelectButton:SetToolTipString(Locale.Lookup(typeName).."[NEWLINE]"..MakeCityToolTip(player, pDealItem:GetValueType() ));
					local hasChildDealItems : boolean = false;

					--Check if this city comes with dependants (resources or great works)
					for pChildDealItem in pDeal:Items() do
						if (pDeal:GetItemParent(pChildDealItem) == pDealItem) then
							hasChildDealItems = true;
							local type : number = pChildDealItem:GetType();
							local childIcon : table = g_IconOnlyIM:GetInstance(uiIcon.CityDetailsStack);

							if(type == DealItemTypes.RESOURCES)then
								childIcon.AmountText:SetText(tostring(pChildDealItem:GetAmount()));
								childIcon.AmountText:SetHide(false);
								
								local resourceDescription : table = GameInfo.Resources[pChildDealItem:GetValueType()];
								SetIconToSize(childIcon.Icon, "ICON_" .. resourceDescription.ResourceType);
								
								local childToolTip : string = Locale.Lookup(resourceDescription.Name);
								childIcon.SelectButton:SetToolTipString(childToolTip);

							elseif(type == DealItemTypes.GREATWORK) then
								childIcon.AmountText:SetHide(true);

								local childToolTip : string = Locale.Lookup(GreatWorksSupport_GetBasicTooltip(pChildDealItem:GetValueType(), false))
								childIcon.SelectButton:SetToolTipString(childToolTip);

								local childTypeID : string = pChildDealItem:GetValueTypeID();
								SetIconToSize(childIcon.Icon, "ICON_"..childTypeID,45);
							end
						end
					end
					uiIcon.CollapseButton:RegisterCallback(Mouse.eLClick, function() OnCityDetailsCollapse(uiIcon.CityDetails, typeName, uiIcon.CollapseButton); end);
					uiIcon.CollapseButton:SetHide(not hasChildDealItems);
					if(m_kCollapsedCityDetails[typeName])then
						uiIcon.CityDetails:SetHide(false);
					end

					if(ms_InitiatedByPlayerID ~= g_LocalPlayer:GetID() and pDealItem:GetFromPlayerID() == Game.GetLocalPlayer() and not ms_OtherPlayerIsHuman and not pDealItem:IsUnacceptable())then
						uiIcon.StopAskingButton:SetHide(false);
						uiMinimizedIcon.StopAskingButton:SetHide(false);
						
						uiIcon.StopAskingButton:RegisterCallback(Mouse.eLClick, function() OnSetDealItemUnacceptable(dealItemID); end);
						uiMinimizedIcon.StopAskingButton:RegisterCallback(Mouse.eLClick, function() OnSetDealItemUnacceptable(dealItemID); end);
					else
						uiIcon.StopAskingButton:SetHide(true);
						uiMinimizedIcon.StopAskingButton:SetHide(true);
					end
				end
			end
		end

		local itemCount : number = table.count(iconList.CityDealsStack:GetChildren());

		if(itemCount <= 1 and iconList.CityDealsStack:IsHidden())then
			OnDealsHeaderCollapseButton(iconList.CityDealsStack, iconList.MinimizedCityDealsStack, iconList.CityDealsExpandButton);
		end

		iconList.CityDealsHeader:SetHide(itemCount == 0);
		iconList.CityDealsExpandButton:SetHide(not (itemCount > 1));
		iconList.CityDealsGrid:SetHide(itemCount == 0);
		iconList.OfferStack:CalculateSize();
	end


end

-- ===========================================================================
function PopulatePlayerDealPanel(rootControl : table, player : table)

	if (player ~= nil) then
		
		local playerType : number = GetPlayerType(player);
		PopulateDealResources(player, ms_DealGroups[DealItemGroupTypes.RESOURCES][playerType]);
		PopulateDealAgreements(player, ms_DealGroups[DealItemGroupTypes.AGREEMENTS][playerType]);
		PopulateDealCaptives(player, ms_DealGroups[DealItemGroupTypes.CAPTIVES][playerType]);
		PopulateDealGreatWorks(player, ms_DealGroups[DealItemGroupTypes.GREAT_WORKS][playerType]);
		PopulateDealCities(player, ms_DealGroups[DealItemGroupTypes.CITIES][playerType]);

		rootControl.OfferStack:CalculateSize();
	end
end

-- ===========================================================================
function HandleESC()
	-- Were we just viewing the deal?
	if ( m_kPopupDialog:IsOpen()) then
			m_kPopupDialog:Close();
	elseif (not Controls.ResumeGame:IsHidden()) then
		OnResumeGame();
	else
		OnRefuseDeal();
	end
end

-- ===========================================================================
--	INPUT Handlings
--	If this context is visible, it will get a crack at the input.
-- ===========================================================================
function KeyHandler( key:number )
	if (key == Keys.VK_ESCAPE) then 
		HandleESC();			
		return true; 
	end

	return false;
end

-- ===========================================================================
function InputHandler( pInputStruct:table )
	if SRA_HandleInput( pInputStruct ) then return true; end		-- ScreenReaderAccess
	local uiMsg = pInputStruct:GetMessageType();
	if uiMsg == KeyEvents.KeyUp then 
		return KeyHandler( pInputStruct:GetKey() ); 
	end
	if (uiMsg == MouseEvents.LButtonUp or
		uiMsg == MouseEvents.RButtonUp or
		uiMsg == MouseEvents.MButtonUp or
		uiMsg == MouseEvents.PointerUp) then 
		ClearValueEdit();
	end

	return false;
end

-- ===========================================================================
--	Handle a request to be shown, this should only be called by
--  the diplomacy statement handler.
-- ===========================================================================

function OnShowMakeDeal(otherPlayerID)
	ms_OtherPlayerID = otherPlayerID;
	ms_bIsDemand = false;
	ContextPtr:SetHide( false );
end
SRListen( LuaEvents.DiploPopup_ShowMakeDeal, OnShowMakeDeal );		-- ScreenReaderAccess: was .Add(), see SRListen.lua

-- ===========================================================================
--	Handle a request to be shown, this should only be called by
--  the diplomacy statement handler.
-- ===========================================================================

function OnShowMakeDemand(otherPlayerID)
	ms_OtherPlayerID = otherPlayerID;
	ms_bIsDemand = true;
	ContextPtr:SetHide( false );
end
SRListen( LuaEvents.DiploPopup_ShowMakeDemand, OnShowMakeDemand );		-- ScreenReaderAccess

-- ===========================================================================
--	Handle a request to be hidden, this should only be called by
--  the diplomacy statement handler.
-- ===========================================================================

function OnHideDeal(otherPlayerID)
	OnContinue();
end
SRListen( LuaEvents.DiploPopup_HideDeal, OnHideDeal );		-- ScreenReaderAccess

-- ===========================================================================
-- The other player has updated the deal
function OnDiplomacyIncomingDeal(eFromPlayer, eToPlayer, eAction)
	if (eFromPlayer == ms_OtherPlayerID) then
		local pDeal = DealManager.GetWorkingDeal(DealDirection.INCOMING, g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
		if (pDeal ~= nil) then
			ms_bIsGift = pDeal:IsGift();

			-- Copy the deal to our OUTGOING deal back to the other player, in case we want to make modifications
			DealManager.CopyIncomingToOutgoingWorkingDeal(g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
			ms_LastIncomingDealProposalAction = eAction;

			PopulatePlayerDealPanel(g_uiTheirOffers, g_OtherPlayer);
			PopulatePlayerDealPanel(g_uiMyOffers, g_LocalPlayer);
			UpdateDealStatus();
			SRA_NoteIncoming( eAction );		-- ScreenReaderAccess
		end
	end
end
SRListen( Events.DiplomacyIncomingDeal, OnDiplomacyIncomingDeal );		-- ScreenReaderAccess

-- ===========================================================================
--	Handle a deal changing, usually from an incoming statement.
-- ===========================================================================

function OnDealUpdated(otherPlayerID, eAction, szText)
	if (not ContextPtr:IsHidden()) then
		-- Display some updated text.
		if (szText ~= nil and szText ~= "") then
			SetLeaderDialog(szText, "");
		end			
		-- Update deal and possible override text from szText
		OnDiplomacyIncomingDeal( otherPlayerID, Game.GetLocalPlayer(), eAction); 
	end
end
SRListen( LuaEvents.DiploPopup_DealUpdated, OnDealUpdated );		-- ScreenReaderAccess

-- ===========================================================================
function SetLeaderDialog(leaderDialog:string, leaderEffect:string)
	SRA_NoteLeader( leaderDialog, leaderEffect );		-- ScreenReaderAccess
	-- Update dialog
	Controls.LeaderDialog:LocalizeAndSetText(leaderDialog);

	-- Add parentheses to the effect text unless the text is ""
	if leaderEffect ~= "" then
		leaderEffect = "(" .. Locale.Lookup(leaderEffect) .. ")";
	end
	Controls.LeaderEffect:SetText(leaderEffect);

	-- Recenter text
	Controls.LeaderDialogStack:CalculateSize();
end

-- ===========================================================================
function StartExitAnimation()
	-- Start the exit animation, it will call OnContinue when complete
	ms_bExiting = true;
	Controls.YieldSlide:Reverse();
	Controls.YieldAlpha:Reverse();
	Controls.TradePanelFade:Reverse();
	Controls.TradePanelSlide:Reverse();
	Controls.TradePanelFade:SetSpeed(5);
	Controls.TradePanelSlide:SetSpeed(5);
	UI.PlaySound("UI_Diplomacy_Menu_Change");
end

-- ===========================================================================
function OnContinue()
	ContextPtr:SetHide( true );
end

-- ===========================================================================
--	Functions for setting the data in the yield area
-- ===========================================================================

function FormatValuePerTurn( value:number )
	return Locale.ToNumber(value, "+#,###.#;-#,###.#");
end

function RefreshYields()

	local ePlayer		:number = Game.GetLocalPlayer();
	local localPlayer	:table= nil;
	if ePlayer ~= -1 then
		localPlayer = Players[ePlayer];
		if localPlayer == nil then
			return;
		end
	else
		return;
	end

	---- SCIENCE ----
	local playerTechnology		:table	= localPlayer:GetTechs();
	local currentScienceYield	:number = playerTechnology:GetScienceYield();
	Controls.SciencePerTurn:SetText( FormatValuePerTurn(currentScienceYield) );	
	Controls.ScienceBacking:SetToolTipString( GetScienceTooltip() );
	Controls.ScienceStack:CalculateSize();
	
	---- CULTURE----
	local playerCulture			:table	= localPlayer:GetCulture();
	local currentCultureYield	:number = playerCulture:GetCultureYield();
	Controls.CulturePerTurn:SetText( FormatValuePerTurn(currentCultureYield) );	
	Controls.CultureBacking:SetToolTipString( GetCultureTooltip() );
	Controls.CultureStack:CalculateSize();

	---- GOLD ----
	local playerTreasury:table	= localPlayer:GetTreasury();
	local goldYield		:number = playerTreasury:GetGoldYield() - playerTreasury:GetTotalMaintenance();
	local goldBalance	:number = math.floor(playerTreasury:GetGoldBalance());
	Controls.GoldBalance:SetText( Locale.ToNumber(goldBalance, "#,###.#"));	
	Controls.GoldPerTurn:SetText( FormatValuePerTurn(goldYield) );	
	Controls.GoldBacking:SetToolTipString(GetGoldTooltip());
	Controls.GoldStack:CalculateSize();	
	
	---- FAITH ----
	local playerReligion		:table	= localPlayer:GetReligion();
	local faithYield			:number = playerReligion:GetFaithYield();
	local faithBalance			:number = playerReligion:GetFaithBalance();
	Controls.FaithBalance:SetText( Locale.ToNumber(faithBalance, "#,###.#"));	
	Controls.FaithPerTurn:SetText( FormatValuePerTurn(faithYield) );
	Controls.FaithBacking:SetToolTipString( GetFaithTooltip() );
	Controls.FaithStack:CalculateSize();	
	if (faithYield == 0) then
		Controls.FaithBacking:SetHide(true);
	else
		Controls.FaithBacking:SetHide(false);
	end
	
	Controls.YieldStack:CalculateSize();
end

-- ===========================================================================
function OnRemoveDealCity(name : string, player : table, itemID : number)
	m_kCollapsedCityDetails[name] = nil;
	OnRemoveDealItem(player, itemID);
end

-- ===========================================================================
function OnCityDetailsCollapse(control : table, name : string, button : table)
	control:SetHide(not control:IsHidden());
	if(control:IsHidden()) then
		m_kCollapsedCityDetails[name] = nil;
		button:LocalizeAndSetToolTip("LOC_DIPLO_DEAL_EXPAND_CITY_INFO");
	else
		m_kCollapsedCityDetails[name] = true;
		button:LocalizeAndSetToolTip("LOC_DIPLO_DEAL_COLLAPSE_CITY_INFO");
	end
end

-- ===========================================================================
function OnDealsHeaderCollapseButton(control : table, minimizedControl : table, button : table)
	if(control["isCollapsed"] == nil) then
		control["isCollapsed"] = false;
	end
	control["isCollapsed"] = not control["isCollapsed"];
	control:SetHide(control["isCollapsed"]);
	minimizedControl:SetHide(not control["isCollapsed"]);
	control:CalculateSize();
	if(control["isCollapsed"]) then
		button:SetTexture("Controls_CategoryExpand");
		button:LocalizeAndSetToolTip("LOC_DIPLO_DEAL_EXPAND_CATEGORY");
	else
		button:SetTexture("Controls_CategoryCollapse");
		button:LocalizeAndSetToolTip("LOC_DIPLO_DEAL_COLLAPSE_CATEGORY");
	end
end

-- ===========================================================================
function OnDragResizer()
	local mouseX : number, mouseY : number = UIManager:GetMousePos();

	--How far has the mouse traveled while dragging?
	local yDiff : number = m_StartingMouseY - mouseY;
	yDiff = math.clamp(yDiff, m_MinDragResizeY, m_MaxDragResizeY);

	Controls.OfferColumns:SetSizeY(m_OffersStartSizeY - yDiff);
	Controls.InventoryColumns:SetSizeY(m_InvStartSizeY + yDiff);
	Controls.DragButton:SetOffsetY((m_InvStartSizeY + yDiff) - 20);
end

-- ===========================================================================
function OnShow()
	RefreshYields();
	Controls.YieldAlpha:SetToBeginning();
	Controls.YieldAlpha:Play();
	Controls.YieldSlide:SetToBeginning();
	Controls.YieldSlide:Play();
	Controls.TradePanelFade:SetToBeginning();
	Controls.TradePanelFade:Play();
	Controls.TradePanelSlide:SetToBeginning();
	Controls.TradePanelSlide:Play();
	Controls.LeaderDialogFade:SetToBeginning();
	Controls.LeaderDialogFade:Play();
	Controls.LeaderDialogSlide:SetToBeginning();
	Controls.LeaderDialogSlide:Play();
	Controls.ValueEditPopupBackground:SetHide(true);

	g_IconOnlyIM:ResetInstances();
	g_IconAndTextIM:ResetInstances();
	ms_MinimizedSectionIM:ResetInstances();
	m_srAvail = { [OTHER_PLAYER] = {}, [LOCAL_PLAYER] = {} };		-- ScreenReaderAccess
	m_srOptions = {};												-- ScreenReaderAccess

	--Reset the cityDetails states to closed
	m_kCollapsedCityDetails = {};

	ms_bExiting = false;

	if (Game.GetLocalPlayer() == -1) then
		return;
	end

	-- For hotload testing, force the other player to be valid
	if (ms_OtherPlayerID == -1) then
		local playerID = 0
		for playerID = 0, GameDefines.MAX_PLAYERS-1, 1 do
			if (playerID ~= Game.GetLocalPlayer() and Players[playerID]:IsAlive()) then
				ms_OtherPlayerID = playerID;
				break;
			end
		end
	end

	-- Set up some globals for easy access
	g_LocalPlayer = Players[Game.GetLocalPlayer()];
	g_OtherPlayer = Players[ms_OtherPlayerID];
	ms_OtherPlayerIsHuman = g_OtherPlayer:IsHuman();

	local sessionID = DiplomacyManager.FindOpenSessionID(Game.GetLocalPlayer(), g_OtherPlayer:GetID());
	if (sessionID ~= nil) then
		local sessionInfo = DiplomacyManager.GetSessionInfo(sessionID);
		ms_InitiatedByPlayerID = sessionInfo.FromPlayer;
	end

	-- Did the AI start this or the human?
	if (ms_InitiatedByPlayerID == ms_OtherPlayerID) then
		ms_LastIncomingDealProposalAction = DealProposalAction.PROPOSED;
		
		local pDeal = DealManager.GetWorkingDeal(DealDirection.INCOMING, g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
		ms_bIsGift = pDeal:IsGift();

		DealManager.CopyIncomingToOutgoingWorkingDeal(g_LocalPlayer:GetID(), g_OtherPlayer:GetID());

		local pDeal = DealManager.GetWorkingDeal(DealDirection.INCOMING, g_LocalPlayer:GetID(), g_OtherPlayer:GetID());
		ms_bIsGift = pDeal:IsGift();
	else
		ms_LastIncomingDealProposalAction = DealProposalAction.PENDING;
		-- We are NOT clearing the current outgoing deal. This allows other screens to pre-populate the deal.
	end

	UpdateOtherPlayerText(1);
	SetDefaultLeaderDialogText();

	local availableItemCount : number = 0;
	-- Available content to trade.  Shouldn't change during the session, but it might, especially in multiplayer.
	availableItemCount = availableItemCount + PopulatePlayerAvailablePanel(Controls.MyInventoryStack, g_LocalPlayer);
	availableItemCount = availableItemCount + PopulatePlayerAvailablePanel(Controls.TheirInventoryStack, g_OtherPlayer);

	Controls.MyInventoryScroll:CalculateSize();
	Controls.TheirInventoryScroll:CalculateSize();

	m_kPopupDialog:Close(); -- Close and reset the popup in case it's open

	if (availableItemCount == 0) then
		if (ms_bIsDemand) then
			m_kPopupDialog:AddText(Locale.Lookup("LOC_DIPLO_DEMAND_NO_AVAILABLE_ITEMS"));
			m_kPopupDialog:AddTitle( Locale.ToUpper(Locale.Lookup("LOC_DIPLO_CHOICE_MAKE_DEMAND")))
			m_kPopupDialog:AddButton( Locale.Lookup("LOC_OK_BUTTON"), OnRefuseDeal);
		else
			m_kPopupDialog:AddText(	  Locale.Lookup("LOC_DIPLO_DEAL_NO_AVAILABLE_ITEMS"));
			m_kPopupDialog:AddTitle( Locale.ToUpper(Locale.Lookup("LOC_DIPLO_CHOICE_MAKE_DEAL")))
			m_kPopupDialog:AddButton( Locale.Lookup("LOC_OK_BUTTON"), OnRefuseDeal);
		end
		m_kPopupDialog:Open();
	end

	PopulatePlayerDealPanel(g_uiTheirOffers, g_OtherPlayer);
	PopulatePlayerDealPanel(g_uiMyOffers, g_LocalPlayer);
	UpdateDealStatus();

	-- We may be coming into this screen with a deal already set, which needs to be sent to the AI for inspection. Check that.
	-- Don't send AI proposals for inspection or they will think the player was the creator of the deal
	if (IsAutoPropose() and (ms_InitiatedByPlayerID ~= ms_OtherPlayerID or ms_OtherPlayerIsHuman)) then
		ProposeWorkingDeal(true);
	end

	Controls.MyOfferScroll:CalculateSize();
	Controls.TheirOfferScroll:CalculateSize();

	LuaEvents.DiploBasePopup_HideUI(true);
	TTManager:ClearCurrent();	-- Clear any tool tips raised;

	Controls.DealOptionsStack:CalculateSize();

	SRA_ArmOpen();		-- ScreenReaderAccess
end

----------------------------------------------------------------
function OnHide()
	LuaEvents.DiploBasePopup_HideUI(false);
	SRA_OnHide();		-- ScreenReaderAccess
end

-- ===========================================================================
--	Context CTOR
-- ===========================================================================
function OnInit( isHotload )
	LateInitialize();

	if (isHotload and not ContextPtr:IsHidden()) then
		OnShow();
	end
end

-- ===========================================================================
--	Context DESTRUCTOR
--	Not called when screen is dismissed, only if the whole context is removed!
-- ===========================================================================
function OnShutdown()
	SRUnlistenAll();		-- ScreenReaderAccess: a hot reload must not leave this instance's listeners behind
end

-- ===========================================================================
function OnLocalPlayerTurnEnd()
	if (not ContextPtr:IsHidden()) then
		-- Were we just viewing the deal?
		if (not Controls.ResumeGame:IsHidden()) then
			OnResumeGame();
		else
			OnRefuseDeal(true);
		end
		OnContinue();
	end
end

-- ===========================================================================
function OnPlayerDefeat( player, defeat, eventID)
	local localPlayer = Game.GetLocalPlayer();
	if (localPlayer and localPlayer >= 0) then		-- Check to see if there is any local player
		-- Was it the local player?
		if (localPlayer == player) then
			OnLocalPlayerTurnEnd();
		end
	end
end

-- ===========================================================================
function OnTeamVictory(team, victory, eventID)

	local localPlayer = Game.GetLocalPlayer();
	if (localPlayer and localPlayer >= 0) then		-- Check to see if there is any local player
		OnLocalPlayerTurnEnd();
	end
end

-- ===========================================================================
--	Engine Event
-- ===========================================================================
function OnUserRequestClose()
	-- Is this showing; if so then it needs to raise dialog to handle close
	if (not ContextPtr:IsHidden()) then
		m_kPopupDialog:Reset();
		m_kPopupDialog:AddText(Locale.Lookup("LOC_CONFIRM_EXIT_TXT"));
		m_kPopupDialog:AddButton(Locale.Lookup("LOC_YES"), OnQuitYes, nil, nil, "PopupButtonInstanceRed");
		m_kPopupDialog:AddButton(Locale.Lookup("LOC_NO"), nil);
		m_kPopupDialog:Open();
	end
end
function OnQuitYes()
	Events.UserConfirmedClose();
end

-- ===========================================================================
function LateInitialize()
	CreateGroupTypes();
	InitializeDealGroups();
	CreatePanels();
end

-- ===========================================================================
function Initialize()

	ContextPtr:SetInitHandler( OnInit );
	ContextPtr:SetInputHandler( InputHandler, true );
	ContextPtr:SetShutdown( OnShutdown );
	ContextPtr:SetShowHandler( OnShow );
	ContextPtr:SetHideHandler( OnHide );
	SRA_CreateLists();										-- ScreenReaderAccess
	ContextPtr:SetUpdate( SRA_OnUpdate );					-- ScreenReaderAccess

	SRListen( Events.LocalPlayerTurnEnd, OnLocalPlayerTurnEnd );		-- ScreenReaderAccess: SRListen instead of .Add()
	SRListen( Events.PlayerDefeat, OnPlayerDefeat );
	SRListen( Events.TeamVictory, OnTeamVictory );

	SRListen( Events.UserRequestClose, OnUserRequestClose );
	SRListen( LuaEvents.SRA_DealStatement, SRA_OnStatement );		-- ScreenReaderAccess

	m_kPopupDialog = PopupDialog:new( "DiplomacyDealView" );

	ContextPtr:BuildInstanceForControl("MyOffers", g_uiMyOffers, Controls.MyOfferScroll);
	ContextPtr:BuildInstanceForControl("TheirOffers", g_uiTheirOffers, Controls.TheirOfferScroll);

	g_uiMyOffers.CityDealsExpandButton:RegisterCallback(Mouse.eLClick, function() OnDealsHeaderCollapseButton(g_uiMyOffers.CityDealsStack, g_uiMyOffers.MinimizedCityDealsStack, g_uiMyOffers.CityDealsExpandButton); end);
	g_uiTheirOffers.CityDealsExpandButton:RegisterCallback(Mouse.eLClick, function() OnDealsHeaderCollapseButton(g_uiTheirOffers.CityDealsStack, g_uiTheirOffers.MinimizedCityDealsStack, g_uiTheirOffers.CityDealsExpandButton); end);

	g_uiMyOffers.GreatWorksDealsExpandButton:RegisterCallback(Mouse.eLClick, function() OnDealsHeaderCollapseButton(g_uiMyOffers.GreatWorksDealsStack, g_uiMyOffers.MinimizedGreatWorksDealsStack, g_uiMyOffers.GreatWorksDealsExpandButton); end);
	g_uiTheirOffers.GreatWorksDealsExpandButton:RegisterCallback(Mouse.eLClick, function() OnDealsHeaderCollapseButton(g_uiTheirOffers.GreatWorksDealsStack, g_uiTheirOffers.MinimizedGreatWorksDealsStack, g_uiTheirOffers.GreatWorksDealsExpandButton); end);

	g_uiMyOffers.AgreementDealsExpandButton:RegisterCallback(Mouse.eLClick, function() OnDealsHeaderCollapseButton(g_uiMyOffers.AgreementDealsStack, g_uiMyOffers.MinimizedAgreementDealsStack, g_uiMyOffers.AgreementDealsExpandButton); end);
	g_uiTheirOffers.AgreementDealsExpandButton:RegisterCallback(Mouse.eLClick, function() OnDealsHeaderCollapseButton(g_uiTheirOffers.AgreementDealsStack, g_uiTheirOffers.MinimizedAgreementDealsStack, g_uiTheirOffers.AgreementDealsExpandButton); end);

	g_uiMyOffers.CaptivesDealsExpandButton:RegisterCallback(Mouse.eLClick, function() OnDealsHeaderCollapseButton(g_uiMyOffers.CaptivesDealsStack, g_uiMyOffers.MinimizedCaptivesDealsStack, g_uiMyOffers.CaptivesDealsExpandButton); end);
	g_uiTheirOffers.CaptivesDealsExpandButton:RegisterCallback(Mouse.eLClick, function() OnDealsHeaderCollapseButton(g_uiTheirOffers.CaptivesDealsStack, g_uiTheirOffers.MinimizedCaptivesDealsStack, g_uiTheirOffers.CaptivesDealsExpandButton); end);

	m_OffersStartSizeY = Controls.OfferColumns:GetSizeY();
	m_InvStartSizeY = Controls.InventoryColumns:GetSizeY();

	Controls.DragButton:SetOffsetY(m_InvStartSizeY - 20);

	m_StartingMouseX, m_StartingMouseY = Controls.DragButton:GetScreenOffset();
	m_StartingMouseY = m_StartingMouseY + 24;
	m_MinDragResizeY = m_MinDragResizeY - m_InvStartSizeY;

	Controls.DragSizer:RegisterCallback(Drag.eDrag, function() OnDragResizer(); end);

	--This option requires a restart after changing, so we only need to check it at initialize
	local replaceDragWithClick : number = Options.GetUserOption("Interface", "ReplaceDragWithClick");
	if(replaceDragWithClick == 1)then
		Controls.DragButton:LocalizeAndSetToolTip("LOC_DIPLOMACY_DRAG_BUTTON_CLICK_TOOLTIP");
	end
end

-- This wildcard include will include all loaded files beginning with "DiplomacyDealView_"
-- This method replaces the uses of include("DiplomacyDealView") in files that want to override
-- functions from this file. If you're implementing a new "DiplomacyDealView_" file DO NOT include this file.
include("DiplomacyDealView_", true);

-- ===========================================================================
-- Begin ScreenReaderAccess change: keyboard navigation and speech for the deal screen
-- (docs/ingame-plan.md, "Deal screen"). Four sections, Tab / Shift+Tab cycle through them:
--   1 Deal         what is in the deal (Enter or Delete removes an item, Left/Right change an amount)
--   2 Your items   what you can add (the records the Populate* functions keep in m_srAvail)
--   3 Their items  the same for the other side
--   4 Actions      the visible buttons (Propose / Accept, What would it take?, Never mind ...)
-- Each section is a KeyNavList rebuilt from the game's state at key time; Enter runs the callback of the icon or
-- button itself. The agreement option popup (alliance type, war target ...) is a fifth list that owns the keys
-- while it is open. The AI's answers (leader text, changed deal) are spoken from the update loop once things have
-- settled. Every keyboard event is swallowed while the screen is shown.
-- ===========================================================================
local SRA_SECTIONS:table = { "Deal", "Your items", "Their items", "Actions" };
local SRA_ACTION_BUTTONS:table = { "AcceptDeal", "DemandDeal", "EqualizeDeal", "ResumeGame", "RefuseDeal" };
local SRA_ACTION_HELP:table = {
	AcceptDeal = "Sends your proposal to the other side, or accepts the deal when they have agreed to it",
	DemandDeal = "Makes your demand",
	EqualizeDeal = "Asks the other side what they would want, or give, to make the deal work",
	ResumeGame = "Closes the deal screen and goes back to the game, the deal stays pending",
	RefuseDeal = "Leaves the deal, or refuses the offer",
};
local SRA_AVAILABLE_SECTION:table = { agreement = "Agreements", city = "Cities", greatwork = "Great works", captive = "Captives" };

local m_srLists:table = {};
local m_srOptList:table = nil;
local m_srSection:number = 1;
local m_srShown:boolean = false;			-- OnShow ran (so OnHide may speak)
local m_srAnnounced:boolean = false;		-- the opening announcement was spoken (changes may be spoken now)
local m_srOpenWait:number = -1;				-- seconds until the opening announcement, -1 = none pending
local m_srFlushWait:number = -1;			-- seconds until changes are spoken, -1 = none pending
local m_srIncomingAction = nil;				-- the last DealProposalAction the other side sent, until spoken
local m_srLeaderText:string = "";			-- what the leader says now (set by SetLeaderDialog)
local m_srSpokenLeader:string = "";
local m_srSpokenSig:string = "";			-- the deal summary as last spoken
local m_srAcceptTime = nil;					-- when the final Accept was pressed, so the hide says "Deal accepted"
local m_srStatementTime = nil;				-- UI.GetElapsedTime() when it arrived
local m_srStatement = nil;					-- what the leader said when the deal was opened (LuaEvents.SRA_DealStatement from DiplomacyActionView)

local function SRA_Say( text:string, nointerrupt:boolean )
	OutputMessageToScreenReader( text, nointerrupt );
end

local function SRA_Clean( text:string )
	return CleanTextForSpeech( text or "" );
end

local function SRA_Plural( n:number, word:string )
	return n .. " " .. word .. ( n == 1 and "" or "s" );
end

local function SRA_LookupText( id )
	if id == nil then return nil; end
	return SRA_Clean( Locale.Lookup( id ) );
end

-- A demand made to us cannot be edited; a gift or demand from the other side cannot get new items.
local function SRA_IsDemandToUs()
	return ms_bIsDemand == true and ms_InitiatedByPlayerID == ms_OtherPlayerID;
end

local function SRA_CannotAdd()
	return ( ms_bIsDemand == true or ms_bIsGift == true ) and ms_InitiatedByPlayerID == ms_OtherPlayerID;
end

-- ---------------------------------------------------------------------------
--	The deal as plain records
-- ---------------------------------------------------------------------------
local function SRA_WorkingDeal()
	if g_LocalPlayer == nil or g_OtherPlayer == nil then return nil; end
	return DealManager.GetWorkingDeal( DealDirection.OUTGOING, g_LocalPlayer:GetID(), g_OtherPlayer:GetID() );
end

local function SRA_ItemRecord( pDeal:table, pDealItem:table )
	local itemType:number = pDealItem:GetType();
	local rec:table = { id = pDealItem:GetID(), from = pDealItem:GetFromPlayerID(), amount = pDealItem:GetAmount(), duration = pDealItem:GetDuration() };
	if itemType == DealItemTypes.GOLD then
		rec.kind = "gold";
	elseif DealItemTypes.FAVOR ~= nil and itemType == DealItemTypes.FAVOR then
		rec.kind = "favor";
	elseif itemType == DealItemTypes.RESOURCES then
		rec.kind = "resource";
		local desc:table = GameInfo.Resources[ pDealItem:GetValueType() ];
		rec.name = ( desc ~= nil ) and Locale.Lookup( desc.Name ) or SRA_LookupText( pDealItem:GetValueTypeNameID() );
	elseif itemType == DealItemTypes.AGREEMENTS then
		rec.kind = "agreement";
		rec.name = SRA_LookupText( pDealItem:GetSubTypeNameID() );
		rec.detail = SRA_LookupText( pDealItem:GetValueTypeNameID() );
	elseif itemType == DealItemTypes.CITIES then
		rec.kind = "city";
		rec.name = SRA_LookupText( pDealItem:GetValueTypeNameID() );
	elseif itemType == DealItemTypes.GREATWORK then
		rec.kind = "greatwork";
		rec.name = SRA_LookupText( pDealItem:GetValueTypeNameID() );
	elseif itemType == DealItemTypes.CAPTIVE then
		rec.kind = "captive";
		rec.name = SRA_LookupText( pDealItem:GetValueTypeNameID() );
	else
		rec.kind = "other";
		rec.name = SRA_LookupText( pDealItem:GetValueTypeNameID() ) or SRA_LookupText( pDealItem:GetSubTypeNameID() );
	end
	-- the identity of an item across repopulates (the game re-creates an item when its amount changes: the ID changes)
	rec.key = rec.from .. ":" .. itemType .. ":" .. tostring( pDealItem:GetSubType() ) .. ":" .. tostring( pDealItem:GetValueType() ) .. ":" .. rec.duration;
	rec.locked = pDealItem:IsLocked();
	rec.unacceptable = pDealItem:IsUnacceptable();
	rec.hasParent = pDeal:GetItemParent( pDealItem ) ~= nil;
	rec.editable = IsItemValueEditable( itemType ) and not rec.locked and not rec.hasParent;
	if rec.editable then rec.max = pDealItem:GetMaxAmount(); end
	return rec;
end

-- What you give, what they give.
local function SRA_DealRecords()
	local give:table, get:table = {}, {};
	local pDeal:table = SRA_WorkingDeal();
	if pDeal == nil then return give, get; end
	local localID:number = g_LocalPlayer:GetID();
	for pDealItem in pDeal:Items() do
		local rec:table = SRA_ItemRecord( pDeal, pDealItem );
		if rec.from == localID then table.insert( give, rec ); else table.insert( get, rec ); end
	end
	return give, get;
end

local function SRA_DealTexts()
	local texts:table = {};
	local give:table, get:table = SRA_DealRecords();
	for _, rec in ipairs( give ) do table.insert( texts, DealSpeech_DealItemText( rec, true ) ); end
	for _, rec in ipairs( get ) do table.insert( texts, DealSpeech_DealItemText( rec, false ) ); end
	return texts;
end

local function SRA_Summary()
	local give:table, get:table = SRA_DealRecords();
	return DealSpeech_Summary( give, get );
end

-- Says what a click or key changed in the deal, then the whole deal; remembers the deal as spoken.
local function SRA_SpeakChange( before:table, fallback:string )
	local change = DealSpeech_ChangeText( before, SRA_DealTexts() );
	local give:table, get:table = SRA_DealRecords();
	local summary:string = DealSpeech_Summary( give, get );
	m_srSpokenSig = summary;
	local giveTexts:table, getTexts:table = {}, {};
	for _, rec in ipairs( give ) do table.insert( giveTexts, DealSpeech_DealItemText( rec, true ) ); end
	for _, rec in ipairs( get ) do table.insert( getTexts, DealSpeech_DealItemText( rec, false ) ); end
	SRA_Say( DealSpeech_ChangeSpeech( change, giveTexts, getTexts, summary, fallback ) );
end

-- ---------------------------------------------------------------------------
--	Section 1: the deal
-- ---------------------------------------------------------------------------
local function SRA_DealItemDetail( rec:table, mine:boolean )
	local parts:table = { DealSpeech_DealItemText( rec, mine ) };
	if rec.locked then
		table.insert( parts, "Locked, it can't be removed" );
	elseif rec.hasParent then
		table.insert( parts, "Comes with a city in the deal and goes when the city is removed" );
	elseif SRA_IsDemandToUs() then
		table.insert( parts, "Part of the demand made to you, you can't change it" );
	else
		if rec.editable then
			table.insert( parts, "Left and Right change the amount by 1, with Shift by 10" .. ( rec.max ~= nil and ( ", up to " .. rec.max ) or "" ) );
		end
		table.insert( parts, "Enter or Delete removes it" );
	end
	if rec.unacceptable then table.insert( parts, "The other side has marked this unacceptable" ); end
	return table.concat( parts, ". " );
end

local function SRA_DealItems()
	local items:table = {};
	local give:table, get:table = SRA_DealRecords();
	local function Add( rec:table, mine:boolean )
		local text:string = DealSpeech_DealItemText( rec, mine );
		if rec.locked then text = text .. ", locked"; end
		if rec.hasParent then text = text .. ", comes with a city"; end
		if rec.unacceptable then text = text .. ", unacceptable"; end
		table.insert( items, { key = "d:" .. rec.key, text = text, rec = rec, detail = function() return SRA_DealItemDetail( rec, mine ); end } );
	end
	for _, rec in ipairs( give ) do Add( rec, true ); end
	for _, rec in ipairs( get ) do Add( rec, false ); end
	if #items == 0 then
		items[1] = { key = "empty", empty = true, text = "Deal is empty", choosable = false, reason = "Deal is empty. Add items from Your items or Their items",
			detail = "Tab switches to Your items and Their items, Enter on an item adds it to the deal" };
	end
	return items;
end

local function SRA_RemoveItem( item:table )
	if item == nil or item.rec == nil then SRA_Say( "Nothing to remove" ); return; end
	local rec:table = item.rec;
	if SRA_IsDemandToUs() then SRA_Say( "Can't remove it, this is a demand made to you" ); return; end
	if rec.locked then SRA_Say( "Can't remove it, it is locked in by the agreement" ); return; end
	if rec.hasParent then SRA_Say( "Can't remove it, it comes with a city. Remove the city instead" ); return; end
	local before:table = SRA_DealTexts();
	local player:table = ( rec.from == g_LocalPlayer:GetID() ) and g_LocalPlayer or g_OtherPlayer;
	OnRemoveDealItem( player, rec.id );
	m_srLists[1].Reset();
	SRA_SpeakChange( before, "Could not remove it" );
end

local function SRA_FocusedItem( section:number )
	local key = m_srLists[ section ].GetFocusKey();
	if key == nil then return nil; end
	local items:table = ( section == 1 ) and SRA_DealItems() or nil;
	for _, item in ipairs( items or {} ) do
		if item.key == key then return item; end
	end
	return nil;
end

local function SRA_KeyDelete()
	SRA_RemoveItem( SRA_FocusedItem( 1 ) );
end

-- Left / Right in the deal section: the amount of a gold, resource or favor item, through the game's own
-- value edit (the edit box text and OnValueEditButton, what the popup's OK button does).
local function SRA_ChangeAmount( delta:number )
	local item:table = SRA_FocusedItem( 1 );
	if item == nil or item.rec == nil then SRA_Say( "Select an item first" ); return; end
	local rec:table = item.rec;
	if SRA_IsDemandToUs() then SRA_Say( "You can't change a demand made to you" ); return; end
	if not rec.editable then SRA_Say( "This item has no amount to change" ); return; end
	local pDeal:table = SRA_WorkingDeal();
	local pDealItem:table = ( pDeal ~= nil ) and pDeal:FindItemByID( rec.id ) or nil;
	if pDealItem == nil then SRA_Say( "Item no longer available" ); return; end
	local current:number = pDealItem:GetAmount();
	local target:number = clip( current + delta, 1, pDealItem:GetMaxAmount() );
	if target == current then
		SRA_Say( ( delta > 0 and "Already at the maximum, " or "Already at the minimum, " ) .. DealSpeech_ItemText( rec ) );
		return;
	end
	Controls.ValueAmountEditBox:SetText( tostring( target ) );
	OnValueEditButton( rec.id );
	-- the game re-created the item (new ID): find it again by its identity
	local give:table, get:table = SRA_DealRecords();
	m_srSpokenSig = DealSpeech_Summary( give, get );
	for _, list in ipairs( { give, get } ) do
		for _, newRec in ipairs( list ) do
			if newRec.key == rec.key then
				SRA_Say( DealSpeech_ItemText( newRec ) .. ( ( newRec.amount ~= target ) and ", the most possible" or "" ) );
				return;
			end
		end
	end
	SRA_Say( m_srSpokenSig );
end

-- ---------------------------------------------------------------------------
--	Sections 2 and 3: the items that can be added
-- ---------------------------------------------------------------------------
local function SRA_AvailableDetail( rec:table )
	local parts:table = { DealSpeech_AvailableText( rec ) };
	local tip = rec.tooltip;
	if type( tip ) == "function" then tip = tip(); end
	if tip ~= nil and tip ~= "" then table.insert( parts, SRA_Clean( tip ) ); end
	if rec.hint ~= nil then table.insert( parts, rec.hint ); end
	return table.concat( parts, ". " );
end

local function SRA_AvailableItems( playerType:number )
	local items:table = {};
	for _, rec in ipairs( m_srAvail[ playerType ] ) do
		table.insert( items, { key = "a:" .. rec.key, text = DealSpeech_AvailableText( rec ), section = SRA_AVAILABLE_SECTION[ rec.kind ], rec = rec,
			choosable = ( rec.enabled ~= false ), reason = ( rec.reason ~= nil ) and ( "Unavailable: " .. rec.reason ) or "Unavailable",
			detail = function() return SRA_AvailableDetail( rec ); end } );
	end
	return items;
end

local function SRA_OptionsOpen()
	return #m_srOptions > 0 and not Controls.ValueEditPopupBackground:IsHidden();
end

local function SRA_OptionItems()
	local items:table = {};
	for _, opt in ipairs( m_srOptions ) do
		local text:string = SRA_Clean( ( string.gsub( opt.text or "", "%[[nN][eE][wW][lL][iI][nN][eE]%]", ", " ) ) );
		table.insert( items, { key = opt.key, text = text, opt = opt, detail = ( opt.tooltip ~= nil and opt.tooltip ~= "" ) and SRA_Clean( opt.tooltip ) or nil } );
	end
	return items;
end

local m_srBeforeOption:table = {};		-- the deal as it was when an option popup opened

local function SRA_OpenOptions()
	m_srOptList.Reset();
	local header:string = SRA_Clean( Controls.ValueEditHeaderLabel:GetText() );
	m_srOptList.Open( header ~= "" and header or "Choose an option" );
end

local function SRA_OnAvailableActivate( item:table )
	if SRA_CannotAdd() then SRA_Say( "You can't add to this offer" ); return; end
	local before:table = SRA_DealTexts();
	m_srBeforeOption = before;
	item.rec.callback();
	if SRA_OptionsOpen() then SRA_OpenOptions(); return; end
	SRA_SpeakChange( before, "Nothing added, it is already in the deal or not possible" );
end

local function SRA_OnOptionActivate( item:table )
	item.opt.callback();
	m_srOptions = {};
	SRA_SpeakChange( m_srBeforeOption, "Nothing added" );
end

local function SRA_OnOptionsClose()
	OnAgreementBackButton();
	m_srOptions = {};
	SRA_Say( "Back" );
end

-- ---------------------------------------------------------------------------
--	Section 4: the buttons
-- ---------------------------------------------------------------------------
local function SRA_ButtonLabel( ctl:table )
	local ok:boolean, label = pcall( function() return ctl:GetTextControl():GetText(); end );
	if ok and label ~= nil then return SRA_Clean( label ); end
	return "";
end

local function SRA_ActionItems()
	local items:table = {};
	for _, id in ipairs( SRA_ACTION_BUTTONS ) do
		local ctl:table = Controls[ id ];
		if ctl ~= nil and not ctl:IsHidden() then
			local label:string = SRA_ButtonLabel( ctl );
			if label == "" then label = id; end
			local disabled:boolean = ctl:IsDisabled();
			local ok:boolean, tip = pcall( function() return ctl:GetToolTipString(); end );
			local detail:string = SRA_ACTION_HELP[ id ] or label;
			if ok and tip ~= nil and tip ~= "" then detail = SRA_Clean( tip ) .. ". " .. detail; end
			table.insert( items, { key = "act:" .. id, id = id, label = label, text = label .. ( disabled and ", unavailable" or "" ),
				choosable = not disabled, reason = label .. " is unavailable", detail = detail } );
		end
	end
	return items;
end

local function SRA_ActionNames()
	local names:table = {};
	for _, item in ipairs( SRA_ActionItems() ) do table.insert( names, item.text ); end
	return table.concat( names, ", " );
end

function SRA_Touch()
	m_srFlushWait = 0.45;
end

local function SRA_OnActionActivate( item:table )
	local id:string = item.id;
	SRA_Say( item.label );
	m_srAcceptTime = nil;
	if id == "AcceptDeal" or id == "DemandDeal" then
		-- the final accept (the deal is equal on both sides) closes the screen: remember it for the hide
		local act = ms_LastIncomingDealProposalAction;
		if id == "AcceptDeal" and ( act == DealProposalAction.ACCEPTED or act == DealProposalAction.PROPOSED or act == DealProposalAction.ADJUSTED )
				and DealManager.AreWorkingDealsEqual( g_LocalPlayer:GetID(), g_OtherPlayer:GetID() ) then
			m_srAcceptTime = UI.GetElapsedTime();
		end
		OnProposeOrAcceptDeal();
	elseif id == "EqualizeDeal" then
		OnEqualizeDeal();
	elseif id == "RefuseDeal" then
		OnRefuseDeal();
	elseif id == "ResumeGame" then
		OnResumeGame();
	end
	SRA_Touch();
end

-- ---------------------------------------------------------------------------
--	Sections, opening announcement, answers of the other side
-- ---------------------------------------------------------------------------
local function SRA_BuildSection( n:number )
	if n == 1 then return SRA_DealItems(); end
	if n == 2 then return SRA_AvailableItems( LOCAL_PLAYER ); end
	if n == 3 then return SRA_AvailableItems( OTHER_PLAYER ); end
	return SRA_ActionItems();
end

local function SRA_EnterSection( n:number )
	m_srSection = n;
	local items:table = SRA_BuildSection( n );
	local count:number = #items;
	if n == 1 and count == 1 and items[1].empty then count = 0; end
	local name:string = SRA_SECTIONS[ n ];
	if n == 1 and count == 0 then
		SRA_Say( "Deal, empty. Tab to Your items or Their items to add something" );
		return;
	end
	if count == 0 then
		SRA_Say( name .. ", nothing available" );
		return;
	end
	SRA_Say( name .. ", " .. SRA_Plural( count, "item" ) );
	local focusKey = m_srLists[ n ].GetFocusKey();
	if n == 4 then
		-- the buttons come and go (Accept appears once the deal is valid): never keep a stale focus, start on the first enabled one
		focusKey = items[1].key;
		for _, item in ipairs( items ) do
			if item.choosable then focusKey = item.key; break; end
		end
	end
	m_srLists[ n ].Focus( focusKey, "" );		-- the list speaks the focused item after the section name
end

local function SRA_CycleSection( delta:number )
	SRA_EnterSection( ( ( m_srSection - 1 + delta ) % 4 ) + 1 );
end

local function SRA_SpeakStatus()
	local summary:string = SRA_Summary();
	local parts:table = { summary };
	if m_srLeaderText ~= "" then table.insert( parts, m_srLeaderText ); end
	local actions:string = SRA_ActionNames();
	if actions ~= "" then table.insert( parts, "Actions: " .. actions ); end
	m_srSpokenSig = summary;
	m_srSpokenLeader = m_srLeaderText;
	SRA_Say( table.concat( parts, " " ) );
end

local function SRA_Announce()
	m_srAnnounced = true;
	if g_OtherPlayer == nil or g_LocalPlayer == nil then return; end
	local config:table = PlayerConfigurations[ g_OtherPlayer:GetID() ];
	local leader:string = Locale.Lookup( config:GetLeaderName() );
	local civ:string = Locale.Lookup( config:GetCivilizationShortDescription() );
	local theirs:boolean = ( ms_InitiatedByPlayerID == ms_OtherPlayerID );
	local mode:string = "make";
	if theirs then
		mode = ms_bIsDemand and "theirdemand" or ( ms_bIsGift and "theirgift" or "theirdeal" );
	elseif ms_bIsDemand then
		mode = "demand";
	end
	local summary:string = SRA_Summary();
	local parts:table = { DealSpeech_Intro( leader, civ, mode ) };
	-- a statement handed over while nobody opened the deal screen is stale: only use one from the last 3 seconds
	if m_srStatement ~= nil and m_srStatement ~= "" and m_srStatementTime ~= nil and UI.GetElapsedTime() - m_srStatementTime < 3 then
		table.insert( parts, m_srStatement );
	end
	m_srStatement = nil;
	if m_srLeaderText ~= "" and m_srLeaderText ~= parts[2] then table.insert( parts, m_srLeaderText ); end
	table.insert( parts, summary );
	if theirs then
		local actions:string = SRA_ActionNames();
		if actions ~= "" then table.insert( parts, "Actions: " .. actions .. "." ); end
	end
	table.insert( parts, "Tab switches sections: Deal, Your items, Their items, Actions. S reads the summary. Control+Tab goes back a section." );
	m_srSpokenLeader = m_srLeaderText;
	m_srSpokenSig = summary;
	SRA_Say( table.concat( parts, " " ), true );
end

-- Called by OnShow: the announcement comes from the update loop once the screen has settled.
function SRA_ArmOpen()
	m_srShown = true;
	m_srAnnounced = false;
	m_srOpenWait = 0.4;
	m_srFlushWait = -1;
	m_srIncomingAction = nil;
	m_srAcceptTime = nil;
	m_srSection = ( ms_InitiatedByPlayerID == ms_OtherPlayerID ) and 4 or 1;
	for _, list in ipairs( m_srLists ) do list.Reset(); end
	if m_srOptList ~= nil then m_srOptList.Reset(); end
end

-- SetLeaderDialog was called: remember what the leader says (spoken by the next flush when it changed).
function SRA_NoteLeader( dialog:string, effect:string )
	local text:string = SRA_Clean( Locale.Lookup( dialog or "" ) );
	if effect ~= nil and effect ~= "" then
		local effectText:string = SRA_Clean( Locale.Lookup( effect ) );
		if effectText ~= "" then text = text .. ". " .. effectText; end
	end
	m_srLeaderText = text;
	SRA_Touch();
end

function SRA_OnStatement( text:string )
	m_srStatement = text;
	m_srStatementTime = UI.GetElapsedTime();
end

-- The other side sent a new version of the deal (or answered it).
function SRA_NoteIncoming( eAction )
	if ContextPtr:IsHidden() then return; end
	m_srIncomingAction = eAction;
	SRA_Touch();
end

-- Speaks the answer of the other side and every change of the leader's text or the deal that nobody has spoken yet.
local function SRA_Flush()
	if not m_srAnnounced or ContextPtr:IsHidden() then return; end
	local parts:table = {};
	local action = m_srIncomingAction;
	m_srIncomingAction = nil;
	if action == DealProposalAction.ACCEPTED then
		table.insert( parts, "They accept the deal." );
	elseif action == DealProposalAction.REJECTED or action == DealProposalAction.REJECTED_PERMANENT then
		table.insert( parts, "They reject the deal." );
	elseif action == DealProposalAction.EQUALIZE_FAILED then
		table.insert( parts, "They can't find a way to make it work." );
	end
	if m_srLeaderText ~= "" and m_srLeaderText ~= m_srSpokenLeader then
		table.insert( parts, m_srLeaderText );
		m_srSpokenLeader = m_srLeaderText;
	end
	local summary:string = SRA_Summary();
	if summary ~= m_srSpokenSig then
		table.insert( parts, "Deal changed. " .. summary );
		m_srSpokenSig = summary;
	end
	if #parts > 0 then
		if action ~= nil then
			local actions:string = SRA_ActionNames();
			if actions ~= "" then table.insert( parts, "Actions: " .. actions .. "." ); end
		end
		SRA_Say( table.concat( parts, " " ), true );
	end
end

function SRA_OnHide()
	if not m_srShown then return; end
	m_srShown = false;
	m_srAnnounced = false;
	m_srStatement = nil;
	m_srOpenWait = -1;
	m_srFlushWait = -1;
	local accepted:boolean = ( m_srAcceptTime ~= nil and UI.GetElapsedTime() - m_srAcceptTime < 5 );
	m_srAcceptTime = nil;
	SRA_Say( accepted and "Deal accepted" or "Deal closed", true );
end

function SRA_OnUpdate( deltaTime:number )
	if m_srOpenWait >= 0 then
		m_srOpenWait = m_srOpenWait - deltaTime;
		if m_srOpenWait < 0 then
			m_srOpenWait = -1;
			local ok:boolean, err = xpcall( SRA_Announce, KeyNavErrorHandler );
			if not ok then print( "DiplomacyDealView announce error: " .. tostring( err ) ); end
		end
		return;
	end
	if m_srFlushWait >= 0 then
		m_srFlushWait = m_srFlushWait - deltaTime;
		if m_srFlushWait < 0 then
			m_srFlushWait = -1;
			local ok:boolean, err = xpcall( SRA_Flush, KeyNavErrorHandler );
			if not ok then print( "DiplomacyDealView flush error: " .. tostring( err ) ); end
		end
	end
end

-- ---------------------------------------------------------------------------
--	Input
-- ---------------------------------------------------------------------------
local function SRA_Escape()
	HandleESC();
end

local function SRA_HandleKey( input:table, key:number, isUp:boolean )
	if m_kPopupDialog:IsOpen() then
		-- the game's own popup (nothing to trade, stop asking, quit): same keys as the diplomacy screen's popups
		if isUp then
			if key == Keys.VK_ESCAPE then m_kPopupDialog:Close(); else m_kPopupDialog:KeyHandler( key ); end
		end
		return;
	end
	if SRA_OptionsOpen() then
		m_srOptList.HandleInput( input );
		return;
	end
	if key == Keys.VK_TAB then
		if isUp then SRA_CycleSection( ( input:IsShiftDown() or input:IsControlDown() ) and -1 or 1 ); end
		return;
	end
	if key == Keys.S and not input:IsShiftDown() and not input:IsControlDown() and not input:IsAltDown() then
		if isUp then SRA_SpeakStatus(); end
		return;
	end
	if m_srSection == 1 and ( key == Keys.VK_LEFT or key == Keys.VK_RIGHT ) then
		if isUp then
			local step:number = input:IsShiftDown() and 10 or 1;
			SRA_ChangeAmount( ( key == Keys.VK_RIGHT ) and step or -step );
		end
		return;
	end
	m_srLists[ m_srSection ].HandleInput( input );
end

-- Every keyboard event is swallowed while the screen is shown (nothing may reach the hub, the world or the
-- diplomacy screen behind); mouse events pass on.
function SRA_HandleInput( pInputStruct:table )
	if ContextPtr:IsHidden() or m_srLists[1] == nil then return false; end
	local msg:number = pInputStruct:GetMessageType();
	if msg ~= KeyEvents.KeyDown and msg ~= KeyEvents.KeyUp then return false; end
	local isUp:boolean = ( msg == KeyEvents.KeyUp );
	local key:number = pInputStruct:GetKey();
	local ok:boolean, err = xpcall( function() SRA_HandleKey( pInputStruct, key, isUp ); end, KeyNavErrorHandler );
	if not ok then print( "DiplomacyDealView input error: " .. tostring( err ) ); end
	return true;
end

function SRA_CreateLists()
	local function Active( section:number )
		return function()
			return not ContextPtr:IsHidden() and m_srSection == section and not SRA_OptionsOpen() and not m_kPopupDialog:IsOpen();
		end
	end
	m_srLists[1] = KeyNavList_Create{ build = SRA_DealItems, isActive = Active( 1 ), onActivate = SRA_RemoveItem, onClose = SRA_Escape,
		extraKeys = { [ Keys.VK_DELETE ] = SRA_KeyDelete } };
	m_srLists[2] = KeyNavList_Create{ build = function() return SRA_AvailableItems( LOCAL_PLAYER ); end, isActive = Active( 2 ), onActivate = SRA_OnAvailableActivate, onClose = SRA_Escape };
	m_srLists[3] = KeyNavList_Create{ build = function() return SRA_AvailableItems( OTHER_PLAYER ); end, isActive = Active( 3 ), onActivate = SRA_OnAvailableActivate, onClose = SRA_Escape };
	m_srLists[4] = KeyNavList_Create{ build = SRA_ActionItems, isActive = Active( 4 ), onActivate = SRA_OnActionActivate, onClose = SRA_Escape };
	m_srOptList = KeyNavList_Create{ build = SRA_OptionItems, isActive = function() return not ContextPtr:IsHidden() and SRA_OptionsOpen() and not m_kPopupDialog:IsOpen(); end,
		onActivate = SRA_OnOptionActivate, onClose = SRA_OnOptionsClose };
end

-- Gathering Storm adds diplomatic favor (PopulateAvailableFavor lives in DiplomacyDealView_Expansion2.lua, included
-- above): wrap it to record the favor icon too.
if PopulateAvailableFavor ~= nil and OnClickAvailableOneTimeFavor ~= nil then
	local SRA_PopulateAvailableFavor = PopulateAvailableFavor;
	function PopulateAvailableFavor( player:table, iconList:table )
		local count:number = SRA_PopulateAvailableFavor( player, iconList );
		if count > 0 then
			SRA_AddAvail( player, { key = "favor", kind = "favor", amount = player:GetFavor(),
				hint = "Enter adds 1 diplomatic favor. Change the amount in the Deal section with Left and Right",
				callback = function() OnClickAvailableOneTimeFavor( player, 1 ); end } );
		end
		return count;
	end
end
print( "ScreenReaderAccess: DiplomacyDealView copy loaded" );		-- the verifier looks for this line in Lua.log
-- End ScreenReaderAccess change

Initialize();
