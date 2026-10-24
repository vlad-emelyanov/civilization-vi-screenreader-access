-- Copyright 2020, Firaxis Games
include("SupportFunctions");
include("ScreenReader");		-- ScreenReaderAccess mod change
include("KeyNavList");			-- ScreenReaderAccess mod change
include("SRListen");			-- ScreenReaderAccess mod change
include("TreatClanText");		-- ScreenReaderAccess mod change

-- ScreenReaderAccess mod change: keyboard list over the visible options (Hire, Incite, Bribe or Ransom, Close), speech
local m_srList		: table = nil;
local m_srSpeakIn	: number = -1;		-- seconds until the opening is read (after the game filled the controls)
local m_srTribeIndex: number = -1;
local m_srClanName	: string = "";
local m_srTargetLabel : string = "";	-- label of the chosen incite target (the pulldown entry text)
local m_srHold		: boolean = false;

local m_BarbarianTribePlotIndex : number;
local m_SelectedInciteTargetID	: number = -1;

local CANT_INCITE_DESCRIPTION_SIZE_Y	: number = 156;
local CAN_INCITE_DESCRIPTION_SIZE_Y		: number = 120;
local CANT_INCITE_DESCRIPTION_OFFSET_Y	: number = 110;
local CAN_INCITE_DESCRIPTION_OFFSET_Y	: number = 92;

-- ===========================================================================
function OnOpenTreatWithTribePopup(plotIndex : number)
	ContextPtr:SetHide(false);

	local iActivePlayer : number = Game.GetLocalPlayer();
	if (iActivePlayer == -1) then
		return;
	end
	local pActivePlayer = Players[iActivePlayer];

	m_BarbarianTribePlotIndex = plotIndex;
	local pTribePlot : table = Map.GetPlotByIndex(plotIndex);
	local iPlotX : number = pTribePlot:GetX();
	local iPlotY : number = pTribePlot:GetY();
	local pBarbarianManager : table = Game.GetBarbarianManager();
	local tribeIndex : number = pBarbarianManager:GetTribeIndexAtLocation(iPlotX, iPlotY);
	local barbType : number = pBarbarianManager:GetTribeNameType(tribeIndex);
	local pBarbTribe : table = GameInfo.BarbarianTribeNames[barbType];

	-- Header
	local strHeader : string = Locale.Lookup("LOC_TREAT_WITH_NAMED_CLAN", pBarbTribe.TribeDisplayName);
	Controls.HeaderLabel:SetText(strHeader);

	-- Subheader info
	local strInfo : string = ComposeTribeInfoString(tribeIndex) or "";
	Controls.SubheaderLabel:SetText(strInfo);

	-- Prioritize operations: only 3 can be relevant at the same time
	local bIsExclusionTest : boolean = false;
	local tParameters : table = {};
	tParameters[PlayerOperations.PARAM_PLOT_ONE] = m_BarbarianTribePlotIndex;

	-- Hire: show as long as the player has a city
	if (pActivePlayer:GetCities():GetCount() >= 1) then
		Controls.HireOption:SetHide(false);
		local bCanStartHire, tHireResults = UI.CanStartPlayerOperation(iActivePlayer, PlayerOperations.HIRE_CLAN, tParameters, bIsExclusionTest);
		Controls.TreatOptionButtonHire:SetDisabled(not bCanStartHire);
		local strGameplayText = FormatOperationGameplayText(tHireResults);
		Controls.TreatOptionHireDescription:SetText(strGameplayText);
	else
		Controls.HireOption:SetHide(true);
		Controls.TreatOptionButtonHire:SetDisabled(true);
	end
	
	-- Incite: always shown
	local bCanStartIncite, tInciteResults = UI.CanStartPlayerOperation(iActivePlayer, PlayerOperations.INCITE_CLAN, tParameters, bIsExclusionTest);
	Controls.TreatOptionButtonIncite:SetDisabled(not bCanStartIncite);
	local strGameplayText = FormatOperationGameplayText(tInciteResults);
	Controls.TreatOptionInciteDescription:SetText(strGameplayText);

	--Set up Incite target pulldown
	Controls.InciteTargetPulldown:ClearEntries();
	if (bCanStartIncite) then
		Controls.InciteOptionScroll:SetSizeY(CAN_INCITE_DESCRIPTION_SIZE_Y);
		Controls.InciteOptionGrid:SetOffsetY(CAN_INCITE_DESCRIPTION_OFFSET_Y);
		UpdateInciteTargetPulldown(tribeIndex);
	else
		Controls.InciteOptionScroll:SetSizeY(CANT_INCITE_DESCRIPTION_SIZE_Y);
		Controls.InciteOptionGrid:SetOffsetY(CANT_INCITE_DESCRIPTION_OFFSET_Y);
		Controls.InciteTargetPulldown:SetHide(true);
		Controls.InciteCostLabel:SetHide(true);
	end

	-- Bribe and Ransom: paired, show Ransom if able otherwise show Bribe
	local bShowRansom = UI.CanStartPlayerOperation(iActivePlayer, PlayerOperations.RANSOM_CLAN, tParameters, true);
	if (bShowRansom) then
		Controls.BribeOption:SetHide(true);
		Controls.RansomOption:SetHide(false);

		local bCanStartRansom, tRansomResults = UI.CanStartPlayerOperation(iActivePlayer, PlayerOperations.RANSOM_CLAN, tParameters, bIsExclusionTest);
		Controls.TreatOptionButtonRansom:SetDisabled(not bCanStartRansom);
		local strGameplayText = FormatOperationGameplayText(tRansomResults);
		Controls.TreatOptionRansomDescription:SetText(strGameplayText);
	else
		Controls.RansomOption:SetHide(true);
		Controls.TreatOptionButtonRansom:SetDisabled(true);
		Controls.BribeOption:SetHide(false);

		local bCanStartBribe, tBribeResults = UI.CanStartPlayerOperation(iActivePlayer, PlayerOperations.BRIBE_CLAN, tParameters, bIsExclusionTest);
		Controls.TreatOptionButtonBribe:SetDisabled(not bCanStartBribe);
		local strGameplayText = FormatOperationGameplayText(tBribeResults);
		Controls.TreatOptionBribeDescription:SetText(strGameplayText);
	end

	-- ScreenReaderAccess mod change: the controls are filled; read the popup after a moment
	m_srTribeIndex = tribeIndex;
	m_srClanName = Locale.Lookup(pBarbTribe.TribeDisplayName);
	m_srTargetLabel = "";
	SRA_OnOpened();
