
include("InstanceManager");
include("PlayerSetupLogic");
include("Civ6Common");
include("KeyboardNavigation");
include("ScreenReader");

-- ===========================================================================
-- CONSTANTS
-- ===========================================================================

local XP2_RULESETUP:string = "RULESET_EXPANSION_2";
local XP1_RULESETUP:string = "RULESET_EXPANSION_1";

-- ===========================================================================
-- Members
-- ===========================================================================

local m_pItemIM:table = InstanceManager:new("ItemInstance",	"Button", Controls.ItemsPanel);

local m_kParameter:table = nil		-- Reference to the parameter being used. 
local m_kSelectedValues:table = nil	-- Table of string->boolean that represents checked off items.
local m_keyNavItemIndex	:number = 1;	-- declared early: RefreshList keeps it on the same city-state
local m_currentSortFunc;				-- the sort actually applied to the list (mouse or keyboard)
local m_kItemList:table = nil;		-- Table of controls for select all/none

local m_bInvertSelection:boolean = false;

local m_kCityStateDataCache:table = {};

local m_kCityStateCountParam:table = nil;
local m_kGameParameters:table = nil;		-- Setup parameters (for the keyboard city-state count)

local m_RulesetType:string = "";

local m_numSelected:number = 0;

-- Track the number of city-states to spawn when opening the picker
-- Used to revert to that number in case the user modifies the parameter then backs out of the picker
local m_OriginalCityStateCount:number = 0;

-- ===========================================================================
function Close()	
	-- Clear any temporary global variables.
	m_kParameter = nil;
	m_kSelectedValues = nil;

	ContextPtr:SetHide(true);
end

-- ===========================================================================
function IsItemSelected(item: table) 
	return m_kSelectedValues[item.Value] == true;
end

-- ===========================================================================
function OnBackButton()
	Close();
	LuaEvents.CityStatePicker_SetParameterValue(m_kCityStateCountParam.ParameterId, m_OriginalCityStateCount);
end

-- ===========================================================================
function OnConfirmChanges()
	-- Generate sorted list from selected values.
	local values = {}
	for k,v in pairs(m_kSelectedValues) do
		if(v) then
			table.insert(values, k);
		end
	end

	LuaEvents.CityStatePicker_SetParameterValues(m_kParameter.ParameterId, values);
	Close();
end

-- ===========================================================================
function OnItemSelect(item :table, checkBox :table)
	local value = item.Value;
	local selected:boolean = not m_kSelectedValues[value];

	m_kSelectedValues[item.Value] = selected;
	if m_bInvertSelection then
		checkBox:SetCheck(not selected);
	else
		checkBox:SetCheck(selected);
	end

	RefreshCountWarning();
end

-- ===========================================================================
function OnItemFocus(item :table)
	if(item) then
		Controls.FocusedItemName:SetText(item.Name);

		local backColor:number, frontColor:number = UI.GetPlayerColorValues(item.Value, 0);
		local kCityStateData:table = GetCityStateData(item.Value);

		local description:string = Locale.ToUpper("LOC_CITY_STATES_SUZERAIN_BONUSES");

        if kCityStateData ~= nil then
            if kCityStateData.Bonus_XP2 ~= nil and m_RulesetType == XP2_RULESETUP and IsExpansion2Enabled() then
                description = description .. "[NEWLINE]" .. Locale.Lookup(kCityStateData.Bonus_XP2);
            elseif kCityStateData.Bonus_XP1 ~= nil and (m_RulesetType == XP1_RULESETUP or m_RulesetType == XP2_RULESETUP) and IsExpansion1Enabled() then
                description = description .. "[NEWLINE]" .. Locale.Lookup(kCityStateData.Bonus_XP1);
            elseif kCityStateData ~= nil then
                description = description .. "[NEWLINE]" .. Locale.Lookup(kCityStateData.Bonus);
            end
        end

		Controls.FocusedItemDescription:LocalizeAndSetText(description);

		-- Icon
		Controls.FocusedItemIcon:SetIcon(item.Icon);
		Controls.FocusedItemIcon:SetHide(false);
		Controls.FocusedItemIcon:SetColor(frontColor);
	end
