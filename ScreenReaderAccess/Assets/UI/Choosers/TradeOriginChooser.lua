-- ===========================================================================
--
--	Slideout panel that allows the player to move their trade units to other city centers
--
-- ===========================================================================
include("InstanceManager");
include("AnimSidePanelSupport");
include("ScreenReader");		-- ScreenReaderAccess
include("KeyNavList");			-- ScreenReaderAccess
include("TradeText");			-- ScreenReaderAccess

-- ===========================================================================
--	CONSTANTS
-- ===========================================================================
local RELOAD_CACHE_ID:string = "TradeOriginChooser"; -- Must be unique (usually the same as the file name)

-- ===========================================================================
--	MEMBERS
-- ===========================================================================
local m_AnimSupport:table; --AnimSidePanelSupport

local m_cityIM:table = InstanceManager:new("CityInstance", "CityButton", Controls.CityStack);

-- ===========================================================================
function Refresh()
	-- Find the selected trade unit
	local selectedUnit:table = UI.GetHeadSelectedUnit();
	if selectedUnit == nil then
		Close();
		return;
	end

	-- Find the current city
	local originCity = Cities.GetCityInPlot(selectedUnit:GetX(), selectedUnit:GetY());
	if originCity == nil then
		Close();
		return;
	end

	-- Reset Instance Manager
	m_cityIM:ResetInstances();

	-- Add all other cities to city stack
	local localPlayer = Players[Game.GetLocalPlayer()];
	local playerCities:table = localPlayer:GetCities();
	for _, city in playerCities:Members() do
		if city ~= originCity and CanTeleportToCity(city) then
			AddCity(city);
		end
	end

	-- Calculate Control Size
	Controls.CityScrollPanel:CalculateInternalSize();
	Controls.CityStack:CalculateSize();
	Controls.CityStack:ReprocessAnchoring();
end

-- ===========================================================================
function AddCity(city:table)
	local cityInstance:table = m_cityIM:GetInstance();
	cityInstance.CityButton:SetText(Locale.ToUpper(city:GetName()));
	cityInstance.CityButton:RegisterCallback(Mouse.eLClick, function() TeleportToCity(city); end);
end

-- ===========================================================================
function CanTeleportToCity(city:table)
	local tParameters = {};
	tParameters[UnitOperationTypes.PARAM_X] = city:GetX();
	tParameters[UnitOperationTypes.PARAM_Y] = city:GetY();

	local eOperation = UI.GetInterfaceModeParameter(UnitOperationTypes.PARAM_OPERATION_TYPE);

	local pSelectedUnit = UI.GetHeadSelectedUnit();
	if (UnitManager.CanStartOperation( pSelectedUnit, eOperation, nil, tParameters)) then
		return true;
	end

	return false;
end

-- ===========================================================================
function TeleportToCity(city:table)
	local tParameters = {};
	tParameters[UnitOperationTypes.PARAM_X] = city:GetX();
	tParameters[UnitOperationTypes.PARAM_Y] = city:GetY();

	local eOperation = UI.GetInterfaceModeParameter(UnitOperationTypes.PARAM_OPERATION_TYPE);

	local pSelectedUnit = UI.GetHeadSelectedUnit();
	if (UnitManager.CanStartOperation( pSelectedUnit, eOperation, nil, tParameters)) then
		UnitManager.RequestOperation( pSelectedUnit, eOperation, tParameters);
		UI.SetInterfaceMode(InterfaceModeTypes.SELECTION);
        UI.PlaySound("Unit_Relocate");
		Close();
	end
end

-- ===========================================================================
function OnInterfaceModeChanged( oldMode:number, newMode:number )
	if (oldMode == InterfaceModeTypes.TELEPORT_TO_CITY) then
		-- Only close if already open
		if m_AnimSupport:IsVisible() then
			Close();
		end
	end
	if (newMode == InterfaceModeTypes.TELEPORT_TO_CITY) then
		-- Only open if selected unit is a trade unit
		local pSelectedUnit:table = UI.GetHeadSelectedUnit();
		local pSelectedUnitInfo:table = GameInfo.Units[pSelectedUnit:GetUnitType()];
		if pSelectedUnitInfo.MakeTradeRoute then
			Open();
		end
	end
end

-- ===========================================================================
function OnCitySelectionChanged(owner, ID, i, j, k, bSelected, bEditable)
	-- Close if we select a city
	if m_AnimSupport:IsVisible() and owner == Game.GetLocalPlayer() and owner ~= -1 then
		Close();
	end
