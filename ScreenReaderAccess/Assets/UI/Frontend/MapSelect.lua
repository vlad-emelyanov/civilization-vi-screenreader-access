
include("InstanceManager");
include("KeyboardNavigation");
include("ScreenReader");

-- ===========================================================================
-- Members
-- ===========================================================================
m_mapSelectorIM	=	InstanceManager:new("MapPreviewInstance",	"MapButton", Controls.MapSelectPanel);
m_mapInfoIM =		InstanceManager:new("MapInfoInstance", "MapContainer", Controls.MapInfoPanel);

local m_uiMapInfo		:table = {};
local m_kAllMaps		:table;
local m_selectedMapValue :string;
local m_lastSetMapValue	:string;
local m_selectedMap		:table;

local m_sortType :number = 0;
local m_lastSelectedSort :table;

local DEFAULT_MAP_RAWNAME = "LOC_MAP_CONTINENTS";

-- Keyboard navigation state: maps in the order they are shown, and the focused one.
local m_keyNavMaps		:table = {};
local m_keyNavInitialValue :string;	-- map value selected when the window was shown (for Escape)

-- ===========================================================================
function Close()
	ContextPtr:SetHide(true);
end

-- ===========================================================================
function OnBackButton()
	Close();
end

-- ===========================================================================
function OnSelectMapButton()
	m_lastSetMapValue = m_selectedMapValue;
	LuaEvents.MapSelect_SetMapByValue( m_selectedMapValue );
	Close();
end

-- ===========================================================================
function OnSortButton( num:number, button:table )
	button:SetCheck(true);
	if(m_lastSelectedSort == button)then
		return;
	end
	m_lastSelectedSort = button;
	m_sortType = num;
	PopulateMapSelectPanel();
end

-- ===========================================================================
function OnMapButton(kMapData :table, c :table)
	
	m_uiMapInfo.MapName:SetText(Locale.Lookup(kMapData.RawName));
	m_uiMapInfo.MapDescription:SetText(Locale.Lookup(kMapData.RawDescription));
	m_uiMapInfo.MapImagePreview:SetTexture(kMapData.Texture);
	m_selectedMapValue = kMapData.Value;	

	c:SetSelected(true);

	if(m_selectedMap == c) then return; end

	if(m_selectedMap ~= nil) then
		m_selectedMap:SetSelected(false);
	end
	m_selectedMap = c;
end

-- ===========================================================================
function LoadMaps(k:table)
	m_kAllMaps = k;
	m_selectedMap = nil;
	m_selectedMapValue = nil;
	PopulateMapSelectPanel();
end

-- ===========================================================================
function PopulateMapSelectPanel()
	m_keyNavMaps = {};

	if(m_mapSelectorIM ~= nil) then
		m_mapSelectorIM:ResetInstances();
	end
	
	for k, v in pairs(m_kAllMaps) do
		if(m_sortType == 1 and v.IsOfficial) then
			PopulateMapButton(m_kAllMaps[k]);
		elseif(m_sortType == 2 and v.IsWorldBuilder) then
			PopulateMapButton(m_kAllMaps[k]);
		elseif(m_sortType == 0) then
			PopulateMapButton(m_kAllMaps[k]);
		end
	end
end

-- ===========================================================================
function PopulateMapButton(kMapData:table)
	if(kMapData.Texture == nil) then
		kMapData.Texture = "Map_Community";
	end

	local uiMap :table = m_mapSelectorIM:GetInstance();
	uiMap.MapImagePreview:SetTexture(kMapData.Texture);
	uiMap.MapName:SetText(Locale.Lookup(kMapData.RawName));
	uiMap.MapButton:SetToolTipString(Locale.Lookup(kMapData.RawDescription));
	uiMap.MapButton:RegisterCallback( Mouse.eLClick, function() OnMapButton(kMapData, uiMap.MapButton); end );
	uiMap.MapButton:RegisterCallback( Mouse.eLDblClick,function() m_selectedMapValue = kMapData.Value; OnSelectMapButton(); end);
	uiMap.MapButton:SetSelected(false);
	table.insert(m_keyNavMaps, { data = kMapData, button = uiMap.MapButton });

	if(m_selectedMapValue == kMapData.Value)then
		OnMapButton(kMapData, uiMap.MapButton);
	elseif(m_lastSetMapValue == kMapData.Value and m_selectedMapValue == nil) then
		OnMapButton(kMapData, uiMap.MapButton);

	--This will only hit true the first time the screen is opened
	elseif(m_selectedMap == nil and m_lastSetMapValue == nil) then
		if(kMapData.RawName == DEFAULT_MAP_RAWNAME) then
			OnMapButton(kMapData, uiMap.MapButton);
		end
	end
end

-- ===========================================================================
function ClearMapData()
	m_lastSetMapValue = nil;
end