end

-- ===========================================================================
function GetCityStateData( civType:string )
	-- Refresh the cache if needed
	if m_kCityStateDataCache[civType] == nil then

		m_kCityStateDataCache[civType] = {};

		local query:string = "SELECT CityStateCategory, Bonus, Bonus_XP1, Bonus_XP2 from CityStates where CivilizationType = ?";
		local kResults:table = DB.ConfigurationQuery(query, civType);
		if(kResults) then
			for i,v in ipairs(kResults) do
				for name, value in pairs(v) do
					m_kCityStateDataCache[civType][name] = value;
				end
			end
		end
	end

	return m_kCityStateDataCache[civType];
end

-- ===========================================================================
function SetAllItems(bState: boolean)
	for _, node in ipairs(m_kItemList) do
		local item:table = node["item"];
		local checkBox:table = node["checkbox"];

		checkBox:SetCheck(bState);
		if m_bInvertSelection then
			m_kSelectedValues[item.Value] = not bState;
		else
			m_kSelectedValues[item.Value] = bState;
		end
	end
end

-- ===========================================================================
function OnSelectAll()
	SetAllItems(true);
	RefreshCountWarning();
end

-- ===========================================================================
function OnSelectNone()
	SetAllItems(false);
	RefreshCountWarning();
end

-- ===========================================================================
function ParameterInitialize(parameter : table, pGameParameters:table)
	m_kParameter = parameter;
	m_kGameParameters = pGameParameters;
	m_kSelectedValues = {};

	m_kCityStateCountParam = pGameParameters.Parameters["CityStateCount"];
	m_OriginalCityStateCount = m_kCityStateCountParam.Value;

	local kRulesetParam = pGameParameters.Parameters["Ruleset"];
	m_RulesetType = kRulesetParam.Value.Value;

	if (parameter.UxHint ~= nil and parameter.UxHint == "InvertSelection") then
		m_bInvertSelection = true;
	else
		m_bInvertSelection = false;
	end

	if(parameter.Value) then
		for i,v in ipairs(parameter.Value) do
			m_kSelectedValues[v.Value] = true;
		end
	end

	Controls.TopDescription:SetText(parameter.Description);
	Controls.WindowTitle:SetText(parameter.Name);
	m_pItemIM:ResetInstances();

	RefreshList();
	RefreshCountWarning()

	InitCityStateCountSlider(pGameParameters);
	InitSortByFilter();

	OnItemFocus(parameter.Values[1]);
end

-- ===========================================================================
function RefreshList( sortByFunc )

	-- Remember the focused city-state by identity; the sort changes its index.
	local focusedValue = (m_kItemList ~= nil and m_kItemList[m_keyNavItemIndex] ~= nil) and m_kItemList[m_keyNavItemIndex].item.Value or nil;
	m_currentSortFunc = (sortByFunc ~= nil) and sortByFunc or SortByName;

	m_numSelected = 0;
	m_kItemList = {};

	-- Sort list
	table.sort(m_kParameter.Values, sortByFunc ~= nil and sortByFunc or SortByName);

	-- Update UI
	m_pItemIM:ResetInstances();
	for i, v in ipairs(m_kParameter.Values) do
		InitializeItem(v);
	end

	if focusedValue ~= nil then
		for i, node in ipairs(m_kItemList) do
			if node.item.Value == focusedValue then m_keyNavItemIndex = i; break; end
		end
	end
end

-- ===========================================================================
function RefreshCountWarning()
	if m_kParameter ~= nil then
		local numSelected:number = 0;

		for i, v in ipairs(m_kParameter.Values) do
			if not IsItemSelected(v) then
				numSelected = numSelected + 1;
			end
		end

		if numSelected < m_kCityStateCountParam.Value then
			Controls.ConfirmButton:SetDisabled(true);
			Controls.CountWarning:SetText(Locale.ToUpper(Locale.Lookup("LOC_CITY_STATE_PICKER_COUNT_WARNING", m_kCityStateCountParam.Value, m_kCityStateCountParam.Value - numSelected)));
		else
			Controls.ConfirmButton:SetDisabled(false);
			Controls.CountWarning:SetText("");
		end
	end
