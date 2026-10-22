-- Copyright 2020, Firaxis Games

-- ===========================================================================
--	UI for managing and appointing Governors	
-- ===========================================================================

include("InstanceManager");
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

local RELOAD_CACHE_ID:string = "GovernorDetailsPanel"; -- Must be unique (usually the same as the file name)

local PROMOTION_X_OFFSET = 110;
local PROMOTION_Y_OFFSET = 147;
local PROMOTION_LINE_Y_OFFSET = 77;
local EXTRA_MIDDLE_PROMOTION_LINE_X_OFFSET = 20;
local PROMOTION_NAME_TRUNCATE_WIDTH = 195;

-- ===========================================================================
--	VARIABLES
-- ===========================================================================

local m_PromotionTreeIM:table = InstanceManager:new("PromotionTreeInstance", "TopGrid", Controls.PromotionAnchor);
local m_SecretPromotionTreeIM:table = InstanceManager:new("SecretSocietyPromotionTreeInstance", "TopGrid", Controls.PromotionAnchor);

local m_PromotionIM:table = InstanceManager:new("PromotionInstance", "PromotionButton");
local m_SecretPromotionIM:table = InstanceManager:new("SecretSocietyPromotionInstance", "PromotionButton");

local m_ReqLinesLeftIM:table = InstanceManager:new("ReqLinesLeft", "Top");
local m_ReqLinesRightIM:table = InstanceManager:new("ReqLinesRight", "Top");
local m_ReqLinesDownIM:table = InstanceManager:new("ReqLinesDown", "Top");

local m_GovernorIndex:number = -1;

local m_SelectedPromotion:number = -1;

local m_TopPanelConsideredHeight:number = 0;