end

-- ===========================================================================
function OnUnitSelectionChanged( playerID : number, unitID : number, hexI : number, hexJ : number, hexK : number, bSelected : boolean, bEditable : boolean)
	-- Close if we select a unit
	if m_AnimSupport:IsVisible() and playerID ~= -1 and playerID == Game.GetLocalPlayer() then
		Close();
	end
end

------------------------------------------------------------------------------------------------
function OnLocalPlayerTurnEnd()
	if(GameConfiguration.IsHotseat()) then
		Close();
	end
end

-- ===========================================================================
function Open()
	LuaEvents.TradeOriginChooser_SetTradeUnitStatus("LOC_HUD_UNIT_PANEL_CHOOSING_ORIGIN_CITY");
	m_AnimSupport:Show();
	Refresh();
	SRA_ArmOpen();		-- ScreenReaderAccess
end

-- ===========================================================================
function Close()
	LuaEvents.TradeOriginChooser_SetTradeUnitStatus("");
	m_AnimSupport:Hide();
end

-- ===========================================================================
function OnOpen()
	Open();
end

-- ===========================================================================
function OnClose()
	Close();
end

-- ===========================================================================
--	HOT-RELOADING EVENTS
-- ===========================================================================
function OnInit(isReload:boolean)
	if isReload then
		LuaEvents.GameDebug_GetValues(RELOAD_CACHE_ID);
	end
end
function OnShutdown()
	SRA_RemoveListeners();		-- ScreenReaderAccess
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID, "isVisible", m_AnimSupport:IsVisible());
end
function OnGameDebugReturn(context:string, contextTable:table)
	if context == RELOAD_CACHE_ID and contextTable["isVisible"] ~= nil and contextTable["isVisible"] then
		OnOpen();
	end
end