end

-- ===========================================================================
function SortByName(kItemA:table, kItemB:table)
	return Locale.Compare(kItemA.Name, kItemB.Name) == -1;
end

-- ===========================================================================
function SortByType(kItemA:table, kItemB:table)
	local kItemDataA:table = GetCityStateData(kItemA.Value);
	local kItemDataB:table = GetCityStateData(kItemB.Value);

	if kItemDataA.CityStateCategory ~= nil and kItemDataB.CityStateCategory ~= nil then
		return Locale.Compare(kItemDataA.CityStateCategory, kItemDataB.CityStateCategory) == -1;
	else
		return false;
	end
end

-- ===========================================================================
function InitCityStateCountSlider( pGameParameters:table )

	local kValues:table = m_kCityStateCountParam.Values;

	Controls.CityStateCountNumber:SetText(m_kCityStateCountParam.Value);
	Controls.CityStateCountSlider:SetNumSteps(kValues.MaximumValue - kValues.MinimumValue);
	Controls.CityStateCountSlider:SetStep(m_kCityStateCountParam.Value - kValues.MinimumValue);

	Controls.CityStateCountSlider:RegisterSliderCallback(function()
		local stepNum:number = Controls.CityStateCountSlider:GetStep();
		local value:number = m_kCityStateCountParam.Values.MinimumValue + stepNum;
			
		-- This method can get called pretty frequently, try and throttle it.
		if(m_kCityStateCountParam.Value ~= value) then
			pGameParameters:SetParameterValue(m_kCityStateCountParam, value);
			Controls.CityStateCountNumber:SetText(value);
			Network.BroadcastGameConfig();
			RefreshCountWarning();
		end
	end);

end

-- ===========================================================================
function InitSortByFilter()

	local uiButton:object = Controls.SortByPulldown:GetButton();
	uiButton:SetText(Locale.Lookup("LOC_CITY_STATE_PICKER_SORT_NAME"));

	Controls.SortByPulldown:ClearEntries();

	local pNameEntryInst:object = {};
	Controls.SortByPulldown:BuildEntry( "InstanceOne", pNameEntryInst );
	pNameEntryInst.Button:SetText(Locale.Lookup("LOC_CITY_STATE_PICKER_SORT_NAME"));
	pNameEntryInst.Button:RegisterCallback( Mouse.eLClick, 
		function() 
			Controls.SortByPulldown:GetButton():SetText(Locale.Lookup("LOC_CITY_STATE_PICKER_SORT_NAME"));
			RefreshList(SortByName);
		end );

	local pTypeEntryInst:object = {};
	Controls.SortByPulldown:BuildEntry( "InstanceOne", pTypeEntryInst );
	pTypeEntryInst.Button:SetText(Locale.Lookup("LOC_CITY_STATE_PICKER_SORT_TYPE"));
	pTypeEntryInst.Button:RegisterCallback( Mouse.eLClick, 
		function() 
			Controls.SortByPulldown:GetButton():SetText(Locale.Lookup("LOC_CITY_STATE_PICKER_SORT_TYPE"));
			RefreshList(SortByType);
		end );

	Controls.SortByPulldown:CalculateInternals();
end

-- ===========================================================================
function InitializeItem(item:table)
	local c: table = m_pItemIM:GetInstance();
	c.Name:SetText(item.Name);

	local backColor, frontColor = UI.GetPlayerColorValues(item.Value, 0);

	c.Icon:SetIcon(item.Icon);
	c.Icon:SetColor(frontColor);
	c.IconBacking:SetColor(backColor);

	c.Button:RegisterCallback( Mouse.eMouseEnter, function() OnItemFocus(item); end );
	c.Button:RegisterCallback( Mouse.eLClick, function() OnItemSelect(item, c.Selected); end );
	c.Selected:RegisterCallback( Mouse.eLClick, function() OnItemSelect(item, c.Selected); end );
	if m_bInvertSelection then
		c.Selected:SetCheck(not IsItemSelected(item));
	else
		c.Selected:SetCheck(IsItemSelected(item));
		m_numSelected = m_numSelected + 1;
	end

	local listItem:table = {};
	listItem["item"] = item;
	listItem["checkbox"] = c.Selected;
	table.insert(m_kItemList, listItem);
end

-- ===========================================================================
function OnShutdown()
	Close();
	m_pItemIM:DestroyInstances();
	LuaEvents.CityStatePicker_Initialize.Remove( ParameterInitialize );
end

-- ===========================================================================
-- ===========================================================================
-- Keyboard navigation (screen reader)
-- Two groups switched with Tab: the city-state list (Up/Down/Home/End) and the controls
-- (number of city-states, sort, Select All, Select None, OK, Back).
-- Space/Enter toggles a city-state, I reads its suzerain bonus, Left/Right changes the number or sort,
-- Enter presses a button, Escape cancels.
-- ===========================================================================
local m_keyNavGroup		:number = 1;	-- 1 = city-states, 2 = controls
local m_keyNavButtonIndex:number = 1;

local function KeyNavControls()
	return {
		{ kind = "count" },
		{ kind = "sort" },
		{ name = Locale.Lookup("LOC_SELECT_ALL"),	activate = OnSelectAll,		message = "All selected" },
		{ name = Locale.Lookup("LOC_SELECT_NONE"),	activate = OnSelectNone,	message = "All deselected" },
		{ name = Locale.Lookup("LOC_OK_BUTTON"),	activate = OnConfirmChanges },
		{ name = Locale.Lookup("LOC_MULTIPLAYER_BACK")..", cancel",	activate = OnBackButton },
	};
end

local function KeyNavIsChecked( node:table )
	return node.checkbox:IsChecked();
end

local function KeyNavCountText()
	local checked:number = 0;
	for _, node in ipairs(m_kItemList) do
		if KeyNavIsChecked(node) then checked = checked + 1; end
	end
	return tostring(checked).." of "..tostring(#m_kItemList).." selected";
end

local function KeyNavWarningText()
	local warning:string = CleanTextForSpeech(Controls.CountWarning:GetText());
	if warning ~= "" then return ". "..warning; end
	return "";
end

local function KeyNavTypeText( item:table )
	local data:table = GetCityStateData(item.Value);
	local category:string = data and data.CityStateCategory or nil;
	if category == nil then return ""; end
	local tag:string = "LOC_CITY_STATES_TYPE_"..string.upper(tostring(category));
	local text:string = Locale.Lookup(tag);
	if text == tag then text = tostring(category); end
	return CleanTextForSpeech(text);
end

local function KeyNavItemText( index:number )
	local node:table = m_kItemList[index];
	local typeText:string = KeyNavTypeText(node.item);
	return CleanTextForSpeech(node.item.Name)..(typeText ~= "" and (", "..typeText) or "")..", "..(KeyNavIsChecked(node) and "checked" or "unchecked")..", "..tostring(index).." of "..tostring(#m_kItemList);
end

local function KeyNavCountValueText()
	return "City-states to spawn: "..tostring(m_kCityStateCountParam.Value);
end

local function KeyNavSortText()
	return string.gsub(CleanTextForSpeech(Locale.Lookup("LOC_CITY_STATE_PICKER_SORT_BY")), ":%s*$", "")..": "..Locale.Lookup((m_currentSortFunc == SortByType) and "LOC_CITY_STATE_PICKER_SORT_TYPE" or "LOC_CITY_STATE_PICKER_SORT_NAME");
end

local function KeyNavAnnounceCurrent()
	if m_keyNavGroup == 1 then
		OutputMessageToScreenReader(KeyNavItemText(m_keyNavItemIndex), false);
	else
		local controls:table = KeyNavControls();
		local control:table = controls[m_keyNavButtonIndex];
		local text:string;
		if control.kind == "count" then
			text = KeyNavCountValueText()..", Left and Right to change";
		elseif control.kind == "sort" then
			text = KeyNavSortText()..", Left and Right to change";
		else
			text = control.name..", button";
			if control.activate == OnConfirmChanges and Controls.ConfirmButton:IsDisabled() then
				text = text..", disabled"..KeyNavWarningText();
			end
		end
		OutputMessageToScreenReader(text..", "..tostring(m_keyNavButtonIndex).." of "..tostring(#controls), false);
	end
end

local function KeyNavFocusItem( index:number )
	m_keyNavItemIndex = index;
	local node:table = m_kItemList[index];
	OnItemFocus(node.item);	-- updates the info panel like hovering would
	KeyNavScrollIntoView(Controls.ItemsScrollPanel, Controls.ItemsPanel, node.checkbox);
	KeyNavAnnounceCurrent();
end

function OnShow()
	m_keyNavGroup = 1;
	m_keyNavItemIndex = 1;
	m_keyNavButtonIndex = 1;
	if m_kParameter == nil or m_kItemList == nil then return; end
	local title:string = CleanTextForSpeech(Controls.WindowTitle:GetText());
	OutputMessageToScreenReader(title..", "..KeyNavCountText()..". "..KeyNavCountValueText()..KeyNavWarningText()..". Up and Down to browse, Space to toggle, I for the suzerain bonus, Tab for the number, sort, Select All, Select None and OK, Escape to cancel", true);
	if #m_kItemList > 0 then
		OnItemFocus(m_kItemList[1].item);
		OutputMessageToScreenReader(KeyNavItemText(1), true);
	end
end

local function KeyNavMove( delta:number )
	if m_keyNavGroup == 1 then
		local count:number = #m_kItemList;
		if count == 0 then return; end
		KeyNavFocusItem((m_keyNavItemIndex - 1 + delta) % count + 1);
	else
		m_keyNavButtonIndex = (m_keyNavButtonIndex - 1 + delta) % #KeyNavControls() + 1;
		KeyNavAnnounceCurrent();
	end
end

-- Left/Right on the count and sort rows. Returns true if the key was used.
local function KeyNavAdjust( delta:number )
	local control:table = KeyNavControls()[m_keyNavButtonIndex];
	if control.kind == "count" then
		local param:table = m_kGameParameters.Parameters["CityStateCount"] or m_kCityStateCountParam;
		local value:number = math.max(param.Values.MinimumValue, math.min(param.Values.MaximumValue, param.Value + delta));
		if value ~= param.Value then
			m_kGameParameters:SetParameterValue(param, value);
			Network.BroadcastGameConfig();
			m_kCityStateCountParam = m_kGameParameters.Parameters["CityStateCount"] or param;
			Controls.CityStateCountNumber:SetText(m_kCityStateCountParam.Value);
			Controls.CityStateCountSlider:SetStep(m_kCityStateCountParam.Value - param.Values.MinimumValue);
			RefreshCountWarning();
		end
		OutputMessageToScreenReader(KeyNavCountValueText()..KeyNavWarningText(), false);
		return true;
	elseif control.kind == "sort" then
		local sortByType:boolean = (m_currentSortFunc ~= SortByType);	-- toggle relative to the sort really in effect
		Controls.SortByPulldown:GetButton():SetText(Locale.Lookup(sortByType and "LOC_CITY_STATE_PICKER_SORT_TYPE" or "LOC_CITY_STATE_PICKER_SORT_NAME"));
		RefreshList(sortByType and SortByType or SortByName);	-- keeps focus on the same city-state
		OutputMessageToScreenReader(KeyNavSortText(), false);
		return true;
	end
	return false;
end

function KeyNavKeyHandler( key:number )
	if m_kParameter == nil or m_kItemList == nil then
		if key == Keys.VK_ESCAPE then ContextPtr:SetHide(true); end
		return;
	end
	if key == Keys.VK_ESCAPE then
		OnBackButton();
		OutputMessageToScreenReader("Cancelled", false);
	elseif key == Keys.VK_DOWN then
		KeyNavMove(1);
	elseif key == Keys.VK_UP then
		KeyNavMove(-1);
	elseif key == Keys.VK_RIGHT and m_keyNavGroup == 2 then
		if not KeyNavAdjust(1) then KeyNavMove(1); end
	elseif key == Keys.VK_LEFT and m_keyNavGroup == 2 then
		if not KeyNavAdjust(-1) then KeyNavMove(-1); end
	elseif key == Keys.VK_HOME and m_keyNavGroup == 1 and #m_kItemList > 0 then
		KeyNavFocusItem(1);
	elseif key == Keys.VK_END and m_keyNavGroup == 1 and #m_kItemList > 0 then
		KeyNavFocusItem(#m_kItemList);
	elseif key == Keys.I and m_keyNavGroup == 1 and #m_kItemList > 0 then
		OnItemFocus(m_kItemList[m_keyNavItemIndex].item);
		OutputMessageToScreenReader(CleanTextForSpeech(Controls.FocusedItemName:GetText())..". "..CleanTextForSpeech(Controls.FocusedItemDescription:GetText()), false);
	elseif key == Keys.VK_TAB then
		m_keyNavGroup = (m_keyNavGroup == 1) and 2 or 1;
		if m_keyNavGroup == 2 then m_keyNavButtonIndex = 1; end
		KeyNavAnnounceCurrent();
	elseif key == Keys.VK_RETURN or key == Keys.VK_SPACE then
		if m_keyNavGroup == 1 then
			local node:table = m_kItemList[m_keyNavItemIndex];
			if node ~= nil then
				local hadWarning:boolean = CleanTextForSpeech(Controls.CountWarning:GetText()) ~= "";
				OnItemSelect(node.item, node.checkbox);
				local warning:string = KeyNavWarningText();
				if warning == "" and hadWarning then warning = ". Minimum reached, OK available"; end
				OutputMessageToScreenReader(KeyNavItemText(m_keyNavItemIndex)..warning, false);
			end
		elseif key == Keys.VK_RETURN then
			local control:table = KeyNavControls()[m_keyNavButtonIndex];
			if control.activate == nil then
				KeyNavAnnounceCurrent();
			elseif control.activate == OnConfirmChanges then
				if Controls.ConfirmButton:IsDisabled() then
					OutputMessageToScreenReader("OK is not available"..KeyNavWarningText(), false);
				else
					local summary:string = KeyNavCountText();
					OnConfirmChanges();
					OutputMessageToScreenReader("OK, "..summary, false);
				end
			elseif control.activate == OnBackButton then
				OnBackButton();
				OutputMessageToScreenReader("Cancelled", false);
			else
				control.activate();
				OutputMessageToScreenReader(control.message..", "..KeyNavCountText()..KeyNavWarningText(), false);
			end
		end
	end
end

function OnInputHandler( pInputStruct:table )
	local uiMsg = pInputStruct:GetMessageType();
	if uiMsg == KeyEvents.KeyUp then
		local ok, err = xpcall(function() KeyNavKeyHandler(pInputStruct:GetKey()); end, KeyNavErrorHandler);
		if not ok then print("KEYNAV ERROR: "..tostring(err)); end
	end
	return true;
end

-- ===========================================================================
function Initialize()
	ContextPtr:SetShutdown( OnShutdown );
	ContextPtr:SetInputHandler( OnInputHandler, true );
	ContextPtr:SetShowHandler( OnShow );

	local OnMouseEnter = function() UI.PlaySound("Main_Menu_Mouse_Over"); end;

	Controls.CloseButton:RegisterCallback( Mouse.eLClick, OnBackButton );
	Controls.CloseButton:RegisterCallback( Mouse.eMouseEnter, OnMouseEnter);
	Controls.ConfirmButton:RegisterCallback( Mouse.eLClick, OnConfirmChanges );
	Controls.ConfirmButton:RegisterCallback( Mouse.eMouseEnter, OnMouseEnter);
	Controls.SelectAllButton:RegisterCallback( Mouse.eLClick, OnSelectAll);
	Controls.SelectAllButton:RegisterCallback( Mouse.eMouseEnter, OnMouseEnter);
	Controls.SelectNoneButton:RegisterCallback( Mouse.eLClick, OnSelectNone);
	Controls.SelectNoneButton:RegisterCallback( Mouse.eMouseEnter, OnMouseEnter);

	LuaEvents.CityStatePicker_Initialize.Add( ParameterInitialize );
end
Initialize();