local m_isReadOnly : boolean = false;
local m_srList:table = nil;		-- ScreenReaderAccess: promotion list
-- ===========================================================================
function Refresh()
	local localPlayerID:number = Game.GetLocalPlayer();
	if m_GovernorIndex == -1 or localPlayerID == PlayerTypes.NONE or localPlayerID == PlayerTypes.OBSERVER then
		return;
	end

	local pGovernorDef:table = GameInfo.Governors[m_GovernorIndex];	
	local pGovernor:table = GetAppointedGovernor(localPlayerID, m_GovernorIndex);
	local pLocalPlayer:table = Players[localPlayerID];
	local pPlayerGovernors:table = pLocalPlayer:GetGovernors();
	local bIsSecretGovernor:boolean = IsCannotAssign(pGovernorDef);

	-- Update governor name and title
	Controls.GovernorNameLabel:SetText(Locale.ToUpper(pGovernorDef.Name));
	Controls.GovernorTitleLabel:SetText(Locale.Lookup(pGovernorDef.Title));
	Controls.GovernorBioLabel:SetText(Locale.Lookup(pGovernorDef.Description));

	-- Show/hide elements based on if this is a secret, non-assignable governor
	if not bIsSecretGovernor then
		Controls.GovernorNamePlaque:SetTexture("Governors_NamePlaque");

		-- Update governor transition strength and identity pressure
		Controls.TransitionStrengthLabel:SetText(pPlayerGovernors:GetTurnsToEstablish(pGovernorDef.Hash));
		Controls.IdentityPressureLabel:SetText(pGovernorDef.IdentityPressure);
		Controls.GovernorStatsContainer:SetHide(false);

		SetGovernorStatus(pGovernorDef, pGovernor);
		Controls.GovernorStatusContainer:SetHide(false);

		Controls.SecretSocietyIcon:SetHide(true);

		-- Update assign button
		if pGovernor then
			local pAssignedCity:table = pGovernor:GetAssignedCity();
			if pAssignedCity then
				Controls.AssignButtonLabel:SetText(Locale.Lookup("LOC_GOVERNORS_SCREEN_BUTTON_REASSIGN_GOVERNOR"));
			else
				Controls.AssignButtonLabel:SetText(Locale.Lookup("LOC_GOVERNORS_SCREEN_BUTTON_ASSIGN_GOVERNOR"));
			end
			Controls.AssignButton:SetVoid1(pGovernorDef.Index);
			Controls.AssignButton:RegisterCallback( Mouse.eLClick, OnAssignGovernor );
			local bCanAssign:boolean = pPlayerGovernors:HasGovernor(pGovernorDef.Hash) and pGovernor:GetNeutralizedTurns() == 0;
			Controls.AssignButton:SetDisabled((not bCanAssign) or m_isReadOnly);
		else
			Controls.AssignButtonLabel:SetText(Locale.Lookup("LOC_GOVERNORS_SCREEN_BUTTON_APPOINT_GOVERNOR"));
			Controls.AssignButton:SetVoid1(pGovernorDef.Index);
			Controls.AssignButton:RegisterCallback( Mouse.eLClick, OnAppointGovernor );
			local bCanAppoint:boolean = pPlayerGovernors:CanAppoint();
			Controls.AssignButton:SetDisabled((not bCanAppoint) or m_isReadOnly);
		end

		Controls.AssignButton:SetHide(false);
		
		Controls.MainContainer:SetTexture("Governors_BackgroundTile_ColumnOff");
	else
		Controls.GovernorNamePlaque:SetTexture("Secret_NamePlaque");

		-- The first, and only, element in SecretSocietyCollection should be the
		-- associated secret society. Safetly looping through it here just as precaution
		local kSecretSocietyDef:table = nil;
		for i, societyDef in ipairs(pGovernorDef.SecretSocietyCollection) do
			if societyDef ~= nil then
				kSecretSocietyDef = societyDef;
				break;
			end
		end

		if kSecretSocietyDef then
			Controls.SecretSocietyIcon:SetTexture(kSecretSocietyDef.SmallIcon);
		end

		Controls.SecretSocietyIcon:SetHide(false);

		Controls.GovernorStatsContainer:SetHide(true);
		Controls.GovernorStatusContainer:SetHide(true);
		Controls.AssignButton:SetHide(true);

		Controls.MainContainer:SetTexture("Secret_Column_BackgroundTile");
	end

	-- Update governor portrait
	Controls.GovernorPortrait:SetTexture(pGovernorDef.PortraitImageSelected);

	m_PromotionTreeIM:ResetInstances();
	m_SecretPromotionTreeIM:ResetInstances();

	if not bIsSecretGovernor then
		CreatePromotionTree(localPlayerID, pGovernor, pGovernorDef, pPlayerGovernors);
	else
		CreateSecretPromotionTree(localPlayerID, pGovernor, pGovernorDef, pPlayerGovernors);
	end

	if m_SelectedPromotion ~= -1 then
		Controls.ConfirmButton:SetHide(false);
		Controls.BackButton:SetHide(true);		
	else
		Controls.ConfirmButton:SetHide(true);
		Controls.BackButton:SetHide(false);
	end
end

