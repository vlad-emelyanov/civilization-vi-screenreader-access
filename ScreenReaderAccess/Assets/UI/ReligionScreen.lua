-- Copyright 2017-2019, Firaxis Games
include("TabSupport");
include("InstanceManager");
include("ModalScreen_PlayerYieldsHelper");
include("GameCapabilities");
include("ScreenReader");		-- ScreenReaderAccess
include("KeyNavList");		-- ScreenReaderAccess
include("Gamepad");		-- ScreenReaderAccess
include("KeyNavEditBox");	-- ScreenReaderAccess
include("ReligionText");	-- ScreenReaderAccess

-- ===========================================================================
--	CONSTANTS
-- ===========================================================================
local PADDING_ICON:number = 5;
local PADDING_TABS:number = 10;
local NUM_MAX_BELIEFS:number = 4;
local NUM_CUSTOM_ICONS:number = 36;
local PADDING_RELIGION_ICON:number = 8;
local PADDING_RELIGION_ICON_SMALL:number = 4;
local PADDING_RELIGION_ICON_SELECTION:number = 8;
local PADDING_RELIGION_ICON_SELECTION_SMALL:number = 4;
local PADDING_TAB_BUTTON_TEXT:number = 55;
local SIZE_BELIEF_ICON_SMALL:number = 32;
local SIZE_BELIEF_ICON_LARGE:number = 64;
local SIZE_RELIGION_ICON_SMALL:number = 22;
local SIZE_RELIGION_ICON_MEDIUM:number = 50;
local SIZE_RELIGION_ICON_LARGE:number = 100;
local SIZE_RELIGION_ICON_HUGE:number = 270;
local SIZE_UNIT_ICON_NONE_ALPHA:number = 0.3;
local OFFSET_WORKING_TOWARDS_PANTHEON:number = 405;
local OFFSET_CHOOSING_PANTHEON_BELIEFS:number = -10;
local OFFSET_CHOOSING_RELIGION_BELIEFS:number = -10;
local TXT_SCREEN_TITLE:string = Locale.Lookup("LOC_UI_RELIGION_TITLE");
local TXT_MY_RELIGION:string = Locale.Lookup("LOC_UI_RELIGION_MY_RELIGION");
local TXT_MY_PANTHEON:string = Locale.Lookup("LOC_UI_RELIGION_MY_PANTHEON");
local DATA_FIELD_FOLLOWERS_IM:string = "FollowersIM";
local DATA_FIELD_BELIEFS_IM:string = "BeliefsIM";
local DATA_FIELD_SELECTION:string = "Selection";
local DATA_FIELD_INDEX:string = "Index";
local DATA_FIELD_ICONS:string = "Icons";
local CITIES_FILTER:table = { FOLLOWING_RELIGION = 1, RELIGION_PRESENT = 2 };

-- Table of localized strings used for when religion units can and cannot be produced
local UNIT_ICON_TOOLTIPS:table = {};
UNIT_ICON_TOOLTIPS["UNIT_MISSIONARY"] = {
	canProduce = "LOC_UI_RELIGION_MISSIONARY_TT",
	cannotProduce = "LOC_UI_RELIGION_HOW_TO_MAKE_MISSIONARY_TT"
};
UNIT_ICON_TOOLTIPS["UNIT_APOSTLE"] = {
	canProduce = "LOC_UI_RELIGION_APOSTLE_TT",
	cannotProduce = "LOC_UI_RELIGION_HOW_TO_MAKE_APOSTLE_TT"
};
UNIT_ICON_TOOLTIPS["UNIT_INQUISITOR"] = {
	canProduce = "LOC_UI_RELIGION_INQUISITOR_TT",
	cannotProduce = "LOC_UI_RELIGION_HOW_TO_MAKE_INQUISITOR_TT"
};
UNIT_ICON_TOOLTIPS["UNIT_GURU"] = {
	canProduce = "LOC_UI_RELIGION_GURU_TT",
	cannotProduce = "LOC_UI_RELIGION_HOW_TO_MAKE_GURU_TT"
};

-- ===========================================================================
--	SCREEN VARIABLES
-- ===========================================================================
local m_TopPanelConsideredHeight:number = 0;
local m_Beliefs:table;
local m_PendingBeliefs:table;
local m_ReligionTabs:table; -- TabSupport
local m_MyReligionTab:table;
local m_AllReligionsTab:table;
local m_ReligionIcons:table;
local m_SelectedReligion:table;
local m_CanCreatePantheon:boolean = false;
local m_isConfirmedBeliefs:boolean = false;
local m_isConfirmingBeliefs:boolean = false;
local m_pGameReligion:table = Game.GetReligion();
local m_CitiesFilter:number = CITIES_FILTER.FOLLOWING_RELIGION;
local m_CitiesIM:table = InstanceManager:new("City", "CityBG", Controls.Cities);
local m_ReligionsIM:table = InstanceManager:new("Religion", "ReligionBG", Controls.Religions);
local m_ReligionTabsIM:table = InstanceManager:new("ReligionTab", "Button", Controls.TabContainer);
local m_ReligionIconsIM:table = InstanceManager:new("ReligionIcon", "ReligionIcon", Controls.ReligionIcons);
local m_AddAvailableBeliefsIM:table = InstanceManager:new("BeliefSlot", "BeliefButton", Controls.AddAvailableBeliefs);
local m_AddSelectedBeliefsIM:table = InstanceManager:new("BeliefSlot", "BeliefButton", Controls.AddBeliefsReligionBeliefs);
local m_ExistingReligionBeliefsIM:table = InstanceManager:new("ReligionBelief", "BeliefBG", Controls.AddBeliefsReligionBeliefs);
local m_SelectBeliefsIM:table = InstanceManager:new("BeliefSlot", "BeliefButton", Controls.AvailableBeliefs);
local m_SelectedBeliefsIM:table = InstanceManager:new("BeliefSlot", "BeliefButton", Controls.SelectedBeliefs);
local m_ReligionBeliefsIM:table = InstanceManager:new("ReligionBelief", "BeliefBG", Controls.ViewReligionBeliefs);
local m_ReligionSelections:table = InstanceManager:new("ReligionOption", "ReligionButton", Controls.ChooseReligionItems);
local m_UnitIconIM:table = InstanceManager:new("UnitIconInstance", "UnitIconBacking", Controls.IconStack);

-- ===========================================================================
--	PLAYER VARIABLES
-- ===========================================================================
local m_LocalPlayer			:table;
local m_PlayerReligionType	:number;
local m_PantheonBelief		:number;
local m_TurnBlockingType	:number;
local m_NumBeliefsEarned	:number;
local m_NumBeliefsEquipped	:number;
local m_isHasProphet		:boolean;
local m_SelectedBeliefs		:table;

-- ScreenReaderAccess
local m_srList				:table;		-- keyboard list (created in the ScreenReaderAccess block below)
local m_srBeliefOrder		:table = {};	-- belief indexes in the order of the available list (filled by PopulateAvailableBeliefs)
local m_srBeliefInst		:table = {};	-- belief index -> button instance of the available list
local m_srReligionSelect	:table = {};	-- religion index -> the click callback of its icon (ChooseReligion)
local m_srNameChanged		= nil;		-- the string-changed callback of the religion name box
local m_srConfirm			= nil;		-- click callback of the confirm button of the current confirm panel
local m_srReselectBeliefs	= nil;		-- click callback of "reselect beliefs"
local m_srOpenPending		:boolean = false;
local m_srOpenDelay			:number = 0;
local m_srResult			= nil;		-- { wait } a confirm whose result is spoken from the game's data
-- End ScreenReaderAccess