end

-- ===========================================================================
function UpdateInciteTargetPulldown(tribeIndex : number)

	local iActivePlayer : number = Game.GetLocalPlayer();
	if (iActivePlayer == -1) then
		return;
	end

	local pBarbarianManager : table = Game.GetBarbarianManager();
	local tInciteTargets : table = pBarbarianManager:GetTribeInciteTargets(tribeIndex, iActivePlayer);
	if (tInciteTargets ~= nil) then

		Controls.InciteTargetPulldown:GetButton():LocalizeAndSetToolTip("");
		Controls.InciteTargetPulldown:SetDisabled(false);
		Controls.InciteTargetPulldown:SetHide(false);

		local inciteSourceID : number = pBarbarianManager:GetTribeInciteSourcePlayer(tribeIndex);
		local inciteTargetID : number = pBarbarianManager:GetTribeInciteTargetPlayer(tribeIndex);

		for _,eTargetPlayer in ipairs(tInciteTargets) do
			local bSkip : boolean = false;
			-- If the active player was the last to incite this clan, exclude their last-chosen target
			if (eTargetPlayer == inciteTargetID) then
				if (iActivePlayer == inciteSourceID) then
					bSkip = true;
				end
			end

			if (not bSkip) then
				local uiIncitePulldownEntry : table = {};
				Controls.InciteTargetPulldown:BuildEntry("InstanceOne", uiIncitePulldownEntry);
			
				-- Other player name
				local pOtherPlayerConfig : table = PlayerConfigurations[eTargetPlayer];
				local strOtherPlayerCivName : string = Locale.Lookup(pOtherPlayerConfig:GetCivilizationShortDescription());
				local strOtherPlayerLeaderName : string = Locale.Lookup(pOtherPlayerConfig:GetLeaderName());
				-- Other player cost
				-- ScreenReaderAccess mod change: the original passed `otherPlayerID`, a global that is never set (nil), so the cost
				-- it computed was for no target (probably 0 or wrong, which keeps Incite disabled). The loop's target is used.
				local iInciteCost : number = pBarbarianManager:GetTribeInciteCost(tribeIndex, iActivePlayer, eTargetPlayer);
				if(strOtherPlayerCivName ~= strOtherPlayerLeaderName)then
					uiIncitePulldownEntry.Button:SetText(strOtherPlayerCivName .. " - " .. strOtherPlayerLeaderName);
				else
					--City states won't have a leader name (it will be the same as civ name)
					uiIncitePulldownEntry.Button:SetText(strOtherPlayerCivName);
				end
				
				uiIncitePulldownEntry.Button:RegisterCallback(Mouse.eLClick, function() SelectInciteTarget(eTargetPlayer, uiIncitePulldownEntry.Button:GetText(), iInciteCost) end);
			end
		end

		Controls.InciteTargetPulldown:CalculateInternals();
		if(m_SelectedInciteTargetID == -1)then
			Controls.TreatOptionButtonIncite:SetDisabled(true);
			Controls.InciteTargetPulldown:GetButton():LocalizeAndSetText("LOC_DIPLOMACY_DEAL_SELECT_TARGET");
			Controls.InciteCostLabel:SetHide(true);
		else
			Controls.InciteCostLabel:SetHide(false);
		end

	else
		Controls.InciteTargetPulldown:SetHide(true);
		Controls.InciteCostLabel:SetHide(true);
	end
end

-- ===========================================================================
function SelectInciteTarget(otherPlayerID : number, otherPlayerCivName : string, otherPlayerCost:number)
	m_SelectedInciteTargetID = otherPlayerID;
	Controls.InciteTargetPulldown:GetButton():LocalizeAndSetText(otherPlayerCivName);
	
	if (otherPlayerCost > 0) then
		Controls.InciteCostLabel:SetHide(false);
		local pLocalPlayer = Players[Game.GetLocalPlayer()];
		local strCost : string = Locale.Lookup("LOC_TREAT_WITH_TRIBE_INCITE_COST", otherPlayerCost);

		if (otherPlayerCost <= pLocalPlayer:GetTreasury():GetGoldBalance()) then
			Controls.InciteCostLabel:SetText(strCost);
			Controls.TreatOptionButtonIncite:SetDisabled(false);
		else
			Controls.InciteCostLabel:SetText("[COLOR:Red]" .. strCost .. "[ENDCOLOR]");
			Controls.TreatOptionButtonIncite:SetDisabled(true);
		end
	else
		Controls.InciteCostLabel:SetHide(true);
		Controls.TreatOptionButtonIncite:SetDisabled(true);
	end
end

-- ===========================================================================
function FormatOperationGameplayText(tResults:table)
	local strHelp : string = FormatOperationHelpString(tResults);
	local strFails : string = FormatFailureReasonsString(tResults);

	if (strHelp ~= "") then
		if (strFails ~= "") then
			return strHelp .. "[NEWLINE][NEWLINE]" .. strFails;
		else
			return strHelp;
		end
	else
		return strFails;
	end
end

-- ===========================================================================
function FormatOperationHelpString(tResults:table)
	if (tResults == nil or tResults[PlayerOperationResults.ADDITIONAL_DESCRIPTION] == nil) then
		return "";
	end

	local strResult = "";
	for i,v in ipairs(tResults[PlayerOperationResults.ADDITIONAL_DESCRIPTION]) do
		strResult = strResult .. Locale.Lookup(v);
	end

	return strResult;
end

-- ===========================================================================
function FormatFailureReasonsString(tResults:table)
	if (tResults == nil) then
		return "";
	end
	if (tResults[PlayerOperationResults.FAILURE_REASONS] == nil) then
		return "";
	end

	local strResult : string = "[COLOR:Red]";
	for i,v in ipairs(tResults[PlayerOperationResults.FAILURE_REASONS]) do
		strResult = strResult .. Locale.Lookup(v);
	end
	strResult = strResult .. "[ENDCOLOR]";

	return strResult;
end