-- ===========================================================================
-- Keyboard navigation (screen reader)
-- ===========================================================================
local function KeyNavMapText( index:number )
	local entry:table = m_keyNavMaps[index];
	local text:string = Locale.Lookup(entry.data.RawName)..", "..tostring(index).." of "..tostring(#m_keyNavMaps);
	if entry.data.RawDescription ~= nil then
		local description:string = CleanTextForSpeech(Locale.Lookup(entry.data.RawDescription));
		if description ~= "" then text = text..". "..description; end
	end
	return text;
end

local function KeyNavFocusMap( index:number )
	local entry:table = m_keyNavMaps[index];
	OnMapButton(entry.data, entry.button);	-- updates the info panel and the selection like a click
	KeyNavScrollIntoView(Controls.ParametersScrollPanel, Controls.MapSelectPanel, entry.button);
	OutputMessageToScreenReader(KeyNavMapText(index), false);
end

local function KeyNavFindSelected()
	for i, entry in ipairs(m_keyNavMaps) do
		if entry.data.Value == m_selectedMapValue then return i; end
	end
	return 1;
end

function OnShow()
	m_keyNavInitialValue = m_selectedMapValue;
	if #m_keyNavMaps == 0 then
		OutputMessageToScreenReader(Locale.Lookup("LOC_SETUP_MAP_CREATE_GAME_SELECT_MAP")..". No maps available. Escape to close", true);
		return;
	end
	OutputMessageToScreenReader(CleanTextForSpeech(Controls.WindowTitle:GetText())..", "..tostring(#m_keyNavMaps).." maps. Up and Down to browse, Enter to select, Escape to cancel", true);
	OutputMessageToScreenReader("Current map: "..KeyNavMapText(KeyNavFindSelected()), true);
end

-- Called by the setup screen before the window is shown with the map currently set in the game.
function OnSetCurrentMap( value:string )
	m_lastSetMapValue = value;
end

function KeyNavKeyHandler( key:number )
	local count:number = #m_keyNavMaps;
	-- The focused map is the selected one (keyboard focus selects like a click), so mouse clicks and tab changes stay in sync.
	local index:number = KeyNavFindSelected();
	if key == Keys.VK_ESCAPE then
		-- Cancel: undo the highlight changes made while browsing.
		if m_keyNavInitialValue ~= nil and m_keyNavInitialValue ~= m_selectedMapValue then
			for _, entry in ipairs(m_keyNavMaps) do
				if entry.data.Value == m_keyNavInitialValue then
					OnMapButton(entry.data, entry.button);
					break;
				end
			end
		end
		Close();
		OutputMessageToScreenReader("Cancelled", false);
	elseif count == 0 then
		return;
	elseif key == Keys.VK_DOWN then
		KeyNavFocusMap(index % count + 1);
	elseif key == Keys.VK_UP then
		KeyNavFocusMap((index - 2) % count + 1);
	elseif key == Keys.VK_HOME then
		KeyNavFocusMap(1);
	elseif key == Keys.VK_END then
		KeyNavFocusMap(count);
	elseif key == Keys.VK_SPACE then
		OutputMessageToScreenReader(KeyNavMapText(index), false);
	elseif key == Keys.VK_RETURN then
		local entry:table = m_keyNavMaps[index];
		local name:string = Locale.Lookup(entry.data.RawName);
		m_selectedMapValue = entry.data.Value;
		OnSelectMapButton();
		OutputMessageToScreenReader("Selected "..name, false);
	end
end

-- ===========================================================================
function OnInputHandler( pInputStruct:table )
	local uiMsg = pInputStruct:GetMessageType();
	if uiMsg == KeyEvents.KeyUp then
		local ok, err = xpcall(function() KeyNavKeyHandler(pInputStruct:GetKey()); end, function(e) return debug.traceback(tostring(e), 2); end);
		if not ok then print("KEYNAV ERROR: "..tostring(err)); end
	end
	return true;
end

-- ===========================================================================
function Initialize()
	ContextPtr:SetInputHandler( OnInputHandler, true );
	ContextPtr:SetShowHandler( OnShow );

	Controls.CloseButton:RegisterCallback( Mouse.eLClick, OnBackButton );
	Controls.CloseButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	Controls.MapSelectionButton:RegisterCallback( Mouse.eLClick, OnSelectMapButton );
	Controls.MapSelectionButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	Controls.AllMapsSelector:RegisterCallback( Mouse.eLClick, function() OnSortButton(0, Controls.AllMapsSelector); end );
	Controls.AllMapsButton:RegisterCallback( Mouse.eLClick, function() OnSortButton(0, Controls.AllMapsSelector); end );
	Controls.AllMapsSelector:SetCheck(true);
	Controls.OfficialMapsSelector:RegisterCallback( Mouse.eLClick, function() OnSortButton(1, Controls.OfficialMapsSelector); end );
	Controls.OfficialMapsButton:RegisterCallback( Mouse.eLClick, function() OnSortButton(1, Controls.OfficialMapsSelector); end );
	Controls.WorldBuilderMapsSelector:RegisterCallback( Mouse.eLClick, function() OnSortButton(2, Controls.WorldBuilderMapsSelector); end );
	Controls.WorldBuilderMapsButton:RegisterCallback( Mouse.eLClick, function() OnSortButton(2, Controls.WorldBuilderMapsSelector); end );

	LuaEvents.MapSelect_PopulatedMaps.Add( LoadMaps );
	LuaEvents.MapSelect_ClearMapData.Add( ClearMapData );
	LuaEvents.MapSelect_SetCurrentMap.Add( OnSetCurrentMap );

	m_uiMapInfo = m_mapInfoIM:GetInstance();
end
Initialize();