-- ===========================================================================
--	ScreenReaderAccess: keyboard navigation and speech
--	Opens 0.4 s after Open() with "Move trader to which city? 3 cities. Florence, 5 tiles, 1 of 3". One item per city that
--	passes CanTeleportToCity (nearest first), rebuilt at every key. Enter calls the game's own TeleportToCity (what the
--	button does); the hub tells the outcome a moment later (LuaEvents.SRA_TradeResult: this context hides when the
--	trader moves). Escape closes the panel and leaves the interface mode (the game's own Escape only hid the panel).
--	Every key event is swallowed while the panel is shown.
-- ===========================================================================
local m_srList				:table = nil;
local m_srOpenPending		:boolean = false;
local m_srOpenDelay			:number = 0;
local SRA_OPEN_DELAY		:number = 0.4;

function SRA_BuildItems()
	local items:table = {};
	local unit = UI.GetHeadSelectedUnit();
	if unit == nil then return items; end
	local originCity = Cities.GetCityInPlot( unit:GetX(), unit:GetY() );
	if originCity == nil then return items; end
	local localPlayer = Players[ Game.GetLocalPlayer() ];
	local cities:table = {};
	for _, city in localPlayer:GetCities():Members() do
		if city:GetID() ~= originCity:GetID() and CanTeleportToCity( city ) then
			table.insert( cities, {
				id = city:GetID(), name = Locale.Lookup( city:GetName() ),
				distance = Map.GetPlotDistance( unit:GetX(), unit:GetY(), city:GetX(), city:GetY() ),
			} );
		end
	end
	table.sort( cities, function( a, b )
		if a.distance ~= b.distance then return a.distance < b.distance; end
		return a.name < b.name;
	end );
	for _, city in ipairs( cities ) do
		table.insert( items, { key = "c:" .. city.id, id = city.id, name = city.name, text = TradeText_Origin( city ) } );
	end
	return items;
end

function SRA_Announce()
	local items:table = SRA_BuildItems();
	local head:string = "Move trader to which city?";
	if #items == 0 then
		OutputMessageToScreenReader( head .. " No cities available. " .. SRKey( "Escape" ) .. " to cancel", true );
		return;
	end
	m_srList.Open( head, nil, true );
	local index:number = 1;
	for i, item in ipairs( items ) do
		if item.key == m_srList.GetFocusKey() then index = i; end
	end
	OutputMessageToScreenReader( head .. " " .. #items .. ( #items == 1 and " city. " or " cities. " ) .. items[ index ].text .. ", " .. index .. " of " .. #items, true );
end

-- Called at the end of Open().
function SRA_ArmOpen()
	m_srList.Reset();
	m_srOpenPending = true;
	m_srOpenDelay = SRA_OPEN_DELAY;
end

function SRA_OnUpdate( deltaTime:number )
	if not m_srOpenPending then return; end
	if ContextPtr:IsHidden() then m_srOpenPending = false; return; end
	m_srOpenDelay = m_srOpenDelay - deltaTime;
	if m_srOpenDelay > 0 then return; end
	m_srOpenPending = false;
	local ok:boolean, err = xpcall( SRA_Announce, KeyNavErrorHandler );
	if not ok then print( "TradeOriginChooser announce error: " .. tostring( err ) ); end
end

local function SRA_Teleport( item:table )
	local unit = UI.GetHeadSelectedUnit();
	local city = CityManager.GetCity( Game.GetLocalPlayer(), item.id );
	if unit == nil or city == nil then
		OutputMessageToScreenReader( "That city is no longer available" );
		return;
	end
	local unitID:number, x:number, y:number = unit:GetID(), unit:GetX(), unit:GetY();
	TeleportToCity( city );		-- closes the panel and leaves the interface mode when the move is allowed
	LuaEvents.SRA_TradeResult( "move", unitID, x, y, item.name );
end

local function SRA_Cancel()
	Close();
	if UI.GetInterfaceMode() == InterfaceModeTypes.TELEPORT_TO_CITY then
		UI.SetInterfaceMode( InterfaceModeTypes.SELECTION );
	end
	OutputMessageToScreenReader( "Cancelled" );
end

function SRA_CreateList()
	m_srList = KeyNavList_Create{
		build		= SRA_BuildItems,
		isActive	= function() return m_AnimSupport:IsVisible(); end,
		onActivate	= SRA_Teleport,
		onClose		= SRA_Cancel,
	};
end

-- Every keyboard event is swallowed while the panel is shown.
function SRA_OnInput( pInputStruct:table )
	if m_AnimSupport:IsVisible() then
		if m_srList.HandleInput( pInputStruct ) then return true; end
		local msg:number = pInputStruct:GetMessageType();
		if msg == KeyEvents.KeyDown or msg == KeyEvents.KeyUp then return true; end
	end
	return m_AnimSupport.OnInputHandler( pInputStruct );
end

-- Hot reload leaves the old instance's listeners registered: remove every one on shutdown.
function SRA_RemoveListeners()
	LuaEvents.GameDebug_Return.Remove( OnGameDebugReturn );
	Events.InterfaceModeChanged.Remove( OnInterfaceModeChanged );
	Events.CitySelectionChanged.Remove( OnCitySelectionChanged );
	Events.UnitSelectionChanged.Remove( OnUnitSelectionChanged );
	Events.LocalPlayerTurnEnd.Remove( OnLocalPlayerTurnEnd );
	Events.SystemUpdateUI.Remove( m_AnimSupport.OnUpdateUI );
end
-- End ScreenReaderAccess

-- ===========================================================================
--	INIT
-- ===========================================================================
function Initialize()
	Controls.Title:SetText(Locale.ToUpper(Locale.Lookup("LOC_UNITOPERATION_MOVE_TO_DESCRIPTION")));

	-- Hot-reload events
	ContextPtr:SetInitHandler(OnInit);
	ContextPtr:SetShutdown(OnShutdown);
	
	LuaEvents.GameDebug_Return.Add(OnGameDebugReturn);

	-- Game Engine Events	
	Events.InterfaceModeChanged.Add( OnInterfaceModeChanged );
	Events.CitySelectionChanged.Add( OnCitySelectionChanged );
	Events.UnitSelectionChanged.Add( OnUnitSelectionChanged );	
	Events.LocalPlayerTurnEnd.Add( OnLocalPlayerTurnEnd );

	-- Animation controller
	m_AnimSupport = CreateScreenAnimation(Controls.SlideAnim);

	-- Animation controller events
	Events.SystemUpdateUI.Add(m_AnimSupport.OnUpdateUI);
	ContextPtr:SetInputHandler(SRA_OnInput, true);		-- ScreenReaderAccess (was m_AnimSupport.OnInputHandler)
	ContextPtr:SetUpdate(SRA_OnUpdate);					-- ScreenReaderAccess
	SRA_CreateList();									-- ScreenReaderAccess

	-- Control Events
	Controls.CloseButton:RegisterCallback(Mouse.eLClick, OnClose);
	Controls.CloseButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
end
Initialize();