-- ===========================================================================
function ComposeTribeInfoString(tribeIndex:number)
	
	local strInfos = {};
	local pBarbarianManager : table = Game.GetBarbarianManager();

	-- Clan type
	local eTribeType = pBarbarianManager:GetTribeType(tribeIndex);
	local pBarbTribe = GameInfo.BarbarianTribes[eTribeType];
	if (pBarbTribe ~= nil and pBarbTribe.Name ~= nil) then
		local strClanType : string = Locale.Lookup(pBarbTribe.Name);
		table.insert(strInfos, strClanType);
	end

	-- Conversion tip given only in chunky increments as a hint
	local iCurrentPoints : number = pBarbarianManager:GetTribeConversionPoints(tribeIndex);
	local iPointsToConvert : number = pBarbarianManager:GetTribeConversionPointsRequired(tribeIndex);
	local iPointsRemaining = iPointsToConvert - iCurrentPoints;

	if (iCurrentPoints >= 0) then
		local strConversionTip : string = "";
		if (iPointsRemaining >= 50) then
			strConversionTip = Locale.Lookup("LOC_TRIBE_BANNER_CONVERSION_TIP_TURNS", 50);
		elseif (iPointsRemaining >= 20) then
			strConversionTip = Locale.Lookup("LOC_TRIBE_BANNER_CONVERSION_TIP_TURNS", 20);
		elseif (iPointsRemaining >= 10) then
			strConversionTip = Locale.Lookup("LOC_TRIBE_BANNER_CONVERSION_TIP_TURNS", 10);
		else
			strConversionTip = Locale.Lookup("LOC_TRIBE_BANNER_CONVERSION_TIP_IMMINENT");
		end
		table.insert(strInfos, strConversionTip);
	else
		local strDisabledTip : string = pBarbarianManager:GetTribeConversionDisabledHelp(tribeIndex);
		if (strDisabledTip ~= nil and strDisabledTip ~= "") then
			table.insert(strInfos, strDisabledTip);
		end
	end

	return FormatTableAsString(strInfos, ".");
end

-- ===========================================================================
function OnBribe()
	local parameters : table = {};
	parameters[PlayerOperations.PARAM_PLOT_ONE] = m_BarbarianTribePlotIndex;
	UI.RequestPlayerOperation( Game.GetLocalPlayer(), PlayerOperations.BRIBE_CLAN, parameters);
	ClosePopup();
end

-- ===========================================================================
function OnHire()
	local parameters : table = {};
	parameters[PlayerOperations.PARAM_PLOT_ONE] = m_BarbarianTribePlotIndex;
	UI.RequestPlayerOperation( Game.GetLocalPlayer(), PlayerOperations.HIRE_CLAN, parameters);
	ClosePopup();
end

-- ===========================================================================
function OnRansom()
	local parameters : table = {};
	parameters[PlayerOperations.PARAM_PLOT_ONE] = m_BarbarianTribePlotIndex;
	UI.RequestPlayerOperation( Game.GetLocalPlayer(), PlayerOperations.RANSOM_CLAN, parameters);
	ClosePopup();
end

-- ===========================================================================
function OnIncite()
	local parameters : table = {};
	parameters[PlayerOperations.PARAM_OTHER_PLAYER] = m_SelectedInciteTargetID;
	parameters[PlayerOperations.PARAM_PLOT_ONE] = m_BarbarianTribePlotIndex;
	UI.RequestPlayerOperation( Game.GetLocalPlayer(), PlayerOperations.INCITE_CLAN, parameters);
	ClosePopup();
end

-- ===========================================================================
function ClosePopup()
	m_SelectedInciteTargetID = -1;
	ContextPtr:SetHide(true);
end

-- ===========================================================================
function OnClose()
	ClosePopup();
end

-- ===========================================================================
function OnLocalPlayerTurnEnd ()
	ClosePopup();
end

-- ===========================================================================
function OnInputHandler( pInputStruct:table )
	-- ScreenReaderAccess mod change: the keyboard list takes the keys; every other key is swallowed while the popup is up
	-- (Enter must never reach the end turn action); Escape is the list's onClose
	if ContextPtr:IsHidden() then return false; end
	if m_srList ~= nil and m_srList.HandleInput( pInputStruct ) then return true; end
	return true;
end

-- ===========================================================================
--	ScreenReaderAccess mod change: keyboard list and speech
-- ===========================================================================
local SR_OPTIONS : table = {
	{ id = "Hire",   option = "HireOption",   button = "TreatOptionButtonHire",   desc = "TreatOptionHireDescription",   op = "HIRE_CLAN" },
	{ id = "Incite", option = "InciteOption", button = "TreatOptionButtonIncite", desc = "TreatOptionInciteDescription", op = "INCITE_CLAN" },
	{ id = "Bribe",  option = "BribeOption",  button = "TreatOptionButtonBribe",  desc = "TreatOptionBribeDescription",  op = "BRIBE_CLAN" },
	{ id = "Ransom", option = "RansomOption", button = "TreatOptionButtonRansom", desc = "TreatOptionRansomDescription", op = "RANSOM_CLAN" },
};

-- the incite targets in the pulldown's order and with its skip rule (UpdateInciteTargetPulldown): { id, label, cost } each
local function SRA_InciteTargets()
	local targets : table = {};
	local iActivePlayer : number = Game.GetLocalPlayer();
	if iActivePlayer == -1 or m_srTribeIndex < 0 then return targets; end
	local pBarbarianManager : table = Game.GetBarbarianManager();
	local tInciteTargets : table = pBarbarianManager:GetTribeInciteTargets(m_srTribeIndex, iActivePlayer);
	if tInciteTargets == nil then return targets; end
	local inciteSourceID : number = pBarbarianManager:GetTribeInciteSourcePlayer(m_srTribeIndex);
	local inciteTargetID : number = pBarbarianManager:GetTribeInciteTargetPlayer(m_srTribeIndex);
	for _, eTargetPlayer in ipairs(tInciteTargets) do
		if not (eTargetPlayer == inciteTargetID and iActivePlayer == inciteSourceID) then
			local pOtherPlayerConfig : table = PlayerConfigurations[eTargetPlayer];
			local strCiv : string = Locale.Lookup(pOtherPlayerConfig:GetCivilizationShortDescription());
			local strLeader : string = Locale.Lookup(pOtherPlayerConfig:GetLeaderName());
			local label : string = strCiv;
			if strCiv ~= strLeader then label = strCiv .. " - " .. strLeader; end
			-- the cost for THIS target (the original pulldown used an undefined variable, see UpdateInciteTargetPulldown)
			local cost : number = pBarbarianManager:GetTribeInciteCost(m_srTribeIndex, iActivePlayer, eTargetPlayer);
			table.insert(targets, { id = eTargetPlayer, label = label, cost = cost });
		end
	end
	return targets;
end

local function SRA_Balance()
	local pLocalPlayer : table = Players[Game.GetLocalPlayer()];
	return pLocalPlayer:GetTreasury():GetGoldBalance();
end

local function SRA_Items()
	local items : table = {};
	local iActivePlayer : number = Game.GetLocalPlayer();
	for _, def in ipairs(SR_OPTIONS) do
		local container : table = Controls[def.option];
		if container ~= nil and not container:IsHidden() then
			local button : table = Controls[def.button];
			local spec : table = {
				id = def.id,
				label = CleanTextForSpeech(button:GetTextControl():GetText()),
				description = CleanTextForSpeech(Controls[def.desc]:GetText()),
				disabled = button:IsDisabled(),
			};
			-- the failure reasons alone (the description label holds the help text and the reasons together)
			local tParameters : table = {};
			tParameters[PlayerOperations.PARAM_PLOT_ONE] = m_BarbarianTribePlotIndex;
			local bCan, tResults = UI.CanStartPlayerOperation(iActivePlayer, PlayerOperations[def.op], tParameters, false);
			spec.reasons = CleanTextForSpeech(FormatFailureReasonsString(tResults));
			if def.id == "Incite" then
				spec.incite = { canStart = bCan and true or false };
				if m_SelectedInciteTargetID ~= -1 then
					for _, target in ipairs(SRA_InciteTargets()) do
						if target.id == m_SelectedInciteTargetID then
							spec.incite.target = { label = target.label, cost = target.cost, balance = SRA_Balance() };
						end
					end
				end
			end
			local item : table = TreatClanText_Item(spec);
			item.key = def.id;
			item.id = def.id;
			table.insert(items, item);
		end
	end
	table.insert(items, { key = "Close", id = "Close", text = "Close", detail = "Close without treating", choosable = true });
	return items;
end

local function SRA_OnActivate( item : table )
	if item.id == "Close" then
		OutputMessageToScreenReader(TreatClanText_Result("Close"));
		OnClose();
		return;
	end
	local result : string = TreatClanText_Result(item.id, m_srClanName, m_srTargetLabel);
	if item.id == "Incite" and m_SelectedInciteTargetID == -1 then
		OutputMessageToScreenReader("Choose a target first, with Left and Right");
		return;
	end
	OutputMessageToScreenReader(result);
	-- the game's own functions send the operation and close the popup
	if item.id == "Hire" then OnHire();
	elseif item.id == "Incite" then OnIncite();
	elseif item.id == "Bribe" then OnBribe();
	elseif item.id == "Ransom" then OnRansom();
	end
end

local function SRA_OnEscape()
	OutputMessageToScreenReader(TreatClanText_Result("Close"));
	ClosePopup();
end

