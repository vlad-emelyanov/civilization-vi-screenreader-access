
include("InstanceManager");
include("KeyboardNavigation");
include("ScreenReader");

-- ===========================================================================
-- Members
-- ===========================================================================
m_ItemIM = InstanceManager:new("ItemInstance",	"Button", Controls.ItemsPanel);

m_Parameter = nil		-- Reference to the parameter being used. 
m_SelectedValues = nil	-- Table of string->boolean that represents checked off items.
m_ItemList = nil;		-- Table of controls for select all/none

local m_bInvertSelection:boolean = false;

-- ===========================================================================
function Close()	
	-- Clear any temporary global variables.
	m_Parameter = nil;
	m_SelectedValues = nil;

	ContextPtr:SetHide(true);
end

-- ===========================================================================
function IsItemSelected(item: table) 
	return m_SelectedValues[item.Value] == true;
end

-- ===========================================================================
function OnBackButton()
	Close();
end

-- ===========================================================================
function OnConfirmChanges()
	-- Generate sorted list from selected values.
	local values = {}
	for k,v in pairs(m_SelectedValues) do
		if(v) then
			table.insert(values, k);
		end
	end

	LuaEvents.MultiSelectWindow_SetParameterValues(m_Parameter.ParameterId, values);
	Close();
end

-- ===========================================================================
function OnItemSelect(item :table, checkBox :table)
	local value = item.Value;
	local selected = not m_SelectedValues[value];

	m_SelectedValues[item.Value] = selected;
	if m_bInvertSelection then
		checkBox:SetCheck(not selected);
	else
		checkBox:SetCheck(selected);
	end
end

-- ===========================================================================
function OnItemFocus(item :table)
	if(item) then
		Controls.FocusedItemName:SetText(item.Name);
		Controls.FocusedItemDescription:LocalizeAndSetText(item.RawDescription);

		if((item.Icon and Controls.FocusedItemIcon:SetIcon(item.Icon)) or Controls.FocusedItemIcon:SetIcon("ICON_" .. item.Value)) then
			Controls.FocusedItemIcon:SetHide(false);
		else
			Controls.FocusedItemIcon:SetHide(true);
		end
	end
end

-- ===========================================================================
function SetAllItems(bState: boolean)
	for _, node in ipairs(m_ItemList) do
		local item:table = node["item"];
		local checkBox:table = node["checkbox"];

		checkBox:SetCheck(bState);
		if m_bInvertSelection then
			m_SelectedValues[item.Value] = not bState;
		else
			m_SelectedValues[item.Value] = bState;
		end
	end
end

-- ===========================================================================
function OnSelectAll()
	SetAllItems(true);
end

-- ===========================================================================
function OnSelectNone()
	SetAllItems(false);
end

-- ===========================================================================
function ParameterInitialize(parameter : table)
	m_Parameter = parameter;
	m_SelectedValues = {};

	if (parameter.UxHint ~= nil and parameter.UxHint == "InvertSelection") then
		m_bInvertSelection = true;
	else
		m_bInvertSelection = false;
	end

	if(parameter.Value) then
		for i,v in ipairs(parameter.Value) do
			m_SelectedValues[v.Value] = true;
		end
	end

	Controls.TopDescription:SetText(parameter.Description);
	Controls.WindowTitle:SetText(parameter.Name);
	m_ItemIM:ResetInstances();

	m_ItemList = {};
	for i, v in ipairs(parameter.Values) do
		InitializeItem(v);
	end

	OnItemFocus(parameter.Values[1]);
end

-- ===========================================================================
function InitializeItem(item:table)
	local c: table = m_ItemIM:GetInstance();
	c.Name:SetText(item.Name);
	if not item.Icon or not c.Icon:SetIcon(item.Icon) then
		c.Icon:SetIcon("ICON_" .. item.Value);
	end
	c.Button:RegisterCallback( Mouse.eMouseEnter, function() OnItemFocus(item); end );
	c.Button:RegisterCallback( Mouse.eLClick, function() OnItemSelect(item, c.Selected); end );
	c.Selected:RegisterCallback( Mouse.eLClick, function() OnItemSelect(item, c.Selected); end );
	if m_bInvertSelection then
		c.Selected:SetCheck(not IsItemSelected(item));
	else
		c.Selected:SetCheck(IsItemSelected(item));
	end

	local listItem:table = {};
	listItem["item"] = item;
	listItem["checkbox"] = c.Selected;
	table.insert(m_ItemList, listItem);
end

-- ===========================================================================
function OnShutdown()
	Close();
	m_ItemIM:DestroyInstances();
	LuaEvents.MultiSelectWindow_Initialize.Remove( ParameterInitialize );
end

-- ===========================================================================
-- Keyboard navigation (screen reader)
-- Two groups: the item list (Up/Down/Home/End) and the buttons (Select All, Select None, OK, Back),
-- switched with Tab. Space/Enter toggles an item; Enter presses a button.
-- ===========================================================================
local m_keyNavGroup		:number = 1;	-- 1 = items, 2 = buttons
local m_keyNavItemIndex	:number = 1;
local m_keyNavButtonIndex:number = 1;

