-- Copyright 2020, Firaxis Games

include("InstanceManager");
include("PlayerSetupLogic");
include("Civ6Common");
include("KeyboardNavigation");
include("ScreenReader");

-- ===========================================================================
-- Members
-- ===========================================================================

local m_pItemIM:table = InstanceManager:new("ItemInstance",	"Button", Controls.ItemsPanel);
local m_pUniqueAbilityIM:table = InstanceManager:new("UniqueAbilityInstance", "Top", Controls.UniqueAbilityStack);

local m_kParameter:table = nil		-- Reference to the parameter being used. 
local m_kSelectedValues:table = nil	-- Table of string->boolean that represents checked off items.
local m_kItemList:table = nil;		-- Table of controls for select all/none

local m_bInvertSelection:boolean = false;

local m_numSelected:number = 0;
local m_minSelected:number = 2;

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

	LuaEvents.LeaderPicker_SetParameterValues(m_kParameter.ParameterId, values);
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
		local kPlayerInfo:table = GetPlayerInfo(item.Domain, item.Value);
		if kPlayerInfo then
			local backColor, frontColor = UI.GetPlayerColorValues(kPlayerInfo.PlayerColor);

			-- Icons
			Controls.FocusedCivIcon:SetIcon(kPlayerInfo.CivilizationIcon);
			Controls.FocusedCivIcon:SetColor(frontColor);
			Controls.FocusedCivIconBacking:SetColor(backColor);
			Controls.FocusedLeaderIcon:SetIcon(kPlayerInfo.LeaderIcon);

			-- Description
			Controls.FocusedLeaderName:SetText(Locale.ToUpper(kPlayerInfo.LeaderName));
			if kPlayerInfo.LeaderAbility then
				Controls.FocusedLeaderAbilityName:SetText(Locale.ToUpper(kPlayerInfo.LeaderAbility.Name));
				Controls.FocusedLeaderAbilityDesc:SetText(Locale.Lookup(kPlayerInfo.LeaderAbility.Description));
			end

			Controls.FocusedCivName:SetText(Locale.ToUpper(kPlayerInfo.CivilizationName));
			if kPlayerInfo.CivilizationAbility then
				Controls.FocusedCivAbilityName:SetText(Locale.ToUpper(kPlayerInfo.CivilizationAbility.Name));
				Controls.FocusedCivAbilityDesc:SetText(Locale.Lookup(kPlayerInfo.CivilizationAbility.Description));
			end

			m_pUniqueAbilityIM:ResetInstances();
			if kPlayerInfo.Uniques then
				for i, kAbility in ipairs(kPlayerInfo.Uniques) do
					local pInst:table = m_pUniqueAbilityIM:GetInstance();
					pInst.Icon:SetIcon(kAbility.Icon);
					pInst.Name:SetText(Locale.ToUpper(kAbility.Name));
					pInst.Description:SetText(Locale.Lookup(kAbility.Description));
				end
			end
		end
	end
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
function SelectLeadersWithNoWins()
	local kLeaderProgress:table = HallofFame.GetLeaderProgress(GameConfiguration.GetRuleSet())

	for _, kNode in ipairs(m_kItemList) do
		local kItem:table = kNode["item"];
		local uiCheckBox:table = kNode["checkbox"];

		local shouldSelect:boolean = false;

		local kLeaderEntry:table = kLeaderProgress[kItem.Value];
		if kLeaderEntry and kLeaderEntry.MostRecentVictoryType == nil then
			shouldSelect = true;
		end

		uiCheckBox:SetCheck(shouldSelect);
		if m_bInvertSelection then
			m_kSelectedValues[kItem.Value] = not shouldSelect;
		else
			m_kSelectedValues[kItem.Value] = shouldSelect;
		end
	end

	RefreshCountWarning();
end

-- ===========================================================================
function RemoveRandomLeadersFromParameter( kParameter:table )
	for i = #kParameter.AllValues, 1, -1 do
		local kItem:table = kParameter.AllValues[i];
		if kItem.Value == "RANDOM" or kItem.Value == "RANDOM_POOL1" or kItem.Value == "RANDOM_POOL2" then
			table.remove(kParameter.AllValues, i);
		end
	end

	for i = #kParameter.Values, 1, -1 do
		local kItem:table = kParameter.Values[i];
		if kItem.Value == "RANDOM" or kItem.Value == "RANDOM_POOL1" or kItem.Value == "RANDOM_POOL2" then
			table.remove(kParameter.Values, i);
		end
	end
end

-- ===========================================================================
function ParameterInitialize( kParameter:table, pGameParameters:table )

	RemoveRandomLeadersFromParameter(kParameter);

	m_kParameter = kParameter;
	m_kSelectedValues = {};

	if (kParameter.UxHint ~= nil and kParameter.UxHint == "InvertSelection") then
		m_bInvertSelection = true;
	else
		m_bInvertSelection = false;
	end

	if (kParameter.Value) then
		for i,v in ipairs(kParameter.Value) do
			m_kSelectedValues[v.Value] = true;
		end
	end

	Controls.TopDescription:SetText(kParameter.Description);
	Controls.WindowTitle:SetText(kParameter.Name);
	m_pItemIM:ResetInstances();

	RefreshList();
	RefreshCountWarning();	-- clear a stale warning from a previous opening

    InitPresets();

	OnItemFocus(kParameter.Values[1]);
end

-- ===========================================================================
function RefreshList( sortByFunc )

	m_numSelected = 0;
	m_kItemList = {};

	-- Sort list
	table.sort(m_kParameter.Values, sortByFunc ~= nil and sortByFunc or SortByName);

	-- Update UI
	m_pItemIM:ResetInstances();
	for i, v in ipairs(m_kParameter.Values) do
		InitializeItem(v);
	end
end

-- ===========================================================================
function RefreshCountWarning()
	local numSelected:number = 0;

	for i, v in ipairs(m_kParameter.Values) do
		if not IsItemSelected(v) then
			numSelected = numSelected + 1;
		end
	end

	if numSelected < m_minSelected then
		Controls.ConfirmButton:SetDisabled(true);
		Controls.CountWarning:SetText(Locale.ToUpper(Locale.Lookup("LOC_LEADER_POOL_COUNTER_WARNING", m_minSelected)));
	else
		Controls.ConfirmButton:SetDisabled(false);
		Controls.CountWarning:SetText("");
	end
end

-- ===========================================================================
function SortByName(kItemA:table, kItemB:table)
	return Locale.Compare(kItemA.Name, kItemB.Name) == -1;
end

-- ===========================================================================
function InitPresets()

	local uiButton:object = Controls.PresetPulldown:GetButton();
	uiButton:SetText(Locale.Lookup("LOC_LEADER_PICK_PRESET_ALL"));

	Controls.PresetPulldown:ClearEntries();

	local pNameEntryInst:object = {};
	Controls.PresetPulldown:BuildEntry( "InstanceOne", pNameEntryInst );
	pNameEntryInst.Button:SetText(Locale.Lookup("LOC_LEADER_PICK_PRESET_ALL"));
	pNameEntryInst.Button:RegisterCallback( Mouse.eLClick, 
		function() 
			Controls.PresetPulldown:GetButton():SetText(Locale.Lookup("LOC_LEADER_PICK_PRESET_ALL"));
			OnSelectAll();
		end );

	local pTypeEntryInst:object = {};
	Controls.PresetPulldown:BuildEntry( "InstanceOne", pTypeEntryInst );
	pTypeEntryInst.Button:SetText(Locale.Lookup("LOC_LEADER_PICK_PRESET_NONE"));
	pTypeEntryInst.Button:RegisterCallback( Mouse.eLClick, 
		function() 
			Controls.PresetPulldown:GetButton():SetText(Locale.Lookup("LOC_LEADER_PICK_PRESET_NONE"));
			OnSelectNone();
		end );

	local pTypeEntryInst:object = {};
	Controls.PresetPulldown:BuildEntry( "InstanceOne", pTypeEntryInst );
	pTypeEntryInst.Button:SetText(Locale.Lookup("LOC_LEADER_PICK_PRESET_NO_WINS"));
	pTypeEntryInst.Button:RegisterCallback( Mouse.eLClick, 
		function() 
			Controls.PresetPulldown:GetButton():SetText(Locale.Lookup("LOC_LEADER_PICK_PRESET_NO_WINS"));
			SelectLeadersWithNoWins();
		end );

	Controls.PresetPulldown:CalculateInternals();
end

-- ===========================================================================
function InitializeItem(item:table)

	local c: table = m_pItemIM:GetInstance();
	c.Name:SetText(item.Name);

	local kPlayerInfo:table = GetPlayerInfo(item.Domain, item.Value);
	if kPlayerInfo then
		c.LeaderIcon:SetIcon(kPlayerInfo.LeaderIcon);
	end

	c.Button:RegisterCallback( Mouse.eMouseEnter, function() OnItemFocus(item); end );
	c.Button:RegisterCallback( Mouse.eLClick, function() OnItemSelect(item, c.Selected, c.Button); end );
	c.Selected:RegisterCallback( Mouse.eLClick, function() OnItemSelect(item, c.Selected, c.Button); end );
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
	LuaEvents.LeaderPicker_Initialize.Remove( ParameterInitialize );
end

-- ===========================================================================
-- ===========================================================================
-- Keyboard navigation (screen reader)
-- Two groups switched with Tab: the leader list (Up/Down/Home/End) and the buttons
-- (Select All / Select None / leaders with no wins / OK / Back).
-- Space/Enter toggles a leader, I reads the full abilities, Enter presses a button, Escape cancels.
-- ===========================================================================
local m_keyNavGroup		:number = 1;	-- 1 = leaders, 2 = buttons
local m_keyNavItemIndex	:number = 1;
local m_keyNavButtonIndex:number = 1;

local function KeyNavButtons()
	return {
		{ name = Locale.Lookup("LOC_LEADER_PICK_PRESET_ALL"),		activate = OnSelectAll,				message = "All selected" },
		{ name = Locale.Lookup("LOC_LEADER_PICK_PRESET_NONE"),		activate = OnSelectNone,			message = "All deselected" },
		{ name = Locale.Lookup("LOC_LEADER_PICK_PRESET_NO_WINS"),	activate = SelectLeadersWithNoWins,	message = "Leaders with no wins selected" },
		{ name = Locale.Lookup("LOC_OK_BUTTON"),					activate = OnConfirmChanges },
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

local function KeyNavInfo( node:table )
	return GetPlayerInfo(node.item.Domain, node.item.Value);
end

-- "Leader, Civilization", unless the leader's name already mentions the civilization (e.g. "Eleanor of Aquitaine (England)").
local function KeyNavLeaderCivText( info:table )
	local leader:string = CleanTextForSpeech(Locale.Lookup(info.LeaderName));
	local civ:string = CleanTextForSpeech(Locale.Lookup(info.CivilizationName));
	if civ == "" or string.find(string.lower(leader), string.lower(civ), 1, true) ~= nil then return leader; end
	return leader..", "..civ;
end

local function KeyNavItemText( index:number, withAbilities:boolean )
	local node:table = m_kItemList[index];
	local info:table = KeyNavInfo(node);
	local name:string = CleanTextForSpeech(node.item.Name);
	if info ~= nil then
		name = KeyNavLeaderCivText(info);
	end
	local text:string = name..", "..(KeyNavIsChecked(node) and "checked" or "unchecked")..", "..tostring(index).." of "..tostring(#m_kItemList);
	if withAbilities and info ~= nil then
		if info.LeaderAbility ~= nil then
			text = text..". Leader ability: "..CleanTextForSpeech(Locale.Lookup(info.LeaderAbility.Name));
		end
		if info.CivilizationAbility ~= nil then
			text = text..". Civilization ability: "..CleanTextForSpeech(Locale.Lookup(info.CivilizationAbility.Name));
		end
	end
	return text;
end

local function KeyNavDetailsText( index:number )
	local node:table = m_kItemList[index];
	local info:table = KeyNavInfo(node);
	if info == nil then return CleanTextForSpeech(node.item.Name); end
	local parts:table = { CleanTextForSpeech(Locale.Lookup(info.LeaderName)) };
	if info.LeaderAbility ~= nil then
		table.insert(parts, "Leader ability: "..CleanTextForSpeech(Locale.Lookup(info.LeaderAbility.Name))..": "..CleanTextForSpeech(Locale.Lookup(info.LeaderAbility.Description)));
	end
	table.insert(parts, CleanTextForSpeech(Locale.Lookup(info.CivilizationName)));
	if info.CivilizationAbility ~= nil then
		table.insert(parts, "Civilization ability: "..CleanTextForSpeech(Locale.Lookup(info.CivilizationAbility.Name))..": "..CleanTextForSpeech(Locale.Lookup(info.CivilizationAbility.Description)));
	end
	if info.Uniques ~= nil then
		for _, ability in ipairs(info.Uniques) do
			table.insert(parts, "Unique: "..CleanTextForSpeech(Locale.Lookup(ability.Name))..": "..CleanTextForSpeech(Locale.Lookup(ability.Description)));
		end
	end
	return table.concat(parts, ". ");
end

local function KeyNavAnnounceCurrent( withAbilities:boolean )
	if m_keyNavGroup == 1 then
		OutputMessageToScreenReader(KeyNavItemText(m_keyNavItemIndex, withAbilities), false);
	else
		local buttons:table = KeyNavButtons();
		local button:table = buttons[m_keyNavButtonIndex];
		local text:string = button.name..", button, "..tostring(m_keyNavButtonIndex).." of "..tostring(#buttons);
		if button.activate == OnConfirmChanges and Controls.ConfirmButton:IsDisabled() then
			text = text..", disabled"..KeyNavWarningText();
		end
		OutputMessageToScreenReader(text, false);
	end
end

local function KeyNavFocusItem( index:number )
	m_keyNavItemIndex = index;
	local node:table = m_kItemList[index];
	OnItemFocus(node.item);	-- updates the info panel like hovering would
	KeyNavScrollIntoView(Controls.ItemsScrollPanel, Controls.ItemsPanel, node.checkbox);
	KeyNavAnnounceCurrent(true);
end

function OnShow()
	m_keyNavGroup = 1;
	m_keyNavItemIndex = 1;
	m_keyNavButtonIndex = 1;
	if m_kParameter == nil or m_kItemList == nil then return; end
	local title:string = CleanTextForSpeech(Controls.WindowTitle:GetText());
	OutputMessageToScreenReader(title..", "..KeyNavCountText()..KeyNavWarningText()..". " .. SRKey( "Up and Down" ) .. " to browse, " .. SRKey( "Space" ) .. " to toggle, I for abilities, " .. SRKey( "Tab" ) .. " for Select All, Select None and OK, " .. SRKey( "Escape" ) .. " to cancel", true);
	if #m_kItemList > 0 then
		OnItemFocus(m_kItemList[1].item);
		OutputMessageToScreenReader(KeyNavItemText(1, true), true);
	end
end

local function KeyNavMove( delta:number )
	if m_keyNavGroup == 1 then
		local count:number = #m_kItemList;
		if count == 0 then return; end
		KeyNavFocusItem((m_keyNavItemIndex - 1 + delta) % count + 1);
	else
		m_keyNavButtonIndex = (m_keyNavButtonIndex - 1 + delta) % #KeyNavButtons() + 1;
		KeyNavAnnounceCurrent(false);
	end
end

function KeyNavKeyHandler( key:number )
	if m_kParameter == nil or m_kItemList == nil then
		if key == Keys.VK_ESCAPE then Close(); end
		return;
	end
	if key == Keys.VK_ESCAPE then
		Close();
		OutputMessageToScreenReader("Cancelled", false);
	elseif key == Keys.VK_DOWN or (key == Keys.VK_RIGHT and m_keyNavGroup == 2) then
		KeyNavMove(1);
	elseif key == Keys.VK_UP or (key == Keys.VK_LEFT and m_keyNavGroup == 2) then
		KeyNavMove(-1);
	elseif key == Keys.VK_HOME and m_keyNavGroup == 1 and #m_kItemList > 0 then
		KeyNavFocusItem(1);
	elseif key == Keys.VK_END and m_keyNavGroup == 1 and #m_kItemList > 0 then
		KeyNavFocusItem(#m_kItemList);
	elseif key == Keys.I and m_keyNavGroup == 1 and #m_kItemList > 0 then
		OutputMessageToScreenReader(KeyNavDetailsText(m_keyNavItemIndex), false);
	elseif key == Keys.VK_TAB then
		m_keyNavGroup = (m_keyNavGroup == 1) and 2 or 1;
		if m_keyNavGroup == 2 then m_keyNavButtonIndex = 1; end
		KeyNavAnnounceCurrent(true);
	elseif key == Keys.VK_RETURN or key == Keys.VK_SPACE then
		if m_keyNavGroup == 1 then
			local node:table = m_kItemList[m_keyNavItemIndex];
			if node ~= nil then
				local hadWarning:boolean = CleanTextForSpeech(Controls.CountWarning:GetText()) ~= "";
				OnItemSelect(node.item, node.checkbox);
				local warning:string = KeyNavWarningText();
				if warning == "" and hadWarning then warning = ". Minimum reached, OK available"; end
				OutputMessageToScreenReader(KeyNavItemText(m_keyNavItemIndex, false)..warning, false);
			end
		elseif key == Keys.VK_RETURN then
			local button:table = KeyNavButtons()[m_keyNavButtonIndex];
			if button.activate == OnConfirmChanges then
				if Controls.ConfirmButton:IsDisabled() then
					OutputMessageToScreenReader("OK is not available"..KeyNavWarningText(), false);
				else
					local summary:string = KeyNavCountText();
					OnConfirmChanges();
					OutputMessageToScreenReader("OK, "..summary, false);
				end
			elseif button.activate == OnBackButton then
				OnBackButton();
				OutputMessageToScreenReader("Cancelled", false);
			else
				button.activate();
				OutputMessageToScreenReader(button.message..", "..KeyNavCountText()..KeyNavWarningText(), false);
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

	LuaEvents.LeaderPicker_Initialize.Add( ParameterInitialize );
end
Initialize();