-- ===========================================================================
function CreatePromotionTree(localPlayerID:number, pGovernor:table, pGovernorDef:table, pPlayerGovernors:table)
	
	local pPromotionTreeInst:table = m_PromotionTreeIM:GetInstance();

	-- Define promotion tree matrix used to determine promotion requirement lines
	local promotionTreeMatrix:table = {{}, {}, {}};

	-- Create the promotion button instances and fill the promotion matrix
	m_PromotionIM:ResetInstances();
	for promotionSet in GameInfo.GovernorPromotionSets() do
		if promotionSet.GovernorType == pGovernorDef.GovernorType then
			local kPromotion:table = GameInfo.GovernorPromotions[promotionSet.GovernorPromotion];
			
			local sName:string = Locale.ToUpper(kPromotion.Name);
			local sDescription:string = Locale.Lookup(kPromotion.Description);
			if (IsPromotionHidden(kPromotion.Hash, localPlayerID, pGovernorDef.Index)) then
				sName = GetPromotionHiddenName(kPromotion.Hash);
				sDescription = GetPromotionHiddenDescription(kPromotion.Hash);
			end
			
			if kPromotion.BaseAbility then
				local iconName:string = "ICON_" .. pGovernorDef.GovernorType .. "_PROMOTION";
				pPromotionTreeInst.BaseAbilityIcon:SetIcon(iconName);
				pPromotionTreeInst.BaseAbilityLabel:SetText(sDescription);
			else
				if kPromotion.Level ~= 0 then
					local pPromotionInst:table = m_PromotionIM:GetInstance(pPromotionTreeInst.PromotionContainer);
					TruncateStringWithTooltip(pPromotionInst.PromotionName, PROMOTION_NAME_TRUNCATE_WIDTH, sName);
					pPromotionInst.PromotionDesc:SetText(sDescription);

					local xOffset:number = PROMOTION_X_OFFSET * (kPromotion.Column);
					-- Subtract 1 from level to discount the BaseAbility which is the only level 0 promotion
					local yOffset:number = PROMOTION_Y_OFFSET * (kPromotion.Level - 1);
					pPromotionInst.PromotionButton:SetOffsetVal(xOffset, yOffset);

					-- Determine if this promotion can currently be earn by this governor due to requirements, etc
					local canEarnPromotion:boolean = pPlayerGovernors:CanEarnPromotion(pGovernorDef.Hash, kPromotion.Hash);

					-- Update button state and callback depending on the promotion state
					if (pGovernor and pGovernor:HasPromotion(kPromotion.Hash)) then
						pPromotionInst.PromotionButton:SetDisabled(true);
						pPromotionInst.PromotionButton:SetVisState(4);
						pPromotionInst.PromotionButton:ClearCallback( Mouse.eLClick );
					elseif m_SelectedPromotion == kPromotion.Index then
						pPromotionInst.PromotionButton:SetDisabled(false);
						pPromotionInst.PromotionButton:SetSelected(true);
						pPromotionInst.PromotionButton:SetVisState(5);
						pPromotionInst.PromotionButton:SetVoid1(m_GovernorIndex);
						pPromotionInst.PromotionButton:SetVoid2(kPromotion.Index);
						pPromotionInst.PromotionButton:RegisterCallback( Mouse.eLClick, OnPromoteGovernor );
					elseif not canEarnPromotion then
						pPromotionInst.PromotionButton:SetDisabled(true);
						pPromotionInst.PromotionButton:SetSelected(false);
						pPromotionInst.PromotionButton:SetVisState(3);
						pPromotionInst.PromotionButton:ClearCallback( Mouse.eLClick );
					else
						pPromotionInst.PromotionButton:SetDisabled(m_isReadOnly);
						pPromotionInst.PromotionButton:SetSelected(false);
						pPromotionInst.PromotionButton:SetVisState(0);
						pPromotionInst.PromotionButton:SetVoid1(m_GovernorIndex);
						pPromotionInst.PromotionButton:SetVoid2(kPromotion.Index);
						pPromotionInst.PromotionButton:RegisterCallback( Mouse.eLClick, OnPromoteGovernor );
					end

					-- Insert this promotion into the matrix
					local matrixX:number = kPromotion.Column + 1;
					local matrixY:number = kPromotion.Level;
					if matrixX >= 1 and matrixX <= 3 and matrixY >= 1 and matrixY <= 3 then
						promotionTreeMatrix[matrixX][matrixY] = kPromotion;
					end
				end
			end
		end
	end

	m_ReqLinesLeftIM:ResetInstances();
	m_ReqLinesRightIM:ResetInstances();
	m_ReqLinesDownIM:ResetInstances();

	-- Loop through the matrix to determine where we have to display requirement lines
	for x=1,3,1 do
		for y=1,2,1 do
			local kPromotion:table = promotionTreeMatrix[x][y];
			if kPromotion then
				
				local xOffset:number = PROMOTION_X_OFFSET * (x - 1);
				local yOffset:number = (PROMOTION_Y_OFFSET * (y - 1)) + PROMOTION_LINE_Y_OFFSET;

				-- Check if we unlock the promotion below us
				local kPromotionBelow = promotionTreeMatrix[x][y+1]
				if kPromotionBelow then
					local pLineInst:table = m_ReqLinesDownIM:GetInstance(pPromotionTreeInst.PromotionLinesContainer);
					pLineInst.Top:SetOffsetVal(xOffset, yOffset);
				end

				-- Check if we unlock the promotion to the right of us
				if x < 3 then
					local kPromotionToRight:table = promotionTreeMatrix[x+1][y+1];
					if kPromotionToRight then
						local pLineInst:table = m_ReqLinesRightIM:GetInstance(pPromotionTreeInst.PromotionLinesContainer);
						local adjustedXOffset:number = x ~= 2 and xOffset or xOffset + EXTRA_MIDDLE_PROMOTION_LINE_X_OFFSET;
						pLineInst.Top:SetOffsetVal(adjustedXOffset, yOffset);
					end
				end

				-- Check if we unlock the promotion to the left of us
				if x > 1 then
					local kPromotionToLeft:table = promotionTreeMatrix[x-1][y+1];
					if kPromotionToLeft then
						local pLineInst:table = m_ReqLinesLeftIM:GetInstance(pPromotionTreeInst.PromotionLinesContainer);
						local adjustedXOffset:number = x ~= 2 and xOffset or xOffset - EXTRA_MIDDLE_PROMOTION_LINE_X_OFFSET;
						pLineInst.Top:SetOffsetVal(adjustedXOffset, yOffset);
					end
				end
			end
		end
	end