local function KeyNavButtons()
	return {
		{ control = Controls.SelectAllButton,	name = Locale.Lookup("LOC_SELECT_ALL"),		activate = OnSelectAll,		message = "All selected" },
		{ control = Controls.SelectNoneButton,	name = Locale.Lookup("LOC_SELECT_NONE"),	activate = OnSelectNone,	message = "All deselected" },
		{ control = Controls.ConfirmButton,		name = Locale.Lookup("LOC_OK_BUTTON"),		activate = OnConfirmChanges },
		{ control = Controls.CloseButton,		name = Locale.Lookup("LOC_MULTIPLAYER_BACK")..", cancel", activate = OnBackButton },
	};
end

-- Whether the item is shown as checked (this accounts for inverted parameters).
local function KeyNavIsChecked( node:table )
	return node.checkbox:IsChecked();
end

local function KeyNavCountText()
	local checked:number = 0;
	for _, node in ipairs(m_ItemList) do
		if KeyNavIsChecked(node) then checked = checked + 1; end
	end
	return tostring(checked).." of "..tostring(#m_ItemList).." selected";
end

local function KeyNavItemText( index:number, withDescription:boolean )
	local node:table = m_ItemList[index];
	local text:string = CleanTextForSpeech(node.item.Name)..", "..(KeyNavIsChecked(node) and "checked" or "unchecked")..", "..tostring(index).." of "..tostring(#m_ItemList);
	if withDescription and node.item.RawDescription ~= nil then
		local description:string = CleanTextForSpeech(Locale.Lookup(node.item.RawDescription));
		if description ~= "" then text = text..". "..description; end
	end
	return text;
end

local function KeyNavAnnounceCurrent( withDescription:boolean )
	if m_keyNavGroup == 1 then
		OutputMessageToScreenReader(KeyNavItemText(m_keyNavItemIndex, withDescription), false);
	else
		local button:table = KeyNavButtons()[m_keyNavButtonIndex];
		OutputMessageToScreenReader(button.name..", button, "..tostring(m_keyNavButtonIndex).." of 4", false);
	end
end

local function KeyNavFocusItem( index:number )
	m_keyNavItemIndex = index;
	local node:table = m_ItemList[index];
	OnItemFocus(node.item);	-- updates the info panel like hovering would
	KeyNavScrollIntoView(Controls.ItemsScrollPanel, Controls.ItemsPanel, node.checkbox);
	KeyNavAnnounceCurrent(true);
end

function OnShow()
	m_keyNavGroup = 1;
	m_keyNavItemIndex = 1;
	m_keyNavButtonIndex = 1;
	if m_Parameter == nil or m_ItemList == nil then return; end
	local title:string = CleanTextForSpeech(Controls.WindowTitle:GetText());
	OutputMessageToScreenReader(title..", "..KeyNavCountText()..". " .. SRKey( "Up and Down" ) .. " to browse, " .. SRKey( "Space" ) .. " to toggle, " .. SRKey( "Tab" ) .. " for Select All, Select None and OK, " .. SRKey( "Escape" ) .. " to cancel", true);
	if #m_ItemList > 0 then
		OnItemFocus(m_ItemList[1].item);
		OutputMessageToScreenReader(KeyNavItemText(1, true), true);
	end
end

local function KeyNavMove( delta:number )
	if m_keyNavGroup == 1 then
		local count:number = #m_ItemList;
		if count == 0 then return; end
		KeyNavFocusItem((m_keyNavItemIndex - 1 + delta) % count + 1);
	else
		m_keyNavButtonIndex = (m_keyNavButtonIndex - 1 + delta) % 4 + 1;
		KeyNavAnnounceCurrent(false);
	end
end

function KeyNavKeyHandler( key:number )
	if m_Parameter == nil or m_ItemList == nil then
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
	elseif key == Keys.VK_HOME and m_keyNavGroup == 1 and #m_ItemList > 0 then
		KeyNavFocusItem(1);
	elseif key == Keys.VK_END and m_keyNavGroup == 1 and #m_ItemList > 0 then
		KeyNavFocusItem(#m_ItemList);
	elseif key == Keys.VK_TAB then
		m_keyNavGroup = (m_keyNavGroup == 1) and 2 or 1;
		if m_keyNavGroup == 2 then m_keyNavButtonIndex = 1; end
		KeyNavAnnounceCurrent(true);
	elseif key == Keys.VK_RETURN or key == Keys.VK_SPACE then
		if m_keyNavGroup == 1 then
			local node:table = m_ItemList[m_keyNavItemIndex];
			if node ~= nil then
				OnItemSelect(node.item, node.checkbox);
				OutputMessageToScreenReader(KeyNavItemText(m_keyNavItemIndex, false), false);
			end
		elseif key == Keys.VK_RETURN then
			local button:table = KeyNavButtons()[m_keyNavButtonIndex];
			if button.activate == OnConfirmChanges then
				local summary:string = KeyNavCountText();
				OnConfirmChanges();
				OutputMessageToScreenReader("OK, "..summary, false);
			elseif button.activate == OnBackButton then
				OnBackButton();
				OutputMessageToScreenReader("Cancelled", false);
			else
				button.activate();
				OutputMessageToScreenReader(button.message..", "..KeyNavCountText(), false);
			end
		end
	end
end

-- ===========================================================================
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

	LuaEvents.MultiSelectWindow_Initialize.Add( ParameterInitialize );
end
Initialize();