-- Left / Right on the Incite option: the next or previous target, chosen through the game's SelectInciteTarget
local function SRA_CycleTarget( delta : number )
	if m_srList == nil or m_srList.GetFocusKey() ~= "Incite" then
		OutputMessageToScreenReader("Left and Right choose the incite target on the Incite option");
		return;
	end
	local items : table = SRA_Items();
	local incite : table = nil;
	for _, item in ipairs(items) do if item.id == "Incite" then incite = item; end end
	if incite == nil then return; end
	local targets : table = SRA_InciteTargets();
	if #targets == 0 then
		OutputMessageToScreenReader("No civilization to incite the clan against");
		return;
	end
	local current : number = 0;
	for i, target in ipairs(targets) do if target.id == m_SelectedInciteTargetID then current = i; end end
	local nextIndex : number;
	if current == 0 then nextIndex = (delta > 0) and 1 or #targets;
	else
		nextIndex = current + delta;
		if nextIndex < 1 then nextIndex = #targets; end
		if nextIndex > #targets then nextIndex = 1; end
	end
	local target : table = targets[nextIndex];
	m_srTargetLabel = target.label;
	SelectInciteTarget(target.id, target.label, target.cost);
	OutputMessageToScreenReader(TreatClanText_Target(target.label, target.cost, SRA_Balance()));
end

local function SRA_Speak()
	if ContextPtr:IsHidden() then return; end
	local items : table = SRA_Items();
	local header : string = CleanTextForSpeech(Controls.HeaderLabel:GetText());
	local sub : string = CleanTextForSpeech(Controls.SubheaderLabel:GetText());
	local opening : string = TreatClanText_Opening(header, sub, #items, nil);
	if m_srList ~= nil and #items > 0 then
		-- the opening, then the focused (first) option with its position
		m_srList.Focus(items[1].key, opening);
	else
		OutputMessageToScreenReader(opening, true);
	end
end

local function SRA_OnUpdate( deltaTime : number )
	if m_srSpeakIn < 0 then return; end
	m_srSpeakIn = m_srSpeakIn - deltaTime;
	if m_srSpeakIn >= 0 then return; end
	m_srSpeakIn = -1;
	SRA_Speak();
end

-- the end of the game's open function (controls filled): open the list, hold the hub's speech, read after a moment
function SRA_OnOpened()
	LuaEvents.SRA_SpeechHold("TreatWithTribe", true, "/InGame/AdditionalUserInterfaces/" .. ContextPtr:GetID());
	m_srHold = true;
	if m_srList ~= nil then
		m_srList.Reset();
		m_srList.Open("", nil, true);
	end
	m_srSpeakIn = 0.2;
end

local function SRA_OnHide()
	m_srSpeakIn = -1;
	if m_srHold then
		m_srHold = false;
		LuaEvents.SRA_SpeechHold("TreatWithTribe", false);
	end
end

-- ===========================================================================
function Initialize()	
	ContextPtr:SetInputHandler( OnInputHandler, true );
	-- ScreenReaderAccess mod change
	ContextPtr:SetHideHandler( SRA_OnHide );
	ContextPtr:SetUpdate( SRA_OnUpdate );
	ContextPtr:SetShutdown( function() SRUnlistenAll(); end );
	m_srList = KeyNavList_Create{
		build = SRA_Items,
		isActive = function() return not ContextPtr:IsHidden(); end,
		onActivate = SRA_OnActivate,
		onClose = SRA_OnEscape,
		extraKeys = { [Keys.VK_LEFT] = function() SRA_CycleTarget(-1); end, [Keys.VK_RIGHT] = function() SRA_CycleTarget(1); end },
	};

	Controls.CloseButton:RegisterCallback( Mouse.eLClick, OnClose);
	Controls.CloseButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);

	Controls.TreatOptionButtonBribe:RegisterCallback(Mouse.eLClick, OnBribe);
	Controls.TreatOptionButtonBribe:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);

	Controls.TreatOptionButtonHire:RegisterCallback(Mouse.eLClick, OnHire);
	Controls.TreatOptionButtonHire:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);

	Controls.TreatOptionButtonRansom:RegisterCallback(Mouse.eLClick, OnRansom);
	Controls.TreatOptionButtonRansom:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);

	Controls.TreatOptionButtonIncite:RegisterCallback(Mouse.eLClick, OnIncite);
	Controls.TreatOptionButtonIncite:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);

	-- LUA Events
	LuaEvents.CityBannerManager_OpenTreatWithTribePopup.Add(OnOpenTreatWithTribePopup);

	-- Game Events
	Events.LocalPlayerTurnEnd.Add( OnLocalPlayerTurnEnd );
end
Initialize();
print( "TreatWithTribePopup: ScreenReaderAccess copy loaded" );