end

-- ===========================================================================
function CreateSecretPromotionTree(localPlayerID:number, pGovernor:table, pGovernorDef:table, pPlayerGovernors:table)
	
	local pSecretPromotionTreeInst:table = m_SecretPromotionTreeIM:GetInstance();

	m_SecretPromotionIM:ResetInstances();
	for promotionSet in GameInfo.GovernorPromotionSets() do
		if promotionSet.GovernorType == pGovernorDef.GovernorType then
			local kPromotion:table = GameInfo.GovernorPromotions[promotionSet.GovernorPromotion];
			
			local sName:string = Locale.ToUpper(kPromotion.Name);
			local sDescription:string = Locale.Lookup(kPromotion.Description);
			local isHidden:boolean = IsPromotionHidden(kPromotion.Hash, localPlayerID, pGovernorDef.Index);
			if isHidden then
				sName = GetPromotionHiddenName(kPromotion.Hash);
				sDescription = GetPromotionHiddenDescription(kPromotion.Hash);
			end
			
			local promotionInst:table = m_SecretPromotionIM:GetInstance(pSecretPromotionTreeInst.PromotionContainer);
			TruncateStringWithTooltip(promotionInst.PromotionName, PROMOTION_NAME_TRUNCATE_WIDTH, sName);
			promotionInst.PromotionDesc:SetText(sDescription);

			-- Determine if this promotion can currently be earn by this governor due to requirements, etc
			local canEarnPromotion:boolean = pPlayerGovernors:CanEarnPromotion(pGovernorDef.Hash, kPromotion.Hash);

			-- Update button state and callback depending on the promotion state
			if (pGovernor and pGovernor:HasPromotion(kPromotion.Hash)) then
				promotionInst.PromotionButton:SetDisabled(true);
				promotionInst.PromotionButton:SetVisState(4);
				promotionInst.PromotionButton:ClearCallback( Mouse.eLClick );
			elseif m_SelectedPromotion == kPromotion.Index then
				promotionInst.PromotionButton:SetDisabled(false);
				promotionInst.PromotionButton:SetSelected(true);
				promotionInst.PromotionButton:SetVisState(5);
				promotionInst.PromotionButton:SetVoid1(m_GovernorIndex);
				promotionInst.PromotionButton:SetVoid2(kPromotion.Index);
				promotionInst.PromotionButton:RegisterCallback( Mouse.eLClick, OnPromoteGovernor );
			elseif not canEarnPromotion then
				promotionInst.PromotionButton:SetDisabled(true);
				promotionInst.PromotionButton:SetSelected(false);
				promotionInst.PromotionButton:SetVisState(3);
				promotionInst.PromotionButton:ClearCallback( Mouse.eLClick );
			else
				promotionInst.PromotionButton:SetDisabled(m_isReadOnly);
				promotionInst.PromotionButton:SetSelected(false);
				promotionInst.PromotionButton:SetVisState(0);
				promotionInst.PromotionButton:SetVoid1(m_GovernorIndex);
				promotionInst.PromotionButton:SetVoid2(kPromotion.Index);
				promotionInst.PromotionButton:RegisterCallback( Mouse.eLClick, OnPromoteGovernor );
			end

			-- Add secret promotions to list so we can play effects on them
			promotionInst.NeedsSmokeEffect = isHidden;
		end
	end

    pSecretPromotionTreeInst.PromotionContainer:CalculateSize();
    RefreshSmokeEffects();
end

-- ===========================================================================
function SetGovernorStatus(governorDef:table, governor:table)
	local status, statusDetails = GetGovernorStatus(governorDef, governor);
	Controls.GovernorStatus:SetText(status);
	Controls.GovernorStatusDetails:SetText(statusDetails);
end

-- ===========================================================================
function OnAppointGovernor( eGovernor:number )
	local pLocalPlayer = Players[Game.GetLocalPlayer()];
	if (pLocalPlayer ~= nil) then
		local kParameters:table = {};
		kParameters[PlayerOperations.PARAM_GOVERNOR_TYPE] = eGovernor;
		UI.RequestPlayerOperation(Game.GetLocalPlayer(), PlayerOperations.APPOINT_GOVERNOR, kParameters);
	end
end

-- ===========================================================================
function OnAssignGovernor( eGovernor:number )
	LuaEvents.GovernorAssignmentChooser_RequestAssignment( eGovernor );
	Close();
	LuaEvents.GovernorPanel_AssignDetails();
end

-- ===========================================================================
function OnPromoteGovernor(eGovernor:number, ePromotion:number)
	
	if m_SelectedPromotion == ePromotion then
		m_SelectedPromotion = -1;
	else
		m_SelectedPromotion = ePromotion;
	end

	Refresh();
end

-- ===========================================================================
function OnConfirm()
	ApplyPromotion();
end

-- ===========================================================================
function ApplyPromotion()
	local pLocalPlayer = Players[Game.GetLocalPlayer()];
	if (pLocalPlayer ~= nil) then
		local kParameters:table = {};
		kParameters[PlayerOperations.PARAM_GOVERNOR_TYPE] = m_GovernorIndex;
		kParameters[PlayerOperations.PARAM_GOVERNOR_PROMOTION_TYPE] = m_SelectedPromotion;
		UI.RequestPlayerOperation(Game.GetLocalPlayer(), PlayerOperations.PROMOTE_GOVERNOR, kParameters);
	end

	m_SelectedPromotion = -1;
end

-- ===========================================================================
function OnBack()
	Close();
	LuaEvents.GovernorPanel_ClosedDetails();
end

-- ===========================================================================
function OnOpenDetails( governorIndex:number, isReadOnly : boolean )
	m_GovernorIndex = governorIndex;
	m_isReadOnly = isReadOnly;
	Open();
end

-- ===========================================================================
function Open()
	-- Clear promotion queue
	m_SelectedPromotion = -1;
	
	Refresh();
	ContextPtr:SetHide(false);
	SRA_Announce();		-- ScreenReaderAccess
end

-- ===========================================================================
function Close()
	ContextPtr:SetHide(true);
end

-- ===========================================================================
function OnInit( isReload:boolean )
	if isReload then		
		LuaEvents.GameDebug_GetValues( RELOAD_CACHE_ID );	
	end
end

-- =======================================================================================
function OnShutdown()
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "isVisible", ContextPtr:IsVisible());
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "governorIndex", m_GovernorIndex);

	Unsubscribe();
end

-- ===========================================================================
function RefreshSmokeEffects()
	for i=1, m_SecretPromotionIM.m_iCount, 1 do
		local pPromotionInstance:table = m_SecretPromotionIM:GetAllocatedInstance(i);
		if pPromotionInstance.NeedsSmokeEffect then
			EffectsManager:PlayEffect(pPromotionInstance.PromotionButton, "FireFX_SecretSocietySmoke");
		else
			EffectsManager:StopEffect(pPromotionInstance.PromotionButton);
		end
	end
end

-- ===========================================================================s
function OnGameDebugReturn( context:string, contextTable:table )
	if context ~= RELOAD_CACHE_ID then
		return;
	end

	if contextTable["governorIndex"] then
		m_GovernorIndex = contextTable["governorIndex"];
	end

	if contextTable["isVisible"] and contextTable["isVisible"] == true then
		Open();
	end
end

-- ===========================================================================
--	ScreenReaderAccess: keyboard navigation and speech
--	The promotions of the governor as a list: Up/Down/Home/End, Space = read again, Enter = promote (select the
--	promotion and confirm, as the buttons do), Escape = back.
-- ===========================================================================
local function SRA_Say( text:string, nointerrupt:boolean )
	OutputMessageToScreenReader( text, nointerrupt );