-- ===========================================================================
function GetDisplayPlayerID()

	if Game.GetLocalObserver() == PlayerTypes.OBSERVER then
		-- Use the first alive player
		local aPlayers = PlayerManager.GetAliveMajors();
		if (#aPlayers > 0) then
			return aPlayers[1]:GetID();
		end
	end

	return Game.GetLocalPlayer();
end

-- ===========================================================================
--	Called every time screen is shown
-- ===========================================================================
function UpdatePlayerData()
	local displayPlayerID = GetDisplayPlayerID();
	if (displayPlayerID ~= -1) then
		m_LocalPlayer					= Players[displayPlayerID];
		local pPlayerReligion:table		= m_LocalPlayer:GetReligion();
		m_PantheonBelief				= pPlayerReligion:GetPantheon();
		m_CanCreatePantheon				= pPlayerReligion:CanCreatePantheon();
		m_PlayerReligionType			= pPlayerReligion:GetReligionTypeCreated();
		m_TurnBlockingType				= NotificationManager.GetFirstEndTurnBlocking(displayPlayerID);
		m_NumBeliefsEarned				= pPlayerReligion:GetNumBeliefsEarned();
		m_isHasProphet					= pPlayerReligion:HasReligiousFoundingUnit();
	
		m_NumBeliefsEquipped = 0;
		local religions = m_pGameReligion:GetReligions();
		for _, religion in ipairs(religions) do
			if (religion.Founder == displayPlayerID) then
				m_NumBeliefsEquipped = table.count(religion.Beliefs);
				break;
			end
		end
	end
end

-- ===========================================================================
--	Called every time screen is shown
-- ===========================================================================
function UpdateTabs()

	if (m_LocalPlayer == nil) then
		return;
	end

	-- Clean up previous data
	m_MyReligionTab = nil
	m_AllReligionsTab = nil;
	m_ReligionTabsIM:ResetInstances();
	
	-- Deselect previously selected tab
	if(m_ReligionTabs ~= nil) then
		m_ReligionTabs.SelectTab(nil);
		if(m_ReligionTabs.prevSelectedControl ~= nil) then
			m_ReligionTabs.prevSelectedControl[DATA_FIELD_SELECTION]:SetHide(true);
		end
	end

	-- Create TabSupport object
	m_ReligionTabs = CreateTabs( Controls.TabContainer, 42, 34, UI.GetColorValueFromHexLiteral(0xFF331D05) );

	-- Create my pantheon/religion tab
	local religionData:table;
	local playerReligionName:string;
	if (m_PlayerReligionType >= 0) then
		religionData = GameInfo.Religions[m_PlayerReligionType];
		playerReligionName = TXT_MY_RELIGION;
	elseif (m_NumBeliefsEarned > 0) then
		playerReligionName = TXT_MY_RELIGION;
	else
		playerReligionName = TXT_MY_PANTHEON;
	end

	if(religionData == nil) then
		m_MyReligionTab = AddTab(playerReligionName, nil, ViewMyReligion);
	else
		m_MyReligionTab = AddTab(playerReligionName, religionData, ViewMyReligion);
	end
	
	-- Create other religion tabs
	local numFoundedReligions	:number = 0;
	local pAllReligions			:table = m_pGameReligion:GetReligions();

	for _, religionInfo in ipairs(pAllReligions) do
		local religionType:number = religionInfo.Religion;
		religionData = GameInfo.Religions[religionType];
		if(religionData.Pantheon == false and m_pGameReligion:HasBeenFounded(religionType)) then
			numFoundedReligions = numFoundedReligions + 1;
			if(religionType ~= m_PlayerReligionType) then
				AddTab(Game.GetReligion():GetName(religionType), religionData, function() ViewReligion(religionType); end);
			end
		end
	end

	--[[ DEBUG
	for i=1,1 do
		AddTab("Religion " .. i, "RELIGION_CATHOLICISM", function() ViewReligion(i); end);
		numFoundedReligions = numFoundedReligions + 1;
	end
	--]]

	-- Create "View All Religions" Tab
	if(numFoundedReligions > 0) then
		local maxReligions;
		local mapSizeIndex = Map.GetMapSize();
		local mapSize = GameInfo.Maps[mapSizeIndex];
		local mapSizeType = mapSize and mapSize.MapSizeType;
		if(mapSizeType) then
			for row in GameInfo.Map_GreatPersonClasses() do
				if(row.MapSizeType == mapSizeType and row.GreatPersonClassType == "GREAT_PERSON_CLASS_PROPHET") then
					maxReligions = row.MaxWorldInstances;
				end
			end
		end

		if(maxReligions == nil) then
			maxReligions = 0;
		end

		m_AllReligionsTab = AddTab(Locale.Lookup("LOC_UI_RELIGION_ALL_RELIGIONS", numFoundedReligions .. "/"  .. maxReligions), nil, ViewAllReligions);
	end

	-- Determine size of all tabs, to ensure they fit
	local totalSize:number = 0;
	for _, tabButton in ipairs(m_ReligionTabs.tabControls) do
		totalSize = totalSize + tabButton:GetSizeX() + PADDING_ICON + PADDING_TABS;
	end

	local numTabs:number = table.count(m_ReligionTabs.tabControls);
	local smallSize:number = SIZE_RELIGION_ICON_SMALL + (PADDING_ICON * 2);
	local bSmallTabs:boolean = totalSize > Controls.TabContainer:GetSizeX();
	for i, tabButton in ipairs(m_ReligionTabs.tabControls) do
		if(i ~= 1 and i ~= numTabs ) then
			local tabIcons:table = tabButton[DATA_FIELD_ICONS];
			if bSmallTabs then
				tabButton:SetText("");
				tabButton:SetSizeX(smallSize);
				tabButton[DATA_FIELD_SELECTION]:SetSizeX(smallSize + 4);
				tabIcons.Icon:SetOffsetX(PADDING_RELIGION_ICON_SMALL);
				tabIcons.SelectionIcon:SetOffsetX(PADDING_RELIGION_ICON_SELECTION_SMALL);
				tabButton:SetToolTipString(Game.GetReligion():GetName(tabButton[DATA_FIELD_INDEX]));
			else
				tabIcons.Icon:SetOffsetX(PADDING_RELIGION_ICON);
				tabIcons.SelectionIcon:SetOffsetX(PADDING_RELIGION_ICON_SELECTION);
			end
		end
	end
	
	m_ReligionTabs.EvenlySpreadTabs();
end

function AddTab(label:string, religionData:table, onClickCallback:ifunction)

	local tabInst:table = m_ReligionTabsIM:GetInstance();
	-- Store Selection and Icon children on the Button, so we can access it in the callback function below
	tabInst.Button[DATA_FIELD_SELECTION] = tabInst.Selection;
	tabInst.Button[DATA_FIELD_ICONS] = { Icon = tabInst.Icon, SelectionIcon = tabInst.SelectionIcon };

	tabInst.Button:SetText(label);
	local textControl = tabInst.Button:GetTextControl();
	textControl:SetHide(false);

	local textSize:number = textControl:GetSizeX();
	tabInst.Button:SetSizeX(textSize + PADDING_TAB_BUTTON_TEXT);
    tabInst.Button:RegisterCallback(Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	tabInst.Selection:SetSizeX(textSize + PADDING_TAB_BUTTON_TEXT + 4);

	if(religionData ~= nil) then
		tabInst.Button[DATA_FIELD_INDEX] = religionData.Index;
		local religionColor:number = UI.GetColorValue(religionData.Color);
		local textureOffsetX:number, textureOffsetY:number, textureSheet:string = IconManager:FindIconAtlas("ICON_" .. religionData.ReligionType, SIZE_RELIGION_ICON_SMALL);
		if(textureSheet == nil or textureSheet == "") then
			error("Could not find icon in AddTab: icon=\""..icon.."\", iconSize="..tostring(SIZE_RELIGION_ICON_SMALL) );
		else
			tabInst.Icon:SetColor(religionColor);
			tabInst.Icon:SetTexture(textureOffsetX, textureOffsetY, textureSheet);

			tabInst.SelectionIcon:SetColor(religionColor);
			tabInst.SelectionIcon:SetTexture(textureOffsetX, textureOffsetY, textureSheet);

			tabInst.Icon:SetHide(false);
			tabInst.SelectionIcon:SetHide(true);
		end
	else
		tabInst.Icon:SetHide(true);
		tabInst.SelectionIcon:SetHide(true);
	end

	local callback = function()
		if(m_ReligionTabs.prevSelectedControl ~= nil) then
			m_ReligionTabs.prevSelectedControl[DATA_FIELD_SELECTION]:SetHide(true);
			m_ReligionTabs.prevSelectedControl[DATA_FIELD_ICONS].SelectionIcon:SetHide(true);
		end
		tabInst.Selection:SetHide(false);
		tabInst.SelectionIcon:SetHide(false);
		onClickCallback();
	end

	m_ReligionTabs.AddTab(tabInst.Button, callback);
	return tabInst.Button;
end

-- ===========================================================================
--	Called when user clicks on "My Religion / Patheon" Tab
-- ===========================================================================
function ViewMyReligion()

	-- Tell the player what the next step is (cases organized in order they should appear to player
	if (m_PantheonBelief < 0) then
		if (m_CanCreatePantheon) then
			SelectPantheonBeliefs();
		else
			WorkingTowardsPantheon();
		end
	else
		if (m_NumBeliefsEarned == 0) then
			WorkingTowardsReligion();
		else
			if (m_PlayerReligionType < 0) then
				ChooseReligion();
			elseif (m_NumBeliefsEarned > m_NumBeliefsEquipped) then
				m_SelectedBeliefs = {};
				m_AddSelectedBeliefsIM:ResetInstances();
				m_SelectedReligion = { ID = m_PlayerReligionType };
				SelectReligionBeliefs();
			else
				ViewReligion(m_PlayerReligionType);
			end
		end
	end
end

-- ===========================================================================
--	Called anytime screen switches state
-- ===========================================================================
function ResetState()
	Controls.ViewReligion:SetHide(true);
	Controls.ChooseReligion:SetHide(true);
	Controls.AddBeliefs:SetHide(true);
	Controls.AddConfirmBeliefs:SetHide(true);
	Controls.AddReselectBeliefs:SetHide(true);
	Controls.AddReselectReligion:SetHide(true);
	Controls.SelectBeliefs:SetHide(true);
	Controls.ConfirmBeliefs:SetHide(true);
	Controls.ReselectBeliefs:SetHide(true);
	Controls.ReselectReligion:SetHide(true);
	Controls.SelectBeliefsPantheonIcon:SetHide(true);
	Controls.SelectBeliefsPantheonImage:SetHide(true);
	Controls.SelectBeliefsPantheonTitle:SetHide(true);
	Controls.SelectBeliefsPantheonDescription:SetHide(true);
	Controls.WorkingTowards:SetHide(true);
	Controls.WorkingTowardsReligion:SetHide(true);
	Controls.ViewAllReligions:SetHide(true);
end

-- ===========================================================================
--	Called if player does not yet have a Patheon
-- ===========================================================================
function WorkingTowardsPantheon()
	ResetState();

	Controls.WorkingTowards:SetHide(false);
	Controls.WorkingTowardsPantheon:SetOffsetY(0);
	Controls.WorkingTowardsPantheonTitle:LocalizeAndSetText("LOC_UI_RELIGION_NO_PANTHEON");
	local iPantheonFaith = m_pGameReligion:GetMinimumFaithNextPantheon();
	Controls.WorkingTowardsPantheonEffect:LocalizeAndSetText("LOC_RELIGIONPANEL_NEXT_STEP_FOUND_PANTHEON", iPantheonFaith);
	Controls.WorkingTowardsPantheonStatus:SetText(Locale.ToUpper(Locale.Lookup("LOC_UI_RELIGION_WORKING_TOWARDS_PANTHEON")));
	RealizeStack(Controls.WorkingTowardsPantheonStack);
end

-- ===========================================================================
--	Called if player has a Pantheon, but does not yet have a Religion
-- ===========================================================================
function WorkingTowardsReligion()
	ResetState();

	Controls.WorkingTowards:SetHide(false);
	Controls.WorkingTowardsReligion:SetHide(false);
	Controls.WorkingTowardsPantheon:SetOffsetY(OFFSET_WORKING_TOWARDS_PANTHEON);
	Controls.WorkingTowardsReligionTitle:SetText(Locale.ToUpper(Locale.Lookup("LOC_UI_RELIGION_WORKING_TOWARDS_RELIGION")));
	
	if (m_isHasProphet == false) then
		Controls.WorkingTowardsReligionDesc:LocalizeAndSetText("LOC_RELIGIONPANEL_NEXT_STEP_EARN_PROPHET");
	else
		Controls.WorkingTowardsReligionDesc:LocalizeAndSetText("LOC_RELIGIONPANEL_NEXT_STEP_USE_PROPHET");
	end

	local beliefName:string = "";
	local beliefDesc:string = "";
	if(m_PantheonBelief >= 0) then 
		beliefName = Locale.Lookup(GameInfo.Beliefs[m_PantheonBelief].Name);
		beliefDesc = Locale.Lookup(GameInfo.Beliefs[m_PantheonBelief].Description);
	end

	Controls.WorkingTowardsPantheonTitle:SetText(Locale.ToUpper(Locale.Lookup("LOC_UI_RELIGION_PANTHEON_NAME", beliefName)));
	Controls.WorkingTowardsPantheonStatus:SetText(Locale.ToUpper(Locale.Lookup("LOC_UI_RELIGION_PANTHEON_EFFECT")));
	Controls.WorkingTowardsPantheonEffect:LocalizeAndSetText(beliefDesc);

	RealizeStack(Controls.WorkingTowardsReligionStack);
	RealizeStack(Controls.WorkingTowardsPantheonStack);
end

-- ===========================================================================
--	Called if player is creating a new Patheon / Religion
-- ===========================================================================
function RealizeStack(stackControl:table, scrollControl:table, jumpToEnd:boolean)
	local instanceHeight = 0;
	if(stackControl ~= nil) then
		local prevHeight = stackControl:GetSizeY();
		stackControl:CalculateSize();
		stackControl:ReprocessAnchoring();
		instanceHeight = math.abs(stackControl:GetSizeY() - prevHeight);
	end
	if(scrollControl ~= nil) then
		scrollControl:CalculateSize();
		scrollControl:ReprocessAnchoring();
		if(jumpToEnd ~= nil) then
			if(jumpToEnd) then
				if(stackControl:GetSizeY() > scrollControl:GetSizeY()) then
					scrollControl:SetScrollValue(scrollControl:GetSizeY() + instanceHeight);
				else
					scrollControl:SetScrollValue(0);
				end
			end
		else
			scrollControl:SetScrollValue(0);
		end
	end
end

function SetBeliefSlotDisabled(beliefInst:table, bDisable:boolean)
	beliefInst.BeliefButton:SetDisabled(bDisable);
	if(bDisable) then
		beliefInst.BeliefIcon:SetColor(UI.GetColorValueFromHexLiteral(0xFF808080));
		beliefInst.BeliefLabel:SetColor(UI.GetColorValueFromHexLiteral(0xFF808080));
		beliefInst.BeliefDescription:SetColor(UI.GetColorValueFromHexLiteral(0xFF808080));
	else
		beliefInst.BeliefIcon:SetColor(UI.GetColorValue("COLOR_WHITE"));
		beliefInst.BeliefLabel:SetColor(UI.GetColorValueFromHexLiteral(0xFFB2A797)); 
		beliefInst.BeliefDescription:SetColor(UI.GetColorValueFromHexLiteral(0xFFB2A797));
	end
end

function PopulateAvailableBeliefs(beliefType:string)
	local Beliefs : table = {};

	m_Beliefs.IM:ResetInstances();
	m_srBeliefOrder = {};		-- ScreenReaderAccess
	m_srBeliefInst = {};		-- ScreenReaderAccess

	for row in GameInfo.Beliefs() do

		local bBeliefTypeAlreadySelected:boolean = false;
		for _, beliefID in ipairs(m_SelectedBeliefs) do
			if row.BeliefClassType == GameInfo.Beliefs[beliefID].BeliefClassType then
				bBeliefTypeAlreadySelected = true;
				break;
			end
		end

		if (not bBeliefTypeAlreadySelected and 
			not m_pGameReligion:IsInSomePantheon(row.Index) and
			not m_pGameReligion:IsInSomeReligion(row.Index) and
			not m_pGameReligion:IsTooManyForReligion(row.Index, m_PlayerReligionType) and
			((beliefType ~= nil and row.BeliefClassType == beliefType) or
			 (beliefType == nil and row.BeliefClassType ~= "BELIEF_CLASS_PANTHEON"))) then
			table.insert(Beliefs, row);
		end
	end

	table.sort(Beliefs, function(a, b)
		return a.BeliefClassType > b.BeliefClassType;
		end );

	for _, row in ipairs(Beliefs) do
		local beliefInst:table = m_Beliefs.IM:GetInstance();
		table.insert(m_srBeliefOrder, row.Index);		-- ScreenReaderAccess
		m_srBeliefInst[row.Index] = beliefInst;		-- ScreenReaderAccess
		beliefInst.BeliefLabel:LocalizeAndSetText(Locale.ToUpper(row.Name));
		beliefInst.BeliefDescription:LocalizeAndSetText(row.Description);
		beliefInst.BeliefButton:RegisterCallback(Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
		beliefInst.BeliefButton:RegisterCallback(Mouse.eLClick, function() OnBeliefSelected(row.Index, beliefInst) end);
		SetBeliefIcon(beliefInst.BeliefIcon, row.BeliefType, SIZE_BELIEF_ICON_LARGE);
		SetBeliefSlotDisabled(beliefInst, false);
	end

	RealizeStack(m_Beliefs.Stack, m_Beliefs.Scrollbar);
end

function OnBeliefSelected(beliefID:number, availableBeliefInst:table)
	SetBeliefSlotDisabled(availableBeliefInst, true);
	AddSelectedBelief(beliefID);
	RealizeStack(m_PendingBeliefs.Stack, m_PendingBeliefs.Scrollbar, true);
	table.insert(m_SelectedBeliefs, beliefID);

	if (m_PantheonBelief < 0) then
		ConfirmPantheonBeliefs();
	elseif(table.count(m_SelectedBeliefs) + m_NumBeliefsEquipped >= m_NumBeliefsEarned) then
		ConfirmReligionBeliefs();
	else
		PopulateAvailableBeliefs();
	end
end

function AddSelectedBelief(beliefID:number)
	local beliefInst:table = m_PendingBeliefs.IM:GetInstance();
	local beliefData:table = GameInfo.Beliefs[beliefID];
	beliefInst.BeliefLabel:LocalizeAndSetText(Locale.ToUpper(beliefData.Name));
	beliefInst.BeliefDescription:LocalizeAndSetText(beliefData.Description);
	beliefInst.BeliefButton:RegisterCallback(Mouse.eLClick, function() OnBeliefUnSelected(beliefID, beliefInst, availableBeliefInst) end);
    beliefInst.BeliefButton:RegisterCallback(Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end); 
    SetBeliefIcon(beliefInst.BeliefIcon, beliefData.BeliefType, SIZE_BELIEF_ICON_LARGE);
end

function OnBeliefUnSelected(beliefID:number, selectedBeliefInst:table, availableBeliefInst:table)
	-- Is this even necessary anymore? -sbatista
	if availableBeliefInst then
		SetBeliefSlotDisabled(availableBeliefInst, false);
	end
	m_PendingBeliefs.IM:ReleaseInstance(selectedBeliefInst);
	RealizeStack(m_PendingBeliefs.Stack, m_PendingBeliefs.Scrollbar, true);

	local beliefClass:string = GameInfo.Beliefs[beliefID].BeliefClassType;
	if beliefClass == "BELIEF_CLASS_FOLLOWER" then
		m_PendingBeliefs.IM:ResetInstances();
	else
		m_PendingBeliefs.IM:ReleaseInstance(selectedBeliefInst);
	end

	for i = table.count(m_SelectedBeliefs), 1, -1 do
		if beliefID == m_SelectedBeliefs[i] or beliefClass == "BELIEF_CLASS_FOLLOWER" then
			table.remove(m_SelectedBeliefs, i); 
		end
	end

	if(m_isConfirmingBeliefs) then
		if (m_PantheonBelief < 0) then
			SelectPantheonBeliefs();
		else
			SelectReligionBeliefs();
		end
	elseif(m_PantheonBelief >= 0) then 
		if(table.count(m_SelectedBeliefs) + m_NumBeliefsEquipped >= 1) then
			PopulateAvailableBeliefs();
		else
			PopulateAvailableBeliefs("BELIEF_CLASS_FOLLOWER");
		end
	end
end

function SelectPantheonBeliefs()
	ResetState();
	
	m_SelectedBeliefs = {};
	m_isConfirmingBeliefs = false;
	m_Beliefs = { IM = m_SelectBeliefsIM, Stack = Controls.AvailableBeliefs, Scrollbar = Controls.AvailableBeliefsScrollbar };
	m_PendingBeliefs = { IM = m_SelectedBeliefsIM, Stack = Controls.SelectedBeliefs, Scrollbar = SelectedBeliefsScrollbar };
	m_PendingBeliefs.IM:ResetInstances();

	Controls.ChooseBelief:SetHide(false);
	Controls.SelectBeliefs:SetHide(false);
	Controls.ChooseBeliefTitle:SetText(Locale.ToUpper(Locale.Lookup("LOC_UI_RELIGION_CHOOSE_PANTHEON_BELIEF")));
	Controls.ReligionOrPatheonTitle:SetText(Locale.ToUpper(Locale.Lookup("LOC_UI_RELIGION_CHOOSING_PANTHEON")));

	Controls.ReligionOrPatheonImage:SetOffsetY(OFFSET_CHOOSING_PANTHEON_BELIEFS);

	SetReligionIcon(Controls.ReligionOrPatheonImage);
	PopulateAvailableBeliefs("BELIEF_CLASS_PANTHEON");
end

function ConfirmPantheonBeliefs()
	ResetState();
	m_isConfirmingBeliefs = true;
	m_isConfirmedBeliefs = false;

	Controls.ChooseBelief:SetHide(true);
	Controls.SelectBeliefs:SetHide(false);
	Controls.ConfirmBeliefs:SetHide(false);
	Controls.ReselectBeliefs:SetHide(false);

	local beliefName:string = "";
	if(m_SelectedBeliefs[1] >= 0) then 
		beliefName = Locale.Lookup(GameInfo.Beliefs[m_SelectedBeliefs[1]].Name);
	end

	Controls.ReligionOrPatheonTitle:SetText(Locale.ToUpper(Locale.Lookup("LOC_UI_RELIGION_PANTHEON_NAME", beliefName)));

	Controls.ReselectBeliefs:LocalizeAndSetText("LOC_UI_RELIGION_RESELECT_BELIEFS");
	Controls.ReselectBeliefs:RegisterCallback(Mouse.eLClick, SelectPantheonBeliefs);
    Controls.ReselectBeliefs:RegisterCallback(Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end); 

	Controls.ConfirmBeliefs:LocalizeAndSetText("LOC_UI_RELIGION_FOUND_PANTHEON");
    Controls.ConfirmBeliefs:RegisterCallback(Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end); 
	m_srConfirm = function()		-- ScreenReaderAccess: named so the keyboard can call it
		if not m_isConfirmedBeliefs then
			m_isConfirmedBeliefs = true;
			local tParameters:table = {};
			tParameters[PlayerOperations.PARAM_BELIEF_TYPE] = GameInfo.Beliefs[m_SelectedBeliefs[1]].Hash;
			tParameters[PlayerOperations.PARAM_INSERT_MODE] = PlayerOperations.VALUE_EXCLUSIVE;
			UI.RequestPlayerOperation(Game.GetLocalPlayer(), PlayerOperations.FOUND_PANTHEON, tParameters);
			UI.PlaySound("Confirm_Religion");
		end
	end;
	Controls.ConfirmBeliefs:RegisterCallback(Mouse.eLClick, m_srConfirm);		-- ScreenReaderAccess
end

function ChooseReligion()
	ResetState();

	m_SelectedBeliefs = {};
	if(m_PendingBeliefs ~= nil) then
		m_PendingBeliefs.IM:ResetInstances();
	end

	if(m_SelectedReligion ~= nil) then
		if(m_SelectedReligion.Instance ~= nil) then
			m_SelectedReligion.Instance.ReligionButton:SetSelected(false);
		end
		m_SelectedReligion = nil;
	end

	m_ReligionSelections:ResetInstances();
	m_srReligionSelect = {};		-- ScreenReaderAccess

	Controls.ChooseReligion:SetHide(false);
	Controls.ConfirmReligion:LocalizeAndSetText("LOC_UI_RELIGION_CONFIRM_RELIGION");
	Controls.ChooseReligionName:LocalizeAndSetText("LOC_UI_RELIGION_CHOOSE_RELIGION_NAME");
	Controls.ChooseReligionTitle:LocalizeAndSetText(Locale.ToUpper("LOC_UI_RELIGION_CHOOSE_RELIGION"));
	Controls.PendingReligionTitle:LocalizeAndSetText(Locale.ToUpper("LOC_UI_RELIGION_NO_RELIGION_CHOSEN"));
	Controls.PendingReligionStatus:LocalizeAndSetText(Locale.ToUpper("LOC_UI_RELIGION_FOUNDING_RELIGION"));
	Controls.PendingReligionEffect:LocalizeAndSetText("LOC_UI_RELIGION_FOUNDING_RELIGION_INSTRUCTIONS");

	m_srNameChanged = function(editBox)		-- ScreenReaderAccess: named so the keyboard edit can restore it
		local userInput:string = editBox:GetText();
		if IsReligionNameValid(userInput) then
			Controls.ConfirmReligion:SetDisabled(m_SelectedReligion == nil);
			Controls.PendingReligionTitle:SetText(Locale.ToUpper(userInput));
		else
			Controls.ConfirmReligion:SetDisabled(true);
			Controls.PendingReligionTitle:LocalizeAndSetText(Locale.ToUpper("LOC_UI_RELIGION_REQUIRES_NAME"));
		end
	end;
	Controls.ChooseReligionName:RegisterStringChangedCallback(m_srNameChanged);		-- ScreenReaderAccess

    Controls.ConfirmReligion:RegisterCallback(Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end); 
	Controls.ConfirmReligion:RegisterCallback(Mouse.eLClick, SelectReligionBeliefs);

	for row in GameInfo.Religions() do
		if (row.Pantheon == false and not m_pGameReligion:HasBeenFounded(row.Index)) then
			local religionInst = m_ReligionSelections:GetInstance();
			SetReligionIcon(religionInst.ReligionImage, row.ReligionType, SIZE_RELIGION_ICON_LARGE, row.Color);
			
			local religionName:string = Locale.Lookup(row.Name);
			religionInst.ReligionButton:SetToolTipString(religionName);

            religionInst.ReligionButton:RegisterCallback(Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end); 
			local srSelect = function()		-- ScreenReaderAccess: named so the keyboard can call it
				if(m_SelectedReligion ~= nil) then
					if(m_SelectedReligion.Instance ~= religionInst) then
						m_SelectedReligion.Instance.ReligionButton:SetSelected(false);
						m_SelectedReligion.Instance = religionInst;
						m_SelectedReligion.ID = row.Index;
					end
				else
					m_SelectedReligion = { ID = row.Index, Instance = religionInst };
				end

				religionInst.ReligionButton:SetSelected(true);
				SetReligionIcon(Controls.PendingReligionImage, row.ReligionType, SIZE_RELIGION_ICON_HUGE, row.Color);

				local canChangeName = GameCapabilities.HasCapability("CAPABILITY_RENAME");
				if(row.RequiresCustomName and canChangeName) then
					Controls.ConfirmReligion:SetDisabled(true);
					Controls.PendingReligionTitle:LocalizeAndSetText("LOC_UI_RELIGION_REQUIRES_NAME");
					Controls.ChooseReligionName:SetDisabled(false);
					Controls.ChooseReligionNameButton:SetDisabled(false);
					Controls.ChooseReligionName:SetText("");
					Controls.ChooseReligionName:TakeFocus();
				else
					Controls.ChooseReligionName:SetDisabled(true);
					Controls.ChooseReligionNameButton:SetDisabled(true);
					Controls.ChooseReligionName:SetText(religionName);
					Controls.PendingReligionTitle:SetText(Locale.ToUpper(religionName));
					Controls.ConfirmReligion:SetDisabled(m_SelectedReligion == nil);
				end
			end;
			m_srReligionSelect[row.Index] = srSelect;		-- ScreenReaderAccess
			religionInst.ReligionButton:RegisterCallback(Mouse.eLClick, srSelect);		-- ScreenReaderAccess
		end
	end

	SetReligionIcon(Controls.PendingReligionImage);
	RealizeStack(Controls.ChooseReligionItems, Controls.ChooseReligionScrollbar);
end

-- ===========================================================================
function IsReligionNameValid(name:string)
	if name ~= nil then
		-- If it's really just the label in the customize name edit box, mark it as not being valid.
		if Locale.ToUpper(name) == Locale.ToUpper(Locale.Lookup("LOC_UI_RELIGION_CHOOSE_RELIGION_NAME")) then
			return false;
		end

		for i = 1, #name do
		local c = name:sub(i,i)
			if(c ~= " ") then return true; end
		end
	end
	return false;
end

function SelectReligionBeliefs()
	ResetState();

	if(m_PendingBeliefs ~= nil) then
		--Likely in hotseat mode, previous player's choices were still presesnt.
		m_PendingBeliefs.IM:ResetInstances();
		if table.count(m_SelectedBeliefs) > 0 then
			for _, beliefIndex in ipairs(m_SelectedBeliefs) do
				AddSelectedBelief(beliefIndex);
			end
			RealizeStack(m_PendingBeliefs.Stack, m_PendingBeliefs.Scrollbar, true);
		end
	end

	m_isConfirmingBeliefs = false;

	local pantheonBelief:table = GameInfo.Beliefs[m_PantheonBelief];
	local religionData:table = GameInfo.Religions[m_SelectedReligion.ID];

	if(m_NumBeliefsEquipped == 0) then
		m_Beliefs = { IM = m_SelectBeliefsIM, Stack = Controls.AvailableBeliefs, Scrollbar = Controls.AvailableBeliefsScrollbar };
		m_PendingBeliefs = { IM = m_SelectedBeliefsIM, Stack = Controls.SelectedBeliefs, Scrollbar = SelectedBeliefsScrollbar };

		Controls.ChooseBelief:SetHide(false);
		Controls.SelectBeliefs:SetHide(false);
		Controls.SelectBeliefsPantheonIcon:SetHide(false);
		Controls.SelectBeliefsPantheonImage:SetHide(false);
		Controls.SelectBeliefsPantheonTitle:SetHide(false);
		Controls.SelectBeliefsPantheonDescription:SetHide(false);

		Controls.ReligionOrPatheonImage:SetOffsetX(OFFSET_CHOOSING_RELIGION_BELIEFS);
		Controls.SelectBeliefsPantheonTitle:SetOffsetX(OFFSET_CHOOSING_RELIGION_BELIEFS);

		Controls.SelectBeliefsPantheonTitle:SetText(Locale.ToUpper(Locale.Lookup("LOC_UI_RELIGION_PANTHEON_NAME", pantheonBelief.Name)));
		Controls.SelectBeliefsPantheonDescription:LocalizeAndSetText(pantheonBelief.Description);
		SetBeliefIcon(Controls.SelectBeliefsPantheonIcon, pantheonBelief.BeliefType, SIZE_BELIEF_ICON_LARGE);

		local szPendingTitle = Controls.PendingReligionTitle:GetText();
		if szPendingTitle then
			Controls.ReligionOrPatheonTitle:LocalizeAndSetText(szPendingTitle);
		elseif m_PlayerReligionType >= 0 then
			Controls.ReligionOrPatheonTitle:LocalizeAndSetText(GameInfo.Religions[m_PlayerReligionType].Name);
		else
			UI.DataError("Failed to set text on ReligionOrPatheonTitle");
		end

		Controls.ChooseBeliefTitle:LocalizeAndSetText(Locale.ToUpper("LOC_UI_RELIGION_CHOOSE_RELIGION_BELIEF"));
		SetReligionIcon(Controls.ReligionOrPatheonImage, religionData.ReligionType, SIZE_RELIGION_ICON_HUGE, religionData.Color);
	else
		m_Beliefs = { IM = m_AddAvailableBeliefsIM, Stack = Controls.AddAvailableBeliefs, Scrollbar = Controls.AddAvailableBeliefsScrollbar };
		m_PendingBeliefs = { IM = m_AddSelectedBeliefsIM, Stack = Controls.AddBeliefsReligionBeliefs, Scrollbar = Controls.AddBeliefsReligionScroll };

		Controls.AddBelief:SetHide(false);
		Controls.AddBeliefs:SetHide(false);

		Controls.AddBeliefsPantheonTitle:SetText(Locale.ToUpper(Locale.Lookup("LOC_UI_RELIGION_PANTHEON_NAME", pantheonBelief.Name)));
		Controls.AddBeliefsPantheonDescription:LocalizeAndSetText(pantheonBelief.Description);
		SetBeliefIcon(Controls.AddBeliefsPantheonIcon, pantheonBelief.BeliefType, SIZE_BELIEF_ICON_LARGE);

		Controls.AddBeliefsReligionTitle:LocalizeAndSetText(Locale.ToUpper(religionData.Name));

		Controls.AddBeliefTitle:LocalizeAndSetText(Locale.ToUpper("LOC_UI_RELIGION_CHOOSE_A_BELIEF"));
		SetReligionIcon(Controls.AddBeliefsReligionImage, religionData.ReligionType, SIZE_RELIGION_ICON_HUGE, religionData.Color);

		local religion:table = nil;
		for _, tmp in ipairs(m_pGameReligion:GetReligions()) do
			if (tmp.Religion == m_PlayerReligionType) then
				religion = tmp;
				break;
			end
		end

		m_ExistingReligionBeliefsIM:ResetInstances();
		for _, beliefIndex in ipairs(religion.Beliefs) do
			belief = GameInfo.Beliefs[beliefIndex];
			local beliefInst:table = m_ExistingReligionBeliefsIM:GetInstance();
			beliefInst.BeliefBG:SetColor(UI.GetColorValue("COLOR_WHITE"));
			beliefInst.BeliefLabel:LocalizeAndSetText(Locale.ToUpper(belief.Name));
			beliefInst.BeliefDescription:LocalizeAndSetText(belief.Description);
			SetBeliefIcon(beliefInst.BeliefIcon, belief.BeliefType, SIZE_BELIEF_ICON_LARGE);
			beliefInst.BeliefIcon:SetHide(false);
		end

		Controls.AddBeliefsReligionScroll:CalculateSize();

		local ownerPlayer:table = Players[religion.Founder];
		local playerReligion:table = ownerPlayer:GetReligion();
		local religionData:table = GameInfo.Religions[m_PlayerReligionType];
		local civID:number = PlayerConfigurations[religion.Founder]:GetCivilizationTypeID();
		local civName:string = Locale.Lookup(GameInfo.Civilizations[civID].Name);
		local holyCity:table = CityManager.GetCity(playerReligion:GetHolyCityID());
		Controls.AddBeliefsReligionHolyCity:SetText(Locale.ToUpper(Locale.Lookup("LOC_UI_RELIGION_HOLY_CITY", holyCity:GetName())));

		Controls.AddBeliefsReligionTitle:LocalizeAndSetText(Locale.ToUpper(religionData.Name));
		Controls.AddBeliefsReligionFounder:SetText(Locale.ToUpper(Locale.Lookup("LOC_UI_RELIGION_FOUNDER_NAME", civName)));
		Controls.AddBeliefsReligionBeliefsHeader:SetText(Locale.ToUpper(Locale.Lookup("LOC_UI_RELIGION_BELIEFS_OF_RELIGION", religionData.Name)))
		RealizeStack(Controls.AddBeliefsReligionStack, Controls.AddBeliefsReligionScroll);

		if table.count(m_SelectedBeliefs) > 0 then
			for _, beliefIndex in ipairs(m_SelectedBeliefs) do
				AddSelectedBelief(beliefIndex);
			end
			RealizeStack(m_PendingBeliefs.Stack, m_PendingBeliefs.Scrollbar, true);
		end

		-- Gather data necessary for cities panel
		local numDominantCities:number = 0;
		local majorPlayers:table = PlayerManager.GetAlive();
		for _, player in ipairs(majorPlayers) do
			local playerCities:table = player:GetCities();
			for _, city in playerCities:Members() do
				local cityReligion:table = city:GetReligion();
				if(cityReligion:GetMajorityReligion() == m_PlayerReligionType) then
					numDominantCities = numDominantCities + 1;
				end
			end
		end

		-- Update dominant city text
		if(numDominantCities > 1) then
			Controls.AddBeliefsReligionDominance:SetText(Locale.ToUpper(Locale.Lookup("LOC_UI_RELIGION_RELIGION_DOMINANCE_PLURAL", numDominantCities)));
		else
			Controls.AddBeliefsReligionDominance:SetText(Locale.ToUpper(Locale.Lookup("LOC_UI_RELIGION_RELIGION_DOMINANCE", numDominantCities)));
		end
	end

	if(table.count(m_SelectedBeliefs) + m_NumBeliefsEquipped >= 1) then
		PopulateAvailableBeliefs();
	else
		PopulateAvailableBeliefs("BELIEF_CLASS_FOLLOWER");
	end
end

function ConfirmReligionBeliefs()
	ResetState();
	m_isConfirmedBeliefs = false;
	m_isConfirmingBeliefs = true;

	local confirmBeliefsButton:table;
	local reselectBeliefsButton:table;
	local reselectReligionButton:table;

	if(m_NumBeliefsEquipped == 0) then
		Controls.SelectBeliefs:SetHide(false);
		confirmBeliefsButton = Controls.ConfirmBeliefs;
		reselectBeliefsButton = Controls.ReselectBeliefs;
		reselectReligionButton = Controls.ReselectReligion;
	else
		Controls.AddBeliefs:SetHide(false);
		confirmBeliefsButton = Controls.AddConfirmBeliefs;
		reselectBeliefsButton = Controls.AddReselectBeliefs;
		reselectReligionButton = Controls.AddReselectReligion;
	end

	Controls.AddBelief:SetHide(true);
	Controls.ChooseBelief:SetHide(true);
	confirmBeliefsButton:SetHide(false);
	reselectBeliefsButton:SetHide(false);
	Controls.SelectBeliefsPantheonIcon:SetHide(false);
	Controls.SelectBeliefsPantheonImage:SetHide(false);
	Controls.SelectBeliefsPantheonTitle:SetHide(false);
	Controls.SelectBeliefsPantheonDescription:SetHide(false);

	local pantheonBelief:table = GameInfo.Beliefs[m_PantheonBelief];
	Controls.SelectBeliefsPantheonTitle:SetText(Locale.ToUpper(Locale.Lookup("LOC_UI_RELIGION_PANTHEON_NAME", pantheonBelief.Name)));
	Controls.SelectBeliefsPantheonDescription:LocalizeAndSetText(pantheonBelief.Description);

	if (m_PlayerReligionType >= 0) then
		reselectReligionButton:SetHide(true);
		confirmBeliefsButton:SetText(Locale.Lookup("LOC_UI_RELIGION_CONFIRM_RELIGION"));
		reselectBeliefsButton:SetText(Locale.Lookup("LOC_UI_RELIGION_RESELECT_BELIEF"));
	else
		reselectReligionButton:SetHide(false);
		confirmBeliefsButton:SetText(Locale.Lookup("LOC_UI_RELIGION_FOUND_RELIGION"));
		reselectBeliefsButton:SetText(Locale.Lookup("LOC_UI_RELIGION_RESELECT_BELIEFS"));
	end
	
    reselectBeliefsButton:RegisterCallback(Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end); 
    m_srReselectBeliefs = function()		-- ScreenReaderAccess: named so the keyboard can call it
		m_SelectedBeliefs = {};
		if(m_PendingBeliefs ~= nil) then
			m_PendingBeliefs.IM:ResetInstances();
			RealizeStack(m_PendingBeliefs.Stack, m_PendingBeliefs.Scrollbar);
		end
		SelectReligionBeliefs();
	end;
	reselectBeliefsButton:RegisterCallback(Mouse.eLClick, m_srReselectBeliefs);		-- ScreenReaderAccess

	reselectReligionButton:LocalizeAndSetText("LOC_UI_RELIGION_RESELECT_RELIGION");
	reselectReligionButton:RegisterCallback(Mouse.eLClick, ChooseReligion);
    reselectReligionButton:RegisterCallback(Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end); 

	m_srConfirm = function()		-- ScreenReaderAccess: named so the keyboard can call it
    confirmBeliefsButton:RegisterCallback(Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end); 
        		
		if not m_isConfirmedBeliefs then

			m_isConfirmedBeliefs = true;

			if (m_PlayerReligionType < 0) then
				local tParameters = {};
				tParameters[PlayerOperations.PARAM_INSERT_MODE] = PlayerOperations.VALUE_EXCLUSIVE;
				tParameters[PlayerOperations.PARAM_RELIGION_TYPE] = GameInfo.Religions[m_SelectedReligion.ID].Hash;
				if(GameInfo.Religions[m_SelectedReligion.ID].RequiresCustomName) then
					tParameters[PlayerOperations.PARAM_RELIGION_CUSTOM_NAME] = Controls.ChooseReligionName:GetText();
				end
			
				UI.RequestPlayerOperation(Game.GetLocalPlayer(), PlayerOperations.FOUND_RELIGION, tParameters);
			end

			for _, belief in ipairs(m_SelectedBeliefs) do
				local tParameters = {};
				tParameters[PlayerOperations.PARAM_BELIEF_TYPE] = GameInfo.Beliefs[belief].Hash;
				tParameters[PlayerOperations.PARAM_INSERT_MODE] = PlayerOperations.VALUE_EXCLUSIVE;
				UI.RequestPlayerOperation(Game.GetLocalPlayer(), PlayerOperations.ADD_BELIEF, tParameters);
			end

			UI.PlaySound("Confirm_Religion");
			if (m_PlayerReligionType >= 0) then
				Close();
			end
		end
	end;
	confirmBeliefsButton:RegisterCallback(Mouse.eLClick, m_srConfirm);		-- ScreenReaderAccess
end

function SetReligionIcon(targetControl:table, religionType:string, iconSize:number, religionColor:string)
	if(religionType ~= nil) then
		local textureOffsetX:number, textureOffsetY:number, textureSheet:string = IconManager:FindIconAtlas("ICON_" .. religionType, iconSize);
		if(textureSheet == nil or textureSheet == "") then
			error("Could not find icon in SetReligionIcon: religionType=\""..religionType.."\", iconSize="..tostring(iconSize) );
		else
			targetControl:SetTexture(textureOffsetX, textureOffsetY, textureSheet);
			targetControl:SetSizeVal(iconSize, iconSize);
		end
	else
		Controls.PendingReligionImage:SetTexture(0,0,"Religion_Generic");
		Controls.PendingReligionImage:SetSizeVal(SIZE_RELIGION_ICON_HUGE, SIZE_RELIGION_ICON_HUGE);
	end
	if(religionColor == nil) then
		targetControl:SetColor(UI.GetColorValue("COLOR_WHITE"));
		Controls.PendingReligionImage:SetColor(UI.GetColorValue("COLOR_WHITE"));
	else
		targetControl:SetColor(UI.GetColorValue(religionColor));
		Controls.PendingReligionImage:SetColor(UI.GetColorValue(religionColor));
	end
end

function SetBeliefIcon(targetControl:table, beliefType:string, iconSize:number)
	local textureOffsetX:number, textureOffsetY:number, textureSheet:string = IconManager:FindIconAtlas("ICON_" .. beliefType, iconSize);
	if(textureSheet == nil or textureSheet == "") then
		error("Could not find icon in SetBeliefIcon: beliefType=\""..beliefType.."\", iconSize="..tostring(iconSize) );
	else
		targetControl:SetTexture(textureOffsetX, textureOffsetY, textureSheet);
		targetControl:SetSizeVal(iconSize, iconSize);
	end
end

-- ===========================================================================
--	Called if player selects any religion tab
-- ===========================================================================
function ViewReligion(religionType:number)
	ResetState();

	-- Ensure we are trying to view a valid religion
	local religion:table = nil;
	for _, tmp in ipairs(m_pGameReligion:GetReligions()) do
		if (tmp.Religion == religionType) then
			religion = tmp;
			break;
		end
	end

	if(religion == nil or not m_pGameReligion:HasBeenFounded(religionType)) then 
		print("Error, attempting to view 'nil' or 'unfounded' religion, religionType=" .. religionType); 
		return;
	end

	Controls.ViewReligion:SetHide(false);

	if(m_SelectedReligion ~= nil and m_SelectedReligion.Instance ~= nil) then
		m_SelectedReligion.Instance.ReligionButton:SetSelected(false);          
	end
	m_SelectedReligion = { ID = religionType };

	-- Gather player data
	local ownerPlayer:table = Players[religion.Founder];
	local localPlayerID:number = GetDisplayPlayerID();
	local localPlayer:table = Players[localPlayerID];
	local localDiplomacy:table = localPlayer:GetDiplomacy();
	local playerReligion:table = ownerPlayer:GetReligion();
	local religionData:table = GameInfo.Religions[religionType];
	local pantheonBelief:number = playerReligion:GetPantheon();
	local belief:table= GameInfo.Beliefs[pantheonBelief];
	local civID:number = PlayerConfigurations[religion.Founder]:GetCivilizationTypeID();

	if religion.Founder == localPlayerID or localDiplomacy:HasMet(religion.Founder) or Game.GetLocalObserver() == PlayerTypes.OBSERVER then
		local civName:string = Locale.Lookup(GameInfo.Civilizations[civID].Name);
		Controls.ViewReligionFounder:SetText(Locale.ToUpper(Locale.Lookup("LOC_UI_RELIGION_FOUNDER_NAME", civName)));
		local holyCity:table = CityManager.GetCity(playerReligion:GetHolyCityID());
		if holyCity ~= nil then
			Controls.ViewReligionHolyCity:SetText(Locale.ToUpper(Locale.Lookup("LOC_UI_RELIGION_HOLY_CITY", holyCity:GetName())));
		else
			Controls.ViewReligionHolyCity:LocalizeAndSetText(Locale.ToUpper("LOC_UI_RELIGION_HOLY_CITY_NONE"));
		end
	else
		Controls.ViewReligionFounder:SetText(Locale.ToUpper(Locale.Lookup("LOC_UI_RELIGION_FOUNDER_NAME", Locale.Lookup("LOC_DIPLOPANEL_UNMET_PLAYER"))));
		Controls.ViewReligionHolyCity:SetText(Locale.ToUpper(Locale.Lookup("LOC_UI_RELIGION_HOLY_CITY", Locale.Lookup("LOC_UI_RELIGION_UNKNOWN_CITY"))));
	end

	-- Update text and icons
	SetBeliefIcon(Controls.ViewReligionPantheonIcon, belief.BeliefType, SIZE_BELIEF_ICON_LARGE);
	SetReligionIcon(Controls.ViewReligionImage, religionData.ReligionType, SIZE_RELIGION_ICON_LARGE, religionData.Color);

	Controls.CitiesHeader:LocalizeAndSetText(Locale.ToUpper("LOC_UI_RELIGION_CITIES"));
	Controls.FollowersHeader:LocalizeAndSetText(Locale.ToUpper("LOC_UI_RELIGION_FOLLOWERS"));
	Controls.PantheonBeliefHeader:LocalizeAndSetText(Locale.ToUpper("LOC_UI_RELIGION_CITIES_PANTHEON_BELIEF"));
	Controls.ViewReligionTitle:SetText(Locale.ToUpper(Locale.Lookup(Game.GetReligion():GetName(religionType))));
	
	Controls.ViewReligionPantheonTitle:SetText(Locale.ToUpper(Locale.Lookup("LOC_UI_RELIGION_PANTHEON_NAME", belief.Name)));
	Controls.ViewReligionBeliefsHeader:SetText(Locale.ToUpper(Locale.Lookup("LOC_UI_RELIGION_BELIEFS_OF_RELIGION", Game.GetReligion():GetName(religionType))))
	Controls.ViewReligionPantheonDescription:LocalizeAndSetText(belief.Description);

	-- Spawn religion beliefs
	m_ReligionBeliefsIM:ResetInstances();
	AddUnlockedBeliefs(religion);
	AddLockedBeliefs(religion);

	RealizeStack(Controls.ViewReligionBeliefs, Controls.ViewReligionScroll);
	
	-- Spawn religion icons for reach founded religion
	m_ReligionIcons = {};
	local numReligions:number = 0;
	m_ReligionIconsIM:ResetInstances();
	local allReligions:table = m_pGameReligion:GetReligions();
	for _, religionInfo in ipairs(allReligions) do
		local religionData = GameInfo.Religions[religionInfo.Religion];
		if(religionData.Pantheon == false and m_pGameReligion:HasBeenFounded(religionInfo.Religion)) then
			local religionIconInst:table = m_ReligionIconsIM:GetInstance();
			SetReligionIcon(religionIconInst.ReligionIcon, religionData.ReligionType, SIZE_RELIGION_ICON_SMALL, religionData.Color);
			table.insert(m_ReligionIcons, {Religion = religionInfo.Religion, Icon = religionIconInst.ReligionIcon});
			numReligions = numReligions + 1;
		end
	end

	-- Calculate size of followers buckets based on number of founded religions
	local bucketSize:number = Controls.ReligionIcons:GetSizeX() / numReligions;
	for i, religionEntry in ipairs(m_ReligionIcons) do
		local leftX:number = (i - 1) * bucketSize;
		religionEntry.Icon:SetOffsetX(leftX + (bucketSize / 2) - (SIZE_RELIGION_ICON_SMALL / 2));
	end

	-- Set tooltips for Unit Icons
	local showUnitIcons:boolean = religion.Founder == localPlayerID;
	local canProduceApostle:boolean = false;
	local canProduceMissionary:boolean = false;

	-- Gather data necessary for cities panel
	local cities:table = {};
	local numDominantCities:number = 0;
	local majorPlayers:table = PlayerManager.GetAlive();
	for _, player in ipairs(majorPlayers) do
		local playerID:number = player:GetID();
		local playerCities:table = player:GetCities();
		local playerReligion:table = player:GetReligion();
		local playerPantheon:number = playerReligion:GetPantheon();

		for _, city in playerCities:Members() do
			local bIncludeCity:boolean = false;
			local religionFollowers:table = nil;
			local cityReligion:table = city:GetReligion();
			local religionsInCity:table = cityReligion:GetReligionsInCity();

			if(cityReligion:GetMajorityReligion() == religionType) then
				numDominantCities = numDominantCities + 1;
				if(m_CitiesFilter == CITIES_FILTER.FOLLOWING_RELIGION) then bIncludeCity = true; end
			end

			for _, cityReligionData in ipairs(religionsInCity) do
				local bIncludeData:boolean = false;
				for _, religionEntry in ipairs(m_ReligionIcons) do
					if(cityReligionData.Religion == religionEntry.Religion) then
						bIncludeData = true;
						break;
					end
				end
				if(bIncludeData) then
					if(religionFollowers == nil) then religionFollowers = {}; end
					local followers = cityReligionData.Followers;
					religionFollowers[cityReligionData.Religion] = followers;
					if(m_CitiesFilter == CITIES_FILTER.RELIGION_PRESENT and cityReligionData.Religion == religionType) then
						bIncludeCity = true;
					end
				end
			end
			
			if(bIncludeCity) then
				table.insert(cities, {City = city, Pantheon = cityReligion:GetActivePantheon(), Followers = religionFollowers});
			end

			if(showUnitIcons and playerID == localPlayerID and (not canProduceApostle or not canProduceMissionary)) then
				local buildQueue:table = city:GetBuildQueue();
				if not canProduceApostle then
					canProduceApostle = buildQueue:CanProduce("UNIT_APOSTLE", false, true);
				end
				if not canProduceMissionary then
					canProduceMissionary = buildQueue:CanProduce("UNIT_MISSIONARY", false, true);
				end
			end
		end
	end

	-- Add scenario specific religious units
	m_UnitIconIM:ResetInstances();

	-- Table of unit types to ignore since they have already been added
	local typesToIgnore:table = {};

	local localPlayer = Players[Game.GetLocalPlayer()];
	local localPlayerCities = localPlayer:GetCities();

	for _, city in localPlayerCities:Members() do
		local buildQueue:table = city:GetBuildQueue();

		for row in GameInfo.Units() do
			if row.ReligiousStrength > 0 and not typesToIgnore[row.UnitType] then
				-- Create instance
				local unitIconInst:table = m_UnitIconIM:GetInstance();
				typesToIgnore[row.UnitType] = true;

				-- Update unit icon
				local iconString:string = "ICON_" .. row.UnitType .. "_PORTRAIT";
				unitIconInst.UnitIcon:SetIcon(iconString);

				-- Determine how many of these units do we own
				local howMany:number = 0;
				local pLocalPlayerUnits = localPlayer:GetUnits();
				for _, pUnit in pLocalPlayerUnits:Members() do
					if row.Index == pUnit:GetType() then
						howMany = howMany + 1;
					end
				end
				
				-- Display how many we own or alpha out icons when we don't own any
				if howMany <= 0 then
					unitIconInst.UnitCount:SetHide(true);
					unitIconInst.UnitIconBacking:SetAlpha(SIZE_UNIT_ICON_NONE_ALPHA);
				else
					unitIconInst.UnitCount:SetText(howMany);
					unitIconInst.UnitCount:SetHide(false);
					unitIconInst.UnitIconBacking:SetAlpha(1.0);
				end

				if buildQueue:CanProduce(row.UnitType, false, true) then
					-- If we can currently produce set tooltip to normal description
					if UNIT_ICON_TOOLTIPS[row.UnitType] and UNIT_ICON_TOOLTIPS[row.UnitType].canProduce then
						unitIconInst.UnitIconBacking:SetToolTipString(Locale.Lookup(UNIT_ICON_TOOLTIPS[row.UnitType].canProduce));
					else
						unitIconInst.UnitIconBacking:SetToolTipString(Locale.Lookup(row.Name));
					end
				else
					-- If not set tooltip to tell player how to be able to produce them
					if UNIT_ICON_TOOLTIPS[row.UnitType] and UNIT_ICON_TOOLTIPS[row.UnitType].cannotProduce then
						unitIconInst.UnitIconBacking:SetToolTipString(Locale.Lookup(UNIT_ICON_TOOLTIPS[row.UnitType].cannotProduce));
					else
						unitIconInst.UnitIconBacking:SetToolTipString(Locale.Lookup(row.Name));
					end
				end
			end
		end
	end

	RealizeStack(Controls.IconStack);
	RealizeStack(Controls.ViewReligionStack);

	-- Update dominant city text
	if(numDominantCities == 1) then
		Controls.ViewReligionDominance:SetText(Locale.ToUpper(Locale.Lookup("LOC_UI_RELIGION_RELIGION_DOMINANCE", numDominantCities)));
	else
		Controls.ViewReligionDominance:SetText(Locale.ToUpper(Locale.Lookup("LOC_UI_RELIGION_RELIGION_DOMINANCE_PLURAL", numDominantCities)));
	end

	-- Sort cities based on number of followers
	table.sort(cities, function(a, b) return SortCitiesByFollowers(a.City:GetReligion(), b.City:GetReligion(), religionType) end);

	-- Spawn cities and populate follower for each founded religion
	m_CitiesIM:ResetInstances();
	for i = 1, table.count(cities) do
		local cityData:table = cities[i].City;
		local cityPantheon:number = cities[i].Pantheon;
		local cityFollowers:table = cities[i].Followers;
		local cityInst:table = m_CitiesIM:GetInstance();
		local cityOwner:number = cityData:GetOwner();
		local civID:number = PlayerConfigurations[cityOwner]:GetCivilizationTypeID();
		local civName:string = Locale.Lookup(GameInfo.Civilizations[civID].Name);
		
		if localPlayerID == cityOwner or localDiplomacy:HasMet(cityOwner) or Game.GetLocalObserver() == PlayerTypes.OBSERVER then
			cityInst.CityName:LocalizeAndSetText("LOC_UI_RELIGION_CITY_NAME", cityData:GetName(), civName);
		else
			cityInst.CityName:LocalizeAndSetText("LOC_UI_RELIGION_UNKNOWN_CITY");
		end

		if(cityPantheon < 0) then
			cityInst.CityPantheon:LocalizeAndSetText("LOC_UI_RELIGION_NO_PANTHEON_BELIEF");
		else
			cityInst.CityPantheon:LocalizeAndSetText(GameInfo.Beliefs[cityPantheon].Description);
		end

		local cityFollowersIM:table = cityInst[DATA_FIELD_FOLLOWERS_IM];
		if(cityFollowersIM ~= nil) then
			cityFollowersIM:ResetInstances();
		else
			cityFollowersIM = InstanceManager:new("CityFollowers", "BG", cityInst.CityFollowers);
			cityInst[DATA_FIELD_FOLLOWERS_IM] = cityFollowersIM;
		end

		local nextX:number = 0;
		local nextSizeX:number = bucketSize - 2;
		for i, religionEntry in ipairs(m_ReligionIcons) do
			local followersInst:table = cityFollowersIM:GetInstance();

			if(i > 1) then
				nextX = nextX + 2;
			end

			followersInst.BG:SetOffsetX(nextX);
			followersInst.BG:SetSizeX(nextSizeX);
			local rowSize = math.max(cityInst.CityPantheon:GetSizeY() + 20, 38);
			followersInst.BG:SetSizeY(rowSize);

			if(cityFollowers ~= nil and cityFollowers[religionEntry.Religion] ~= nil and cityFollowers[religionEntry.Religion] ~= 0) then
				followersInst.Followers:SetText(cityFollowers[religionEntry.Religion]);
			else
				followersInst.Followers:SetText("-");
			end
			followersInst.Followers:SetOffsetX((nextSizeX / 2) - (followersInst.Followers:GetSizeX() / 2));
			nextX = nextX + bucketSize;
		end
	end

	RealizeStack(Controls.Cities, Controls.CitiesScrollbar);
	RealizeSortTypePulldown();
end

-- ==============================================
function AddUnlockedBeliefs(religion)
	for _, beliefIndex in ipairs(religion.Beliefs) do
		belief = GameInfo.Beliefs[beliefIndex];
		local beliefInst:table = m_ReligionBeliefsIM:GetInstance();
		beliefInst.BeliefBG:SetColor(UI.GetColorValue("COLOR_WHITE"));
		beliefInst.BeliefLabel:SetText(Locale.ToUpper(belief.Name));
		beliefInst.BeliefDescription:LocalizeAndSetText(belief.Description);
		SetBeliefIcon(beliefInst.BeliefIcon, belief.BeliefType, SIZE_BELIEF_ICON_LARGE);
		beliefInst.BeliefIcon:SetHide(false);
	end
end

-- ==============================================
function AddLockedBeliefs(religion)
	local numLockedBeliefs:number = NUM_MAX_BELIEFS - table.count(religion.Beliefs);
	for i = 1, numLockedBeliefs do
		local beliefInst:table = m_ReligionBeliefsIM:GetInstance();
		beliefInst.BeliefBG:SetColor(UI.GetColorValueFromHexLiteral(0xFF808080));
		beliefInst.BeliefLabel:SetText(Locale.ToUpper(Locale.Lookup("LOC_UI_RELIGION_LOCKED_BELIEF")));
		if religion.Founder == Game.GetLocalPlayer() then
			beliefInst.BeliefDescription:LocalizeAndSetText("LOC_UI_RELIGION_LOCKED_BELIEF_DESCRIPTION");
		else
			beliefInst.BeliefDescription:SetText("");
		end
		beliefInst.BeliefIcon:SetHide(true);
	end
end

-- ==============================================
function SortCitiesByFollowers(cityReligionA:table, cityReligionB:table, selectedReligion:number)
	local numFollowersA:number, numFollowersB:number = 0, 0;

	local religionsInCity:table = cityReligionA:GetReligionsInCity();
	for _, cityReligionData in ipairs(religionsInCity) do
		if(cityReligionData.Religion == selectedReligion) then
			numFollowersA = cityReligionData.Followers;
			break;
		end
	end

	religionsInCity = cityReligionB:GetReligionsInCity();
	for _, cityReligionData in ipairs(religionsInCity) do
		if(cityReligionData.Religion == selectedReligion) then
			numFollowersB = cityReligionData.Followers;
			break;
		end
	end

	return numFollowersB < numFollowersA;
end

function PopulateSortType()

	for _,sortType in pairs(CITIES_FILTER) do
		local control = {};
		Controls.FilterType:BuildEntry("SmallItemInstance", control);
		control.Button:SetSizeX(Controls.FilterType:GetSizeX());
		control.DescriptionText:SetOffsetX(10);
		if(sortType == CITIES_FILTER.RELIGION_PRESENT) then
			control.DescriptionText:LocalizeAndSetText("LOC_UI_RELIGION_CITY_SORT_TYPE_PRESENT");
		elseif(m_CitiesFilter == CITIES_FILTER.FOLLOWING_RELIGION) then
			control.DescriptionText:LocalizeAndSetText("LOC_UI_RELIGION_CITY_SORT_TYPE_FOLLOWING");
		end
		
		control.Button:RegisterCallback( Mouse.eLClick,  function() OnSortTypeChanged(sortType); end );
        control.Button:RegisterCallback(Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end); 

	end
	Controls.FilterType:CalculateInternals();
end

function RealizeSortTypePulldown()
	local pullDownButton = Controls.FilterType:GetButton();	
	if(m_CitiesFilter == CITIES_FILTER.RELIGION_PRESENT) then
		pullDownButton:SetText("   " .. Locale.Lookup("LOC_UI_RELIGION_CITY_SORT_TYPE_PRESENT"));
	elseif(m_CitiesFilter == CITIES_FILTER.FOLLOWING_RELIGION) then
		pullDownButton:SetText("   " .. Locale.Lookup("LOC_UI_RELIGION_CITY_SORT_TYPE_FOLLOWING"));
	end
end

function OnSortTypeChanged(filterType:number)
	if(filterType ~= m_CitiesFilter) then		
		m_CitiesFilter = filterType;
		ViewReligion(m_SelectedReligion.ID);
	end
end

-- ===========================================================================
--	Called if player selects "View All Religions" tab
-- ===========================================================================
function ViewAllReligions()
	ResetState();

	Controls.ViewAllReligions:SetHide(false);

	local dominantCities:table = {};
	local majorPlayers:table = PlayerManager.GetAlive();
	for _, player in ipairs(majorPlayers) do
		local playerCities:table = player:GetCities();
		for _, city in playerCities:Members() do
			local cityReligion:table= city:GetReligion();
			local majorityReligion:number = cityReligion:GetMajorityReligion()
			if(dominantCities[majorityReligion] == nil) then
				dominantCities[majorityReligion] = 1;
			else
				dominantCities[majorityReligion] = dominantCities[majorityReligion] + 1;
			end
		end
	end

	m_ReligionsIM:ResetInstances();

	local displayPlayerID = GetDisplayPlayerID();
	local localPlayerDiplomacy:table = Players[displayPlayerID]:GetDiplomacy();

	local allReligions:table = m_pGameReligion:GetReligions();
	for _, religionInfo in ipairs(allReligions) do
		local religionData = GameInfo.Religions[religionInfo.Religion];
		if(religionData.Pantheon == false and m_pGameReligion:HasBeenFounded(religionInfo.Religion)) then
			local religionInst:table = m_ReligionsIM:GetInstance();
			local civID:number = PlayerConfigurations[religionInfo.Founder]:GetCivilizationTypeID();

			if religionInfo.Founder == displayPlayerID or localPlayerDiplomacy:HasMet(religionInfo.Founder) or Game.GetLocalObserver() == PlayerTypes.OBSERVER then
				local civName:string = Locale.Lookup(GameInfo.Civilizations[civID].Name);
				religionInst.ReligionFounder:SetText(Locale.ToUpper(Locale.Lookup("LOC_UI_RELIGION_FOUNDER_NAME", civName)));
			else
				religionInst.ReligionFounder:SetText(Locale.ToUpper(Locale.Lookup("LOC_UI_RELIGION_FOUNDER_NAME", Locale.Lookup("LOC_DIPLOPANEL_UNMET_PLAYER"))));
			end
			
			religionInst.ReligionName:SetText(Locale.ToUpper(Game.GetReligion():GetName(religionInfo.Religion)));
			
			SetReligionIcon(religionInst.ReligionImage, religionData.ReligionType, SIZE_RELIGION_ICON_MEDIUM, religionData.Color);

			local numDominantCities:number = dominantCities[religionInfo.Religion];
			if numDominantCities == nil then numDominantCities = 0; end
			if(numDominantCities == 1) then
				religionInst.ReligionDominance:SetText(Locale.ToUpper(Locale.Lookup("LOC_UI_RELIGION_RELIGION_DOMINANCE", numDominantCities)));
			else
				religionInst.ReligionDominance:SetText(Locale.ToUpper(Locale.Lookup("LOC_UI_RELIGION_RELIGION_DOMINANCE_PLURAL", numDominantCities)));
			end

			local beliefsIM:table = religionInst[DATA_FIELD_BELIEFS_IM];
			if(beliefsIM ~= nil) then
				beliefsIM:ResetInstances();
			else
				beliefsIM = InstanceManager:new("ReligionBeliefSmall", "BeliefBG", religionInst.Beliefs);
				religionInst[DATA_FIELD_BELIEFS_IM] = beliefsIM;
			end

			for _, belief in ipairs(religionInfo.Beliefs) do
				local beliefInst:table = beliefsIM:GetInstance();
				local beliefData:table= GameInfo.Beliefs[belief];
				beliefInst.BeliefLabel:SetText(Locale.Lookup("LOC_UI_RELIGION_BELIEF_COMPACT", beliefData.Name, beliefData.Description));
				SetBeliefIcon(beliefInst.BeliefIcon, beliefData.BeliefType, SIZE_BELIEF_ICON_SMALL);
			end

			religionInst.Beliefs:CalculateSize();
			religionInst.Beliefs:ReprocessAnchoring();
			religionInst.ReligionStack:CalculateSize();
			religionInst.ReligionStack:ReprocessAnchoring();
		end
	end

	RealizeStack(Controls.Religions, Controls.ReligionsScrollbar);
end

-- ===========================================================================
--	Update player data and refresh the display state
-- ===========================================================================
function UpdateData()
	UpdatePlayerData();
	UpdateTabs();
	if (m_ReligionTabs ~= nil) then
		m_ReligionTabs.SelectTab(m_MyReligionTab);
	end
	SRA_OnDataUpdated();		-- ScreenReaderAccess
end

-- ===========================================================================
function OnShowScreen()
	Open();
end

-- ===========================================================================
function Open()
	if (Game.GetLocalPlayer() == -1) then
		return
	end

	UpdateData();
	if not UIManager:IsInPopupQueue(ContextPtr) then
		-- Queue the screen as a popup, but we want it to render at a desired location in the hierarchy, not on top of everything.
		local kParameters = {};
		kParameters.RenderAtCurrentParent = true;
		kParameters.InputAtCurrentParent = true;
		kParameters.AlwaysVisibleInQueue = true;
		UIManager:QueuePopup(ContextPtr, PopupPriority.Low, kParameters);
		UI.PlaySound("UI_Screen_Open");
	end

	-- From ModalScreen_PlayerYieldsHelper
	if not RefreshYields() then
		Controls.Vignette:SetSizeY(m_TopPanelConsideredHeight);
	end

	-- From Civ6_styles: FullScreenVignetteConsumer
	Controls.ScreenAnimIn:SetToBeginning();
	Controls.ScreenAnimIn:Play();
	LuaEvents.Religion_OpenReligion();
	SRA_ArmOpen();		-- ScreenReaderAccess
end

-- ===========================================================================
function Close()
	KeyNavEditBox_Cancel();		-- ScreenReaderAccess
	if not ContextPtr:IsHidden() then
		UI.PlaySound("UI_Screen_Close");
	end

	if UIManager:DequeuePopup(ContextPtr) then
		LuaEvents.Religion_CloseReligion();
	end
end

-- ===========================================================================
--	UI Callback
-- ===========================================================================
function OnClose()
	Close();
end

-- ===========================================================================
--	Game Event Callback
-- ===========================================================================
function OnBeliefAdded( ePlayer:number )
	if (ePlayer == Game.GetLocalPlayer()) then
		-- Note: After player selects a belief, m_TurnBlockingType doesn't get cleared immediately.
		--		 Because of this, keep screen hidden during religious updates after confirming beliefs.
		if(not m_isConfirmedBeliefs or m_TurnBlockingType ~= EndTurnBlockingTypes.ENDTURN_BLOCKING_BELIEF) then
			UpdateData();
		end
	end
end

-- ===========================================================================
--	Game Event Callback
-- ===========================================================================
function OnPantheonFounded( ePlayer:number )
	if (ePlayer == Game.GetLocalPlayer()) then
		-- Note: After player selects a belief, m_TurnBlockingType doesn't get cleared immediately.
		--		 Because of this, keep screen hidden during religious updates after confirming beliefs.
		if(not m_isConfirmedBeliefs or m_TurnBlockingType ~= EndTurnBlockingTypes.ENDTURN_BLOCKING_BELIEF) then
			UpdateData();
		end
	end
end

-- ===========================================================================
--	Game Event Callback
-- ===========================================================================
function OnLocalPlayerTurnEnd()
	if(GameConfiguration.IsHotseat()) then
		OnClose();
	end
end

-- ===========================================================================
--	Game Event Callback
-- ===========================================================================
function OnReligionFounded(ePlayer:number)
	if (ePlayer == Game.GetLocalPlayer()) then
		-- Note: After player selects a belief, m_TurnBlockingType doesn't get cleared immediately.
		--		 Because of this, keep screen hidden during religious updates after confirming beliefs.
		if(not m_isConfirmedBeliefs or m_TurnBlockingType ~= EndTurnBlockingTypes.ENDTURN_BLOCKING_BELIEF) then
			UpdateData();
		end
	end
end


-- ===========================================================================
--	UI Event
-- ===========================================================================
function OnInputHandler( pInputStruct:table )
	if SRA_HandleInput( pInputStruct ) then return true; end		-- ScreenReaderAccess
	local uiMsg = pInputStruct:GetMessageType();
	if (uiMsg == KeyEvents.KeyUp and pInputStruct:GetKey() == Keys.VK_ESCAPE) then
		Close();
		return true;
	end
	return false;
end

-- ===========================================================================
--	UI EVENT
-- ===========================================================================
function OnInit(isReload:boolean)
	if isReload then
		LuaEvents.GameDebug_GetValues( "ReligionScreen" );		
	end
	PopulateSortType();
end

-- ===========================================================================
--	UI EVENT
-- ===========================================================================
function OnShutdown()
	KeyNavEditBox_Cancel();		-- ScreenReaderAccess
	-- Cache values for hotloading...
	LuaEvents.GameDebug_AddValue("ReligionScreen", "isHidden", ContextPtr:IsHidden());

	Events.BeliefAdded.Remove(OnBeliefAdded);
	Events.PantheonFounded.Remove(OnPantheonFounded);
	Events.ReligionFounded.Remove(OnReligionFounded);
	Events.LocalPlayerTurnEnd.Remove( OnLocalPlayerTurnEnd );
	
	LuaEvents.GameDebug_Return.Remove(OnGameDebugReturn);	
	LuaEvents.LaunchBar_OpenReligionPanel.Remove(OnShowScreen);
	LuaEvents.LaunchBar_CloseReligionPanel.Remove(OnClose);
	LuaEvents.NotificationPanel_OpenReligionPanel.Remove(OnShowScreen);
	LuaEvents.PantheonChooser_OpenReligionPanel.Remove(OnShowScreen);
end

-- ===========================================================================
--	LUA Event
--	Set cached values back after a hotload.
-- ===========================================================================
function OnGameDebugReturn( context:string, contextTable:table )
	if context == "ReligionScreen" and contextTable["isHidden"] ~= nil and not contextTable["isHidden"] then
		ContextPtr:SetHide( false );
		UpdateData();
	end	
end

-- ===========================================================================
-- Begin ScreenReaderAccess change: keyboard navigation and speech for the religion screen.
--
-- One keyboard list for whatever the screen currently shows. The mode is read from which panel of the screen is visible
-- (SRA_Mode), the items are rebuilt from the screen's own state on every key, and every action calls the screen's own
-- function or button callback (OnBeliefSelected, SelectReligionBeliefs, the confirm button callback, ...):
--   working   no pantheon / no prophet yet: where you stand and the next step
--   religion  founding: choose the religion (Enter selects, Enter again continues; custom religions ask for a name)
--   beliefs   choose pantheon / religion beliefs (sections per belief class), or add a belief to an existing religion
--   confirm   confirm / go back (the confirm button's own callback)
--   view      one religion: its beliefs, pantheon, cities (F switches "follow it" / "present")
--   all       every founded religion, then your cities
-- Tab = next tab of the screen, C = continue / confirm, F = city filter, Escape or L = close. All keys are consumed while shown.
-- ===========================================================================
local function SRA_Say( text:string, nointerrupt:boolean )
	OutputMessageToScreenReader( text, nointerrupt );
end

local function SRA_Clean( text )
	if text == nil then return ""; end
	return CleanTextForSpeech( text );
end

local function SRA_BeliefName( row:table )
	return SRA_Clean( Locale.Lookup( row.Name ) );
end

local function SRA_BeliefText( row:table )
	return SRA_BeliefName( row ) .. ": " .. SRA_Clean( Locale.Lookup( row.Description ) );
end

-- "Follower belief"
local function SRA_BeliefClass( row:table )
	local class:table = GameInfo.BeliefClasses[ row.BeliefClassType ];
	if class == nil then return ""; end
	local name:string = SRA_Clean( Locale.Lookup( class.Name ) );
	if string.find( string.lower( name ), "belief", 1, true ) == nil then name = name .. " belief"; end
	return name;
end

local function SRA_ReligionName( religionType:number )
	return SRA_Clean( Locale.Lookup( m_pGameReligion:GetName( religionType ) ) );
end

local function SRA_CivName( playerID:number )
	local civID:number = PlayerConfigurations[ playerID ]:GetCivilizationTypeID();
	return SRA_Clean( Locale.Lookup( GameInfo.Civilizations[ civID ].Name ) );
end

local function SRA_FindReligion( religionType )
	if religionType == nil then return nil; end
	for _, tmp in ipairs( m_pGameReligion:GetReligions() ) do
		if tmp.Religion == religionType then return tmp; end
	end
	return nil;
end

local function SRA_IsCustom( row:table )
	return row.RequiresCustomName and GameCapabilities.HasCapability( "CAPABILITY_RENAME" );
end

local function SRA_Selected()
	return m_SelectedBeliefs or {};
end

local function SRA_Met( playerID:number )
	local localID:number = GetDisplayPlayerID();
	if playerID == localID or Game.GetLocalObserver() == PlayerTypes.OBSERVER then return true; end
	return Players[ localID ]:GetDiplomacy():HasMet( playerID );
end

local function SRA_FounderText( religion:table )
	if religion.Founder == GetDisplayPlayerID() then return ReligionText_Founder( true, "" ); end
	if SRA_Met( religion.Founder ) then return ReligionText_Founder( false, SRA_CivName( religion.Founder ) ); end
	return ReligionText_Founder( false, SRA_Clean( Locale.Lookup( "LOC_DIPLOPANEL_UNMET_PLAYER" ) ) );
end

local function SRA_HolyCity( religion:table )
	if not SRA_Met( religion.Founder ) then return nil; end
	local holyCity:table = CityManager.GetCity( Players[ religion.Founder ]:GetReligion():GetHolyCityID() );
	if holyCity == nil then return nil; end
	return SRA_Clean( Locale.Lookup( holyCity:GetName() ) );
end

local function SRA_RealMajority( city:table )
	local majority:number = city:GetReligion():GetMajorityReligion();
	if majority == nil or majority < 0 then return nil; end
	local row:table = GameInfo.Religions[ majority ];
	if row == nil or row.Pantheon then return nil; end
	return majority;
end

-- followers per founded religion in a city, for ReligionText_Followers
local function SRA_CityEntries( city:table )
	local entries:table = {};
	for _, data in ipairs( city:GetReligion():GetReligionsInCity() ) do
		local row:table = GameInfo.Religions[ data.Religion ];
		if row ~= nil and row.Pantheon == false and data.Followers ~= nil and data.Followers > 0 then
			table.insert( entries, { name = SRA_ReligionName( data.Religion ), followers = data.Followers } );
		end
	end
	return entries;
end

local function SRA_CityLine( city:table )
	local majority:number = SRA_RealMajority( city );
	local majorityName = nil;
	if majority ~= nil then majorityName = SRA_ReligionName( majority ); end
	return ReligionText_CityLine( SRA_CityLabel( city ), majorityName, SRA_CityEntries( city ) );
end

local function SRA_MajorityCounts()
	local counts:table = {};
	for _, player in ipairs( PlayerManager.GetAlive() ) do
		for _, city in player:GetCities():Members() do
			local majority:number = SRA_RealMajority( city );
			if majority ~= nil then counts[ majority ] = ( counts[ majority ] or 0 ) + 1; end
		end
	end
	return counts;
end

local function SRA_BeliefNames( indexes:table )
	local names:table = {};
	for _, index in ipairs( indexes ) do
		table.insert( names, SRA_BeliefName( GameInfo.Beliefs[ index ] ) );
	end
	return names;
end

local function SRA_BeliefTexts( indexes:table )
	local texts:table = {};
	for _, index in ipairs( indexes ) do
		local row:table = GameInfo.Beliefs[ index ];
		table.insert( texts, SRA_BeliefText( row ) .. " (" .. SRA_BeliefClass( row ) .. ")" );
	end
	return table.concat( texts, ". " );
end

-- Name of the religion being founded / the player's own, "your religion" while a custom name is still empty.
local function SRA_SelectedReligionName()
	if m_PlayerReligionType >= 0 then return SRA_ReligionName( m_PlayerReligionType ); end
	if m_SelectedReligion == nil then return "your religion"; end
	local row:table = GameInfo.Religions[ m_SelectedReligion.ID ];
	if row == nil then return "your religion"; end
	if SRA_IsCustom( row ) then
		local typed:string = Controls.ChooseReligionName:GetText();
		if typed == nil or typed == "" then return "your religion"; end
		return SRA_Clean( typed );
	end
	return SRA_Clean( Locale.Lookup( row.Name ) );
end

-- Which panel of the screen is showing.
function SRA_Mode()
	if ContextPtr:IsHidden() then return nil; end
	if not Controls.WorkingTowards:IsHidden() then return "working"; end
	if not Controls.ViewAllReligions:IsHidden() then return "all"; end
	if not Controls.ViewReligion:IsHidden() then return "view"; end
	if not Controls.ChooseReligion:IsHidden() then return "religion"; end
	if not Controls.SelectBeliefs:IsHidden() then
		if not Controls.ConfirmBeliefs:IsHidden() then return "confirm"; end
		if not Controls.ChooseBelief:IsHidden() then return "beliefs"; end
	end
	if not Controls.AddBeliefs:IsHidden() then
		if not Controls.AddConfirmBeliefs:IsHidden() then return "confirm"; end
		if not Controls.AddBelief:IsHidden() then return "beliefs"; end
	end
	return nil;
end

function SRA_CityLabel( city:table )
	local owner:number = city:GetOwner();
	if not SRA_Met( owner ) then return "Unknown city"; end
	local name:string = SRA_Clean( Locale.Lookup( city:GetName() ) );
	if owner ~= GetDisplayPlayerID() then name = name .. ", " .. SRA_CivName( owner ); end
	return name;
end

-- ---------------------------------------------------------------------------
-- Items per mode
-- ---------------------------------------------------------------------------
local function SRA_ItemsWorking()
	local items:table = {};
	if m_PantheonBelief >= 0 then
		table.insert( items, { key = "pantheon", text = "Pantheon: " .. SRA_BeliefText( GameInfo.Beliefs[ m_PantheonBelief ] ) } );
	end
	local step:string;
	if m_PantheonBelief < 0 then
		step = Locale.Lookup( "LOC_RELIGIONPANEL_NEXT_STEP_FOUND_PANTHEON", m_pGameReligion:GetMinimumFaithNextPantheon() );
	elseif not m_isHasProphet then
		step = Locale.Lookup( "LOC_RELIGIONPANEL_NEXT_STEP_EARN_PROPHET" );
	else
		step = Locale.Lookup( "LOC_RELIGIONPANEL_NEXT_STEP_USE_PROPHET" );
	end
	table.insert( items, { key = "next", text = "Next step: " .. SRA_Clean( step ) } );
	return items;
end

local function SRA_ItemsReligion()
	local items:table = {};
	local selectedCustom:table = nil;
	for row in GameInfo.Religions() do
		if row.Pantheon == false and not m_pGameReligion:HasBeenFounded( row.Index ) then
			local selected:boolean = m_SelectedReligion ~= nil and m_SelectedReligion.Instance ~= nil and m_SelectedReligion.ID == row.Index;
			local text:string;
			if SRA_IsCustom( row ) then
				local number:string = string.match( row.ReligionType, "(%d+)$" ) or "";
				text = "Custom religion " .. number .. ", you choose the name";
				if selected then selectedCustom = row; end
			else
				text = SRA_Clean( Locale.Lookup( row.Name ) );
			end
			if selected then
				if Controls.ConfirmReligion:IsDisabled() then text = text .. ", selected, needs a name"; else text = text .. ", selected, Enter to continue"; end
			end
			table.insert( items, { key = "religion:" .. row.Index, text = text, religion = row, selected = selected } );
		end
	end
	if selectedCustom ~= nil then
		local typed:string = Controls.ChooseReligionName:GetText();
		if typed == nil or typed == "" then typed = "blank"; end
		table.insert( items, { key = "name", text = "Religion name: " .. SRA_Clean( typed ) .. ", Enter to edit" } );
	end
	return items;
end

local function SRA_ItemsBeliefs()
	local items:table = {};
	local pantheon:boolean = ( m_PantheonBelief < 0 );
	for _, index in ipairs( m_srBeliefOrder ) do
		local row:table = GameInfo.Beliefs[ index ];
		if m_srBeliefInst[ index ] ~= nil and not m_pGameReligion:IsInSomeReligion( index ) and not m_pGameReligion:IsInSomePantheon( index ) then
			local section = nil;
			if not pantheon then section = SRA_BeliefClass( row ); end
			table.insert( items, {
				key = "belief:" .. index, text = SRA_BeliefText( row ), section = section, belief = row,
				detail = SRA_BeliefText( row ) .. ". " .. SRA_BeliefClass( row ) .. ". Enter to choose",
			} );
		end
	end
	if #SRA_Selected() > 0 then
		table.insert( items, { key = "undo", text = "Undo: remove " .. ReligionText_Join( SRA_BeliefNames( SRA_Selected() ) ) .. " and start over", section = "Chosen" } );
	end
	return items;
end

-- the three buttons of the confirm panel (the Add* set when beliefs are added to an existing religion)
local function SRA_ConfirmButtons()
	if not Controls.ConfirmBeliefs:IsHidden() then
		return { confirm = Controls.ConfirmBeliefs, reselect = Controls.ReselectBeliefs, reselectReligion = Controls.ReselectReligion };
	end
	return { confirm = Controls.AddConfirmBeliefs, reselect = Controls.AddReselectBeliefs, reselectReligion = Controls.AddReselectReligion };
end

local function SRA_ConfirmSummary()
	local names:table = SRA_BeliefNames( SRA_Selected() );
	if m_PantheonBelief < 0 then return "Pantheon: " .. ReligionText_Join( names ); end
	if m_PlayerReligionType < 0 then return "Found " .. SRA_SelectedReligionName() .. " with " .. ReligionText_Join( names ); end
	return "Add " .. ReligionText_Join( names ) .. " to " .. SRA_ReligionName( m_PlayerReligionType );
end

local function SRA_ItemsConfirm()
	local items:table = {};
	local buttons:table = SRA_ConfirmButtons();
	table.insert( items, {
		key = "confirm", text = SRA_Clean( buttons.confirm:GetText() ),
		detail = SRA_ConfirmSummary() .. ". " .. SRA_BeliefTexts( SRA_Selected() ) .. ". Enter or C to confirm",
	} );
	table.insert( items, { key = "reselect", text = SRA_Clean( buttons.reselect:GetText() ) } );
	if not buttons.reselectReligion:IsHidden() then
		table.insert( items, { key = "reselectReligion", text = SRA_Clean( buttons.reselectReligion:GetText() ) } );
	end
	return items;
end

local function SRA_ItemsView()
	local items:table = {};
	local religionType = nil;
	if m_SelectedReligion ~= nil then religionType = m_SelectedReligion.ID; end
	local religion:table = SRA_FindReligion( religionType );
	if religion == nil then return items; end
	local localID:number = GetDisplayPlayerID();

	for _, index in ipairs( religion.Beliefs ) do
		local row:table = GameInfo.Beliefs[ index ];
		table.insert( items, { key = "belief:" .. index, section = "Beliefs", text = SRA_BeliefText( row ) .. ", " .. string.lower( SRA_BeliefClass( row ) ) } );
	end
	local locked:number = NUM_MAX_BELIEFS - #religion.Beliefs;
	if locked > 0 then
		local text:string = ReligionText_Count( locked, "belief slot", "belief slots" ) .. " still locked";
		if religion.Founder == localID then text = text .. ", more come with Great Prophets and later techs and civics"; end
		table.insert( items, { key = "locked", section = "Beliefs", text = text } );
	end

	if SRA_Met( religion.Founder ) then
		local pantheon:number = Players[ religion.Founder ]:GetReligion():GetPantheon();
		if pantheon ~= nil and pantheon >= 0 then
			table.insert( items, { key = "pantheon", section = "Pantheon", text = "Founder's pantheon, " .. SRA_BeliefText( GameInfo.Beliefs[ pantheon ] ) } );
		end
	end

	-- cities (same selection as the screen's list: majority religion, or any follower)
	local cities:table = {};
	for _, player in ipairs( PlayerManager.GetAlive() ) do
		for _, city in player:GetCities():Members() do
			local include:boolean = false;
			if m_CitiesFilter == CITIES_FILTER.FOLLOWING_RELIGION then
				include = ( SRA_RealMajority( city ) == religionType );
			else
				for _, data in ipairs( city:GetReligion():GetReligionsInCity() ) do
					if data.Religion == religionType and data.Followers ~= nil and data.Followers > 0 then include = true; end
				end
			end
			if include then table.insert( cities, city ); end
		end
	end
	table.sort( cities, function( a, b ) return SortCitiesByFollowers( a:GetReligion(), b:GetReligion(), religionType ); end );
	local name:string = SRA_ReligionName( religionType );
	if m_CitiesFilter == CITIES_FILTER.FOLLOWING_RELIGION then
		table.insert( items, { key = "filter", section = "Cities", text = ReligionText_Count( #cities, "city follows", "cities follow" ) .. " " .. name .. ". Enter shows cities where it is only present" } );
	else
		table.insert( items, { key = "filter", section = "Cities", text = name .. " is present in " .. ReligionText_Count( #cities, "city", "cities" ) .. ". Enter shows only cities that follow it" } );
	end
	for _, city in ipairs( cities ) do
		local pantheonHere:number = city:GetReligion():GetActivePantheon();
		local detail:string = SRA_CityLine( city );
		if pantheonHere ~= nil and pantheonHere >= 0 and SRA_Met( city:GetOwner() ) then
			detail = detail .. ". Pantheon there: " .. SRA_BeliefText( GameInfo.Beliefs[ pantheonHere ] );
		end
		table.insert( items, { key = "city:" .. city:GetOwner() .. ":" .. city:GetID(), section = "Cities", text = SRA_CityLine( city ), detail = detail } );
	end
	return items;
end

local function SRA_ItemsAll()
	local items:table = {};
	local counts:table = SRA_MajorityCounts();
	local localID:number = GetDisplayPlayerID();
	for _, religion in ipairs( m_pGameReligion:GetReligions() ) do
		local data:table = GameInfo.Religions[ religion.Religion ];
		if data ~= nil and data.Pantheon == false and m_pGameReligion:HasBeenFounded( religion.Religion ) then
			local text:string = SRA_ReligionName( religion.Religion ) .. ", " .. SRA_FounderText( religion ) .. ", majority in " .. ReligionText_Count( counts[ religion.Religion ] or 0, "city", "cities" );
			text = text .. ", " .. ReligionText_Beliefs( SRA_BeliefNames( religion.Beliefs ) );
			local detail:string = SRA_ReligionName( religion.Religion ) .. ", " .. SRA_FounderText( religion );
			local holy = SRA_HolyCity( religion );
			if holy ~= nil then detail = detail .. ", holy city " .. holy; end
			detail = detail .. ". Majority in " .. ReligionText_Count( counts[ religion.Religion ] or 0, "city", "cities" ) .. ". " .. SRA_BeliefTexts( religion.Beliefs );
			table.insert( items, { key = "religion:" .. religion.Religion, section = "Religions", text = text, detail = detail } );
		end
	end
	local player:table = Players[ localID ];
	if player ~= nil then
		for _, city in player:GetCities():Members() do
			table.insert( items, { key = "mycity:" .. city:GetID(), section = "Your cities", text = SRA_CityLine( city ) } );
		end
	end
	return items;
end

function SRA_Items()
	local mode = SRA_Mode();
	if mode == "working" then return SRA_ItemsWorking(); end
	if mode == "religion" then return SRA_ItemsReligion(); end
	if mode == "beliefs" then return SRA_ItemsBeliefs(); end
	if mode == "confirm" then return SRA_ItemsConfirm(); end
	if mode == "view" then return SRA_ItemsView(); end
	if mode == "all" then return SRA_ItemsAll(); end
	return {};
end

-- ---------------------------------------------------------------------------
-- Opening sentence per mode
-- ---------------------------------------------------------------------------
local function SRA_Faith()
	return math.floor( Players[ GetDisplayPlayerID() ]:GetReligion():GetFaithBalance() );
end

local function SRA_Head( mode:string )
	if mode == "working" then
		local head:string = "Religion. No religion founded. You have " .. SRA_Faith() .. " faith";
		if m_PantheonBelief < 0 then head = head .. ", no pantheon yet"; end
		return head;
	elseif mode == "religion" then
		local available:number = 0;
		for row in GameInfo.Religions() do
			if row.Pantheon == false and not m_pGameReligion:HasBeenFounded( row.Index ) then available = available + 1; end
		end
		return "Found a religion: choose a religion, " .. available .. " available";
	elseif mode == "beliefs" then
		local remaining:number = math.max( 0, m_NumBeliefsEarned - m_NumBeliefsEquipped - #SRA_Selected() );
		local head:string;
		if m_PantheonBelief < 0 then
			head = "Choose a pantheon, " .. SRA_Faith() .. " faith";
		elseif m_NumBeliefsEquipped == 0 then
			head = "Choose beliefs for " .. SRA_SelectedReligionName() .. ": " .. ReligionText_ToChoose( remaining );
		else
			head = "Add a belief to " .. SRA_ReligionName( m_PlayerReligionType ) .. ": " .. ReligionText_ToChoose( remaining );
		end
		if #SRA_Selected() > 0 then head = head .. ". Chosen: " .. ReligionText_Join( SRA_BeliefNames( SRA_Selected() ) ); end
		return head;
	elseif mode == "confirm" then
		return "Confirm. " .. SRA_ConfirmSummary();
	elseif mode == "view" then
		local religionType = nil;
		if m_SelectedReligion ~= nil then religionType = m_SelectedReligion.ID; end
		local religion:table = SRA_FindReligion( religionType );
		if religion == nil then return "Religion"; end
		local head:string = "Religion: " .. SRA_ReligionName( religionType ) .. ", " .. SRA_FounderText( religion );
		local holy = SRA_HolyCity( religion );
		if holy ~= nil then head = head .. ", holy city " .. holy; end
		local following:number = SRA_MajorityCounts()[ religionType ] or 0;
		return head .. ". Majority religion in " .. ReligionText_Count( following, "city", "cities" );
	elseif mode == "all" then
		local founded:number = 0;
		for _, religion in ipairs( m_pGameReligion:GetReligions() ) do
			local data:table = GameInfo.Religions[ religion.Religion ];
			if data ~= nil and data.Pantheon == false and m_pGameReligion:HasBeenFounded( religion.Religion ) then founded = founded + 1; end
		end
		return "Religions of the world: " .. founded .. " founded";
	end
	return "Religion";
end

-- ---------------------------------------------------------------------------
-- Announcing
-- ---------------------------------------------------------------------------
-- Speaks the opening sentence of the current mode and the first item; focus restarts at the top.
function SRA_Announce( nointerrupt:boolean )
	local mode = SRA_Mode();
	if mode == nil then return; end
	m_srList.Reset();
	local items:table = SRA_Items();
	local head:string = SRA_Head( mode );
	if #items == 0 then
		SRA_Say( head .. ". Nothing to show", nointerrupt );
		return;
	end
	m_srList.Open( head, nil, true );
	local first:table = items[1];
	local text:string = first.text;
	if first.section ~= nil then text = first.section .. ": " .. text; end
	SRA_Say( head .. ". " .. text .. ", 1 of " .. #items, nointerrupt );
end

-- Called when the screen opens: the announcement waits until the data and the popup have settled.
function SRA_ArmOpen()
	m_srOpenPending = true;
	m_srOpenDelay = 0.35;
end

-- Called at the end of UpdateData (screen opened, or the game changed religion data while it is open).
function SRA_OnDataUpdated()
	-- Nothing: the opening announcement is armed only by Open(); mode changes are announced explicitly
	-- (re-arming here doubled the speech and reset the focus on every BeliefAdded / ReligionFounded update).
end

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------
local function SRA_ReadItem( item:table )
	local detail = item.detail;
	if type( detail ) == "function" then detail = detail(); end
	if detail == nil or detail == "" then detail = item.text; end
	SRA_Say( detail );
end

-- Name of a custom religion: the edit box keeps the focus until Enter / Escape (KeyNavEditBox); the game's own validation is
-- put back afterwards so the Continue button enables.
local function SRA_EditName()
	KeyNavEditBox_Begin( Controls.ChooseReligionName, {
		label = "Religion name",
		onEnd = function( committed:boolean )
			if m_srNameChanged ~= nil then
				Controls.ChooseReligionName:RegisterStringChangedCallback( m_srNameChanged );
				m_srNameChanged( Controls.ChooseReligionName );
			end
		end,
	} );
end

local function SRA_Continue()
	if Controls.ConfirmReligion:IsDisabled() then
		if m_SelectedReligion == nil or m_SelectedReligion.Instance == nil then
			SRA_Say( "Choose a religion first" );
		else
			SRA_Say( "Give the religion a name first, Enter on the name to edit" );
		end
		return;
	end
	SelectReligionBeliefs();
	SRA_Announce( false );
end

local function SRA_ActivateReligion( item:table )
	if item.key == "name" then SRA_EditName(); return; end
	local row:table = item.religion;
	if row == nil then return; end
	if item.selected then SRA_Continue(); return; end
	local selectFn = m_srReligionSelect[ row.Index ];
	if selectFn == nil then SRA_Say( "That religion is no longer available" ); return; end
	selectFn();
	if SRA_IsCustom( row ) then
		SRA_EditName();
	else
		SRA_Say( SRA_Clean( Locale.Lookup( row.Name ) ) .. " selected. Enter to continue, or choose another" );
	end
end

local function SRA_ActivateBelief( item:table )
	if item.key == "undo" then
		m_SelectedBeliefs = {};
		if m_PendingBeliefs ~= nil then
			m_PendingBeliefs.IM:ResetInstances();
			RealizeStack( m_PendingBeliefs.Stack, m_PendingBeliefs.Scrollbar );
		end
		if m_PantheonBelief < 0 then SelectPantheonBeliefs(); else SelectReligionBeliefs(); end
		SRA_Say( "Choices removed" );
		SRA_Announce( true );
		return;
	end
	local row:table = item.belief;
	local inst:table = nil;
	if row ~= nil then inst = m_srBeliefInst[ row.Index ]; end
	if row == nil or inst == nil then SRA_Say( "That belief is no longer available" ); return; end
	OnBeliefSelected( row.Index, inst );
	SRA_Say( "Chose " .. SRA_BeliefName( row ) );
	SRA_Announce( true );
end

-- What the engine says after a confirm: spoken from the game's data once it had a moment to answer.
local function SRA_ConfirmResult()
	local player:table = Players[ GetDisplayPlayerID() ];
	if player == nil then return; end
	local religionType:number = player:GetReligion():GetReligionTypeCreated();
	local religion:table = SRA_FindReligion( religionType );
	if religionType ~= nil and religionType >= 0 and religion ~= nil then
		SRA_Say( SRA_ReligionName( religionType ) .. " has " .. ReligionText_Beliefs( SRA_BeliefNames( religion.Beliefs ) ), true );
	elseif player:GetReligion():GetPantheon() >= 0 then
		SRA_Say( "Pantheon: " .. SRA_BeliefName( GameInfo.Beliefs[ player:GetReligion():GetPantheon() ] ), true );
	end
	-- the screen skips its own refresh while it thinks beliefs are still being chosen: refresh it so it shows the result
	if SRA_Mode() == "confirm" and m_isConfirmedBeliefs then
		UpdateData();
		SRA_Announce( true );
	end
end

local function SRA_ActivateConfirm( item:table )
	local buttons:table = SRA_ConfirmButtons();
	if item.key == "confirm" then
		if m_isConfirmedBeliefs then SRA_Say( "Already confirmed, please wait" ); return; end
		if m_srConfirm == nil then SRA_Say( "Can't confirm here" ); return; end
		local summary:string = SRA_ConfirmSummary();
		m_srConfirm();
		SRA_Say( summary .. ", confirmed" );
		m_srResult = { wait = 1.0 };
	elseif item.key == "reselect" then
		if m_PantheonBelief < 0 then
			SelectPantheonBeliefs();
		elseif m_srReselectBeliefs ~= nil then
			m_srReselectBeliefs();
		else
			return;
		end
		SRA_Announce( false );
	elseif item.key == "reselectReligion" then
		ChooseReligion();
		SRA_Announce( false );
	end
end

local function SRA_ToggleFilter()
	if SRA_Mode() ~= "view" then return; end
	if m_CitiesFilter == CITIES_FILTER.FOLLOWING_RELIGION then
		OnSortTypeChanged( CITIES_FILTER.RELIGION_PRESENT );
	else
		OnSortTypeChanged( CITIES_FILTER.FOLLOWING_RELIGION );
	end
	m_srList.Focus( "filter" );
end

local function SRA_OnActivate( item:table )
	local mode = SRA_Mode();
	if mode == "religion" then SRA_ActivateReligion( item );
	elseif mode == "beliefs" then SRA_ActivateBelief( item );
	elseif mode == "confirm" then SRA_ActivateConfirm( item );
	elseif mode == "view" and item.key == "filter" then SRA_ToggleFilter();
	else SRA_ReadItem( item );
	end
end

local function SRA_KeyContinue()
	local mode = SRA_Mode();
	if mode == "religion" then
		SRA_Continue();
	elseif mode == "confirm" then
		SRA_ActivateConfirm( { key = "confirm" } );
	end
end

local function SRA_KeyFilter()
	SRA_ToggleFilter();
end

local function SRA_TabLabel( control:table )
	if control == m_MyReligionTab or control == m_AllReligionsTab or control[ DATA_FIELD_INDEX ] == nil then
		return SRA_Clean( control:GetText() );
	end
	return SRA_ReligionName( control[ DATA_FIELD_INDEX ] );
end

local function SRA_NextTab()
	if m_ReligionTabs == nil or #m_ReligionTabs.tabControls < 2 then
		SRA_Say( "No other tabs" );
		return;
	end
	local tabs:table = m_ReligionTabs.tabControls;
	local current:number = 0;
	for i, control in ipairs( tabs ) do
		if control == m_ReligionTabs.selectedControl then current = i; end
	end
	local target:number = current % #tabs + 1;
	SRA_Say( "Tab " .. SRA_TabLabel( tabs[ target ] ) .. ", " .. target .. " of " .. #tabs );
	m_ReligionTabs.SelectTab( tabs[ target ] );
	SRA_Announce( true );
end

local function SRA_OnClose()
	Close();
	SRA_Say( "Religion closed" );
end

function SRA_OnUpdate( deltaTime:number )
	KeyNavEditBox_Update( deltaTime );
	if m_srResult ~= nil then
		m_srResult.wait = m_srResult.wait - deltaTime;
		if m_srResult.wait <= 0 then
			m_srResult = nil;
			local ok:boolean, err = xpcall( SRA_ConfirmResult, KeyNavErrorHandler );
			if not ok then print( "ReligionScreen result error: " .. tostring( err ) ); end
		end
	end
	if m_srOpenPending and not ContextPtr:IsHidden() then
		m_srOpenDelay = m_srOpenDelay - deltaTime;
		if m_srOpenDelay > 0 then return; end
		m_srOpenPending = false;
		local ok:boolean, err = xpcall( function() SRA_Announce( true ); end, KeyNavErrorHandler );
		if not ok then print( "ReligionScreen announce error: " .. tostring( err ) ); end
	end
end

-- Returns true: every keyboard event is consumed while the screen is shown.
function SRA_HandleInput( pInputStruct:table )
	if ContextPtr:IsHidden() then return false; end
	local handled = KeyNavEditBox_HandleInput( pInputStruct );
	if handled ~= nil then return handled; end
	if m_srList ~= nil and m_srList.HandleInput( pInputStruct ) then return true; end
	local msg:number = pInputStruct:GetMessageType();
	return msg == KeyEvents.KeyDown or msg == KeyEvents.KeyUp;
end

m_srList = KeyNavList_Create{
	build = SRA_Items,
	isActive = function() return not ContextPtr:IsHidden() and not KeyNavEditBox_IsEditing(); end,
	onActivate = SRA_OnActivate,
	onClose = SRA_OnClose,
	extraKeys = {
		[ Keys.VK_TAB ] = SRA_NextTab,
		[ Keys.C ] = SRA_KeyContinue,
		[ Gamepad.Key( "X" ) ] = SRA_KeyContinue,
		[ Keys.F ] = SRA_KeyFilter,
		[ Gamepad.Key( "LT" ) ] = SRA_KeyFilter,
	},
};
-- End ScreenReaderAccess change

-- ===========================================================================
--	Main INIT
-- ===========================================================================
function Initialize()
	
	if (not HasCapability("CAPABILITY_RELIGION_VIEW")) then
		-- Religion is off, just exit
		return;
	end

	--[[ DEBUG
	WorkingTowardsPantheon();
	WorkingTowardsReligion();
	--SelectPantheonBeliefs();
	--SelectReligionBeliefs();
	--ChooseReligion();
	--ViewAllReligions();
	--]]

	ContextPtr:SetInitHandler(OnInit);
	ContextPtr:SetInputHandler(OnInputHandler, true);
	ContextPtr:SetShutdown( OnShutdown );
	ContextPtr:SetUpdate( SRA_OnUpdate );		-- ScreenReaderAccess

	Events.BeliefAdded.Add(OnBeliefAdded);
	Events.PantheonFounded.Add(OnPantheonFounded);
	Events.ReligionFounded.Add(OnReligionFounded);
	Events.LocalPlayerTurnEnd.Add( OnLocalPlayerTurnEnd );
	
	LuaEvents.GameDebug_Return.Add(OnGameDebugReturn);	
	LuaEvents.LaunchBar_OpenReligionPanel.Add(OnShowScreen);
	LuaEvents.LaunchBar_CloseReligionPanel.Add(OnClose);
	LuaEvents.NotificationPanel_OpenReligionPanel.Add(OnShowScreen);
	LuaEvents.PantheonChooser_OpenReligionPanel.Add(OnShowScreen);

	Controls.ModalScreenTitle:SetText(Locale.ToUpper(TXT_SCREEN_TITLE));
	Controls.ModalScreenClose:RegisterCallback(Mouse.eLClick, OnClose);
    Controls.ModalScreenClose:RegisterCallback(Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end); 
	m_TopPanelConsideredHeight = Controls.Vignette:GetSizeY() - TOP_PANEL_OFFSET;

end
Initialize();