end

local function SRA_Clean( text:string )
	return CleanTextForSpeech( Locale.Lookup( text or "" ) );
end

local m_srPromotingName:string = nil;

local function SRA_PromotionItems()
	local items:table = {};
	local localPlayerID:number = Game.GetLocalPlayer();
	if m_GovernorIndex == -1 or localPlayerID == PlayerTypes.NONE or localPlayerID == PlayerTypes.OBSERVER then return items; end
	local def:table = GameInfo.Governors[ m_GovernorIndex ];
	local gov:table = GetAppointedGovernor( localPlayerID, m_GovernorIndex );
	local pg:table = Players[ localPlayerID ]:GetGovernors();
	local promos:table = {};
	for set in GameInfo.GovernorPromotionSets() do
		if set.GovernorType == def.GovernorType then
			table.insert( promos, GameInfo.GovernorPromotions[ set.GovernorPromotion ] );
		end
	end
	table.sort( promos, function( a, b )
		if a.Level ~= b.Level then return a.Level < b.Level; end
		return a.Column < b.Column;
	end );
	for _, promo in ipairs( promos ) do
		local name:string = SRA_Clean( promo.Name );
		local desc:string = SRA_Clean( promo.Description );
		if IsPromotionHidden( promo.Hash, localPlayerID, def.Index ) then
			name = GetPromotionHiddenName( promo.Hash );
			desc = GetPromotionHiddenDescription( promo.Hash );
		end
		local item:table = { key = "promo:" .. promo.Index, promo = promo, name = name };
		if promo.BaseAbility then
			item.text = "Base ability: " .. desc;
			item.choosable = false;
			item.reason = "This is the base ability";
		else
			item.text = name .. ": " .. desc;
			if gov == nil then
				item.choosable = false;
				item.reason = "Appoint this governor first";
			elseif gov:HasPromotion( promo.Hash ) then
				item.text = item.text .. ", have";
				item.choosable = false;
				item.reason = "Already have this promotion";
			elseif pg:CanEarnPromotion( def.Hash, promo.Hash ) then
				if m_isReadOnly then
					item.text = item.text .. ", available";
					item.choosable = false;
					item.reason = "Not possible during the World Congress";
				elseif pg:CanPromoteGovernor( def.Hash ) then
					item.text = item.text .. ", available";
				else
					item.text = item.text .. ", available, needs a governor title";
					item.choosable = false;
					item.reason = "No governor title to promote with";
				end
			else
				local needs:table = {};
				for row in GameInfo.GovernorPromotionPrereqs() do
					if row.GovernorPromotionType == promo.GovernorPromotionType then
						local prereq:table = GameInfo.GovernorPromotions[ row.PrereqGovernorPromotion ];
						if prereq ~= nil and not gov:HasPromotion( prereq.Hash ) then
							table.insert( needs, SRA_Clean( prereq.Name ) );
						end
					end
				end
				item.text = item.text .. ", locked";
				if #needs > 0 then item.text = item.text .. ": needs " .. table.concat( needs, " and " ); end
				item.choosable = false;
				item.reason = "Locked";
				if #needs > 0 then item.reason = "Locked, needs " .. table.concat( needs, " and " ); end
			end
		end
		item.detail = item.text;
		table.insert( items, item );
	end
	return items;
end

local function SRA_OnPromotionActivate( item:table )
	m_srPromotingName = item.name;
	if m_SelectedPromotion ~= item.promo.Index then
		OnPromoteGovernor( m_GovernorIndex, item.promo.Index );
	end
	OnConfirm();
end

function SRA_CreateList()
	m_srList = KeyNavList_Create{
		build = SRA_PromotionItems,
		isActive = function() return not ContextPtr:IsHidden(); end,
		onActivate = SRA_OnPromotionActivate,
		onClose = OnBack,
	};
end

-- "Magnus, The Steward: promotions. Base ability: ..., 1 of 6"
function SRA_Announce()
	if m_srList == nil or m_GovernorIndex == -1 then return; end
	local def:table = GameInfo.Governors[ m_GovernorIndex ];
	local items:table = SRA_PromotionItems();
	local head:string = SRA_Clean( def.Name ) .. ", " .. SRA_Clean( def.Title ) .. ": promotions";
	if #items == 0 then
		SRA_Say( head .. ", none", true );
		return;
	end
	m_srList.Reset();
	m_srList.Open( "", nil, true );
	SRA_Say( head .. ". " .. items[1].text .. ", 1 of " .. #items, true );
end

function SRA_OnPromoted( ePlayer:number, eGovernor:number, ePromotion:number )
	if m_srPromotingName == nil or ePlayer ~= Game.GetLocalPlayer() then return; end
	SRA_Say( "Promoted: " .. m_srPromotingName );
	m_srPromotingName = nil;
end

function SRA_HandleInput( pInputStruct:table )
	if ContextPtr:IsHidden() then return false; end
	if m_srList ~= nil and m_srList.HandleInput( pInputStruct ) then return true; end
	local msg:number = pInputStruct:GetMessageType();
	return msg == KeyEvents.KeyDown or msg == KeyEvents.KeyUp;
end
-- End ScreenReaderAccess

-- ===========================================================================
--	Input
--	UI Event Handler
-- ===========================================================================
function OnInputHandler( pInputStruct:table )

	if ContextPtr:IsHidden() then return; end

	if SRA_HandleInput( pInputStruct ) then return true; end		-- ScreenReaderAccess

	local key = pInputStruct:GetKey();
	local msg = pInputStruct:GetMessageType();
	if msg == KeyEvents.KeyUp and key == Keys.VK_ESCAPE then 
		OnBack();
		return true;
	end;
	return false;
end

-- ===========================================================================
function OnLocalPlayerTurnEnd()
	if GameConfiguration.IsHotseat() and ContextPtr:IsVisible() then
		Close();
	end
end

-- ===========================================================================
function Subscribe()
	-- Lua Events
	LuaEvents.GameDebug_Return.Add( OnGameDebugReturn );

	-- Context Events
	LuaEvents.GovernorDetailsPanel_OpenDetails.Add( OnOpenDetails );

	-- Game Events
	Events.GovernorAppointed.Add( Refresh );
	Events.GovernorAssigned.Add( Refresh );
	Events.GovernorChanged.Add( Refresh );
	Events.GovernorPointsChanged.Add( Refresh );
	Events.GovernorPromoted.Add( Refresh );
	Events.GovernorPromoted.Add( SRA_OnPromoted );		-- ScreenReaderAccess
	Events.LocalPlayerTurnBegin.Add( Refresh );	
	Events.LocalPlayerTurnEnd.Add( OnLocalPlayerTurnEnd );
end

-- ===========================================================================
function Unsubscribe()
	-- Lua Events
	LuaEvents.GameDebug_Return.Remove( OnGameDebugReturn );

	-- Context Events
	LuaEvents.GovernorDetailsPanel_OpenDetails.Remove( OnOpenDetails );

	-- Game Events
	Events.GovernorAppointed.Remove( Refresh );
	Events.GovernorAssigned.Remove( Refresh );
	Events.GovernorChanged.Remove( Refresh );
	Events.GovernorPointsChanged.Remove( Refresh );
	Events.GovernorPromoted.Remove( Refresh );
	Events.GovernorPromoted.Remove( SRA_OnPromoted );		-- ScreenReaderAccess
	Events.LocalPlayerTurnBegin.Remove( Refresh );	
	Events.LocalPlayerTurnEnd.Remove( OnLocalPlayerTurnEnd );
end

-- ===========================================================================
-- ===========================================================================
function Initialize()

	-- Start off hidden
	ContextPtr:SetHide(true);
	ContextPtr:SetInitHandler( OnInit );
	ContextPtr:SetShutdown( OnShutdown );
	ContextPtr:SetInputHandler( OnInputHandler, true );
	SRA_CreateList();		-- ScreenReaderAccess

	-- Control Events
	Controls.ConfirmButton:RegisterCallback( Mouse.eLClick, OnConfirm );
	Controls.BackButton:RegisterCallback( Mouse.eLClick, OnBack );

	Subscribe();

	m_TopPanelConsideredHeight = Controls.Vignette:GetSizeY() - TOP_PANEL_OFFSET;
end
Initialize();
