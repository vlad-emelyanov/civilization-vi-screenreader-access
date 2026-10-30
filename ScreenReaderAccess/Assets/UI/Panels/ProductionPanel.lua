-- ===========================================================================
--	Production Panel / Purchase Panel
-- ===========================================================================

include( "ToolTipHelper" );	
include( "InstanceManager" );
include( "TabSupport" );
include( "Civ6Common" );
include( "Colors") ;
include( "SupportFunctions" );
include( "AdjacencyBonusSupport");
include( "ProductionHelper" );

include("ScreenReader");
include("SRListen");		-- ScreenReaderAccess: removable listeners
include("KeyNavList");		-- ScreenReaderAccess: keyboard navigation of the item list
include("PlacementScan");		-- ScreenReaderAccess: Space on a district says where it fits best
include("DistrictAdvice");
include("ProductionText");

-- ===========================================================================
--	Constants
-- ===========================================================================
local RELOAD_CACHE_ID	:string = "ProductionPanel";
local COLOR_LOW_OPACITY	:number = UI.GetColorValueFromHexLiteral(0x3fffffff);
local HEADER_Y			:number	= 41;
local WINDOW_HEADER_Y	:number	= 150;
local TOPBAR_Y			:number	= 28;
local SEPARATOR_Y		:number	= 20;
local DISABLED_PADDING_Y:number	= 10;
local TEXTURE_BASE				:string = "UnitFlagBase_Combo";
local TEXTURE_CIVILIAN			:string = "UnitFlagCivilian_Combo";
local TEXTURE_RELIGION			:string = "UnitFlagReligion_Combo";
local TEXTURE_EMBARK			:string = "UnitFlagEmbark_Combo";
local TEXTURE_FORTIFY			:string = "UnitFlagFortify_Combo";
local TEXTURE_NAVAL				:string = "UnitFlagNaval_Combo";
local TEXTURE_SUPPORT			:string = "UnitFlagSupport_Combo";
local TEXTURE_TRADE				:string = "UnitFlagTrade_Combo";
local BUILDING_IM_PREFIX		:string = "buildingListingIM_";
local BUILDING_DRAWER_PREFIX	:string = "buildingDrawer_";
local ICON_PREFIX				:string = "ICON_";

-- Mirrored in CityPanel
local LISTMODE:table = {PRODUCTION = 1, PURCHASE_GOLD = 2, PURCHASE_FAITH = 3, PROD_QUEUE = 4};

local EXTENDED_BUTTON_HEIGHT = 60;
local DEFAULT_BUTTON_HEIGHT = 48;

local FIELD_LIST_BUILDING_SIZE_Y	:string = "fieldListBuilingSizeY";
local FIELD_LIST_WONDER_SIZE_Y		:string = "fieldListWonderSizeY";
local FIELD_LIST_UNIT_SIZE_Y		:string = "fieldListUnitSizeY";

local FIELD_DISTRICT_LIST			:string = "fieldDistrictList";
local FIELD_BUILDING_LIST			:string = "fieldBuildingList";
local FIELD_WONDER_LIST				:string = "fieldWonderList";
local FIELD_UNIT_LIST				:string = "fieldUnitList";
local FIELD_PROJECTS_LIST			:string = "fieldProjectsList";

local TXT_PRODUCTION_ITEM_REPAIR			:string = Locale.Lookup("LOC_PRODUCTION_ITEM_REPAIR");
local TXT_PRODUCTION_ITEM_DECONTAMINATE		:string = Locale.Lookup("LOC_PRODUCTION_ITEM_DECONTAMINATE");
local TXT_HUD_CITY_WILL_NOT_COMPLETE		:string = Locale.Lookup("LOC_HUD_CITY_WILL_NOT_COMPLETE");
local TXT_HUD_CITY_DISTRICT_BUILT_TT		:string = Locale.Lookup("LOC_HUD_CITY_DISTRICT_BUILT_TT")
local TXT_COST								:string = Locale.Lookup( "LOC_HUD_PRODUCTION_COST" );
local TXT_PRODUCTION						:string = Locale.Lookup( "LOC_HUD_PRODUCTION" );
local LOC_HUD_UNIT_PANEL_FLEET_SUFFIX		:string = Locale.Lookup("LOC_HUD_UNIT_PANEL_FLEET_SUFFIX");
local TXT_HUD_UNIT_PANEL_CORPS_SUFFIX		:string = Locale.Lookup("LOC_HUD_UNIT_PANEL_CORPS_SUFFIX");
local TXT_HUD_UNIT_PANEL_ARMADA_SUFFIX		:string = Locale.Lookup("LOC_HUD_UNIT_PANEL_ARMADA_SUFFIX");
local TXT_HUD_UNIT_PANEL_ARMY_SUFFIX		:string = Locale.Lookup("LOC_HUD_UNIT_PANEL_ARMY_SUFFIX");
local TXT_DISTRICT_REPAIR_LOCATION_FLOODED	:string = Locale.Lookup("LOC_DISTRICT_REPAIR_LOCATION_FLOODED");

-- ===========================================================================
--	Members
-- ===========================================================================

local m_listIM				= InstanceManager:new( "NestedList",  "Top", Controls.ProductionList );
local m_purchaseListIM		= InstanceManager:new( "NestedList",  "Top", Controls.PurchaseList );
local m_purchaseFaithListIM	= InstanceManager:new( "NestedList",  "Top", Controls.PurchaseFaithList );
local m_queueListIM			= InstanceManager:new( "NestedList",  "Top", Controls.QueueList );

local m_QueueInstanceIM = InstanceManager:new( "ProductionQueueItem", "Top" );

local m_tabs;
local m_productionTab;	-- Additional tracking of the tab control data so that we can select between graphical tabs and label tabs
local m_purchaseTab;
local m_faithTab;
local m_queueTab			:table = {};
local m_managerTab			:table = {};
local m_maxPurchaseSize		:number	= 0;
local m_TypeNames			:table	= {};
local m_kClickedInstance;

local m_showDisabled:boolean = true;
local m_kRecommendedItems:table;

local m_CurrentProductionHash = 0;
local m_PreviousProductionHash = 0;

local m_isQueueOpen:boolean = false;
local m_isManagerOpen:boolean = false;
local m_isTutorialRunning:boolean = false;

local m_selectedQueueInstance:table = nil;
local m_kSelectedQueueItem:table	= {Parent = nil, Button = nil, Index = -1};

local m_SelectedManagerIndex:number = -1;

local m_tutorialTestMode:boolean = false;

local m_hasProductionToShow:boolean = false;

local m_PlayerScrollPositions:table = {};
local m_CurrentListMode:number = -1;

-- The city whose production we're currently modifying
local m_pCity:table = nil;

-- ScreenReaderAccess (must be declared before Open/Close, see the keyboard list section further down)
local m_srActive:boolean = false;			-- the panel is open (set in Open, cleared in Close)
local m_srAnnouncePending:boolean = false;	-- announce the panel once the tab is selected
local m_srData:table = nil;					-- cached GetData() result, set by View, cleared by Open/Close
local m_srPlacementCity:number = nil;		-- id of the city that started that placement: only the same city reopening uses the key
local m_srPlacementKey:string = nil;		-- key of the district / wonder whose placement started: the panel reopened by Escape focuses it again
local m_srPending:table = nil;				-- outcome of the last Enter still to be announced

-- ===========================================================================
function toint(n)
    local s = tostring(n)
    local i, j = s:find('%.')
    if i then
        return tonumber(s:sub(1, i-1))
    else
        return n
    end
end

function onMouseOverProductionItem(message: string, disabled: boolean)
	if (disabled) then
		local disabledText = Locale.Lookup("LOC_MODS_DISABLED");
		message = disabledText .. "[NEWLINE]" .. message;
	else
		UI.PlaySound("Main_Menu_Mouse_Over");
	end

	OutputMessageToScreenReader(message);
end

------------------------------------------------------------------------------
-- Collapsible List Handling
------------------------------------------------------------------------------
function OnCollapseTheList()
	m_kClickedInstance.List:SetHide(true);			
	m_kClickedInstance.ListSlide:SetSizeY(0);
	m_kClickedInstance.ListAlpha:SetSizeY(0);
	Controls.PauseCollapseList:SetToBeginning();
	m_kClickedInstance.ListSlide:SetToBeginning();
	m_kClickedInstance.ListAlpha:SetToBeginning();
end

-- ===========================================================================
function OnCollapse(instance:table)
	m_kClickedInstance = instance;
	instance.ListSlide:Reverse();	
	instance.ListAlpha:Reverse();
	instance.ListSlide:SetSpeed(15.0);
	instance.ListAlpha:SetSpeed(15.0);
	instance.ListSlide:Play();	
	instance.ListAlpha:Play();
	instance.HeaderOn:SetHide(true);		
	instance.Header:SetHide(false);
	Controls.PauseCollapseList:Play();	--By doing this we can delay collapsing the list until the "out" sequence has finished playing
end

-- ===========================================================================
function OnExpand(instance:table)
	m_kClickedInstance = instance;
	instance.HeaderOn:SetHide(false);		
	instance.Header:SetHide(true);			
	instance.List:SetHide(false);			
	instance.ListSlide:SetSizeY(instance.List:GetSizeY());
	instance.ListAlpha:SetSizeY(instance.List:GetSizeY());
	instance.ListSlide:SetToBeginning();
	instance.ListAlpha:SetToBeginning();
	instance.ListSlide:Play();				
	instance.ListAlpha:Play();
end

-- ===========================================================================
function OnTabChangeProduction()
	CloseQueue();
	CloseManager();
	LuaEvents.ProductionPanel_IsQueueOpen(false);

	Controls.MiniProductionTab:SetSelected(true);
	Controls.MiniPurchaseTab:SetSelected(false);
	Controls.MiniPurchaseFaithTab:SetSelected(false);

	ShowProperList(LISTMODE.PRODUCTION);

	LuaEvents.ProductionPanel_ListModeChanged(LISTMODE.PRODUCTION);

	Controls.CurrentProductionContainer:SetHide(not m_hasProductionToShow);
	Controls.NoProductionContainer:SetHide(true);
	Controls.CurrentProductionButton:SetSelected(false);
	Controls.CurrentProductionButton:SetDisabled(true);
	Controls.CurrentProductionButton:SetVisState(0);

    if (Controls.SlideIn:IsStopped()) then
		UI.PlaySound("Production_Panel_ButtonClick");
        UI.PlaySound("Production_Panel_Open");
    end
end

-- ===========================================================================
function OnTabChangePurchase()
	CloseQueue();
	CloseManager();
	LuaEvents.ProductionPanel_IsQueueOpen(false);

	Controls.MiniProductionTab:SetSelected(false);
	Controls.MiniPurchaseTab:SetSelected(true);
	Controls.MiniPurchaseFaithTab:SetSelected(false);

	ShowProperList(LISTMODE.PURCHASE_GOLD);

	LuaEvents.ProductionPanel_ListModeChanged(LISTMODE.PURCHASE_GOLD);

	Controls.CurrentProductionContainer:SetHide(true);
	Controls.NoProductionContainer:SetHide(true);

	UI.PlaySound("Production_Panel_ButtonClick");
end

-- ===========================================================================
function OnTabChangePurchaseFaith()
	CloseQueue();
	CloseManager();
	LuaEvents.ProductionPanel_IsQueueOpen(false);

	Controls.MiniProductionTab:SetSelected(false);
	Controls.MiniPurchaseTab:SetSelected(false);
	Controls.MiniPurchaseFaithTab:SetSelected(true);

	ShowProperList(LISTMODE.PURCHASE_FAITH);

	LuaEvents.ProductionPanel_ListModeChanged(LISTMODE.PURCHASE_FAITH);

	Controls.CurrentProductionContainer:SetHide(true);
	Controls.NoProductionContainer:SetHide(true);

	UI.PlaySound("Production_Panel_ButtonClick");
end

-- ===========================================================================
function OnTabChangeQueue()
	OpenQueue();
	CloseManager();
	LuaEvents.ProductionPanel_IsQueueOpen(true);

	ShowProperList(LISTMODE.PROD_QUEUE);

	LuaEvents.ProductionPanel_ListModeChanged(LISTMODE.PROD_QUEUE);

	Controls.CurrentProductionContainer:SetHide(not m_hasProductionToShow);
	Controls.NoProductionContainer:SetHide(m_hasProductionToShow);
	Controls.CurrentProductionButton:SetSelected(false);
	Controls.CurrentProductionButton:SetDisabled(false);

	UI.PlaySound("Production_Panel_ButtonClick");
end

-- ===========================================================================
function OnTabChangeManager()
	CloseQueue();
	OpenManager();
	LuaEvents.ProductionPanel_IsQueueOpen(true);

	ShowProperList(LISTMODE.PROD_QUEUE);

	LuaEvents.ProductionPanel_ListModeChanged(LISTMODE.PROD_QUEUE);

	Controls.CurrentProductionContainer:SetHide(true);
	Controls.NoProductionContainer:SetHide(true);

	UI.PlaySound("Production_Panel_ButtonClick");
end

-- ===========================================================================
function ShowProperList( eListMode:number )
	m_CurrentListMode = eListMode;
	Controls.PurchaseMenu:SetHide(not (m_CurrentListMode == LISTMODE.PURCHASE_GOLD));
	Controls.PurchaseFaithMenu:SetHide(not (m_CurrentListMode == LISTMODE.PURCHASE_FAITH));
	Controls.ProductionListScroll:SetHide(not (m_CurrentListMode == LISTMODE.PRODUCTION));
	Controls.QueueListContainer:SetHide(not (m_CurrentListMode == LISTMODE.PROD_QUEUE));
end

-- ===========================================================================
-- This function should be called before starting any production
-- It blocks interaction with production list items while a current production 
-- item is selected and also deselects the previous item
-- ===========================================================================
function CheckQueueItemSelected()
	if m_kSelectedQueueItem.Index ~= -1 then
		DeselectItem();
		return true;
	end

	if m_SelectedManagerIndex ~= -1 then
		LuaEvents.ProductionPanel_ProductionClicked();
		return true;
	end

	return false;
end

-- ===========================================================================
-- Placement/Selection 
-- ===========================================================================
function BuildUnit(city, unitEntry)
	if CheckQueueItemSelected() then
		return;
	end

	local tParameters = {}; 
	tParameters[CityOperationTypes.PARAM_UNIT_TYPE] = unitEntry.Hash;
	GetBuildInsertMode(tParameters);
	CityManager.RequestOperation(city, CityOperationTypes.BUILD, tParameters);
	UI.PlaySound("Confirm_Production");
end

-- ===========================================================================
function BuildUnitCorps(city, unitEntry)
	if CheckQueueItemSelected() then
		return;
	end

	local tParameters = {};
	tParameters[CityOperationTypes.PARAM_UNIT_TYPE] = unitEntry.Hash;
	GetBuildInsertMode(tParameters);
	tParameters[CityOperationTypes.MILITARY_FORMATION_TYPE] = MilitaryFormationTypes.CORPS_MILITARY_FORMATION;
	CityManager.RequestOperation(city, CityOperationTypes.BUILD, tParameters);
	UI.PlaySound("Confirm_Production");
end

-- ===========================================================================
function BuildUnitArmy(city, unitEntry)
	if CheckQueueItemSelected() then
		return;
	end

	local tParameters = {};
	tParameters[CityOperationTypes.PARAM_UNIT_TYPE] = unitEntry.Hash;
	GetBuildInsertMode(tParameters);
	tParameters[CityOperationTypes.MILITARY_FORMATION_TYPE] = MilitaryFormationTypes.ARMY_MILITARY_FORMATION;
	CityManager.RequestOperation(city, CityOperationTypes.BUILD, tParameters);
	UI.PlaySound("Confirm_Production");
end

-- ===========================================================================
function BuildBuilding(city, buildingEntry)
	if CheckQueueItemSelected() then
		return;
	end

	local building			:table		= GameInfo.Buildings[buildingEntry.Type];
	local bNeedsPlacement	:boolean	= building.RequiresPlacement;

	UI.SetInterfaceMode(InterfaceModeTypes.SELECTION);

	local pBuildQueue = city:GetBuildQueue();
	if (pBuildQueue:HasBeenPlaced(buildingEntry.Hash)) then
		bNeedsPlacement = false;
	end

	-- If it's a Wonder and the city already has the building then it doesn't need to be replaced.
	if (bNeedsPlacement) then
		local cityBuildings = city:GetBuildings();
		if (cityBuildings:HasBuilding(buildingEntry.Hash)) then
			bNeedsPlacement = false;
		end
	end

	-- Does the building need to be placed?
	if ( bNeedsPlacement ) then			
		-- If so, set the placement mode
		local tParameters = {}; 
		tParameters[CityOperationTypes.PARAM_BUILDING_TYPE] = buildingEntry.Hash;
		GetBuildInsertMode(tParameters);
		UI.SetInterfaceMode(InterfaceModeTypes.BUILDING_PLACEMENT, tParameters);
		Close();
	else
		-- If not, add it to the queue.
		local tParameters = {}; 
		tParameters[CityOperationTypes.PARAM_BUILDING_TYPE] = buildingEntry.Hash;  
		GetBuildInsertMode(tParameters);
		CityManager.RequestOperation(city, CityOperationTypes.BUILD, tParameters);
        UI.PlaySound("Confirm_Production");
		CloseAfterNewProduction();
	end
end

-- ===========================================================================
function ZoneDistrict(city, districtEntry)
	if CheckQueueItemSelected() then
		return;
	end

	local district			:table		= GameInfo.Districts[districtEntry.Type];
	local bNeedsPlacement	:boolean	= district.RequiresPlacement;
	local pBuildQueue		:table		= city:GetBuildQueue();

	if (pBuildQueue:HasBeenPlaced(districtEntry.Hash)) then
		bNeedsPlacement = false;
	end

	-- Almost all districts need to be placed, but just in case let's check anyway
	if (bNeedsPlacement ) then			
		-- If so, set the placement mode
		local tParameters = {}; 
		tParameters[CityOperationTypes.PARAM_DISTRICT_TYPE] = districtEntry.Hash;
		GetBuildInsertMode(tParameters);
		UI.SetInterfaceMode(InterfaceModeTypes.DISTRICT_PLACEMENT, tParameters);
		Close();
	else
		-- If not, add it to the queue.
		local tParameters = {};
		tParameters[CityOperationTypes.PARAM_DISTRICT_TYPE] = districtEntry.Hash;  
		GetBuildInsertMode(tParameters);
		CityManager.RequestOperation(city, CityOperationTypes.BUILD, tParameters);
        UI.PlaySound("Confirm_Production");
		CloseAfterNewProduction();
	end
end

-- ===========================================================================
function AdvanceProject(city, projectEntry)
	if CheckQueueItemSelected() then
		return;
	end

	local tParameters = {}; 
	tParameters[CityOperationTypes.PARAM_PROJECT_TYPE] = projectEntry.Hash;
	GetBuildInsertMode(tParameters);
	CityManager.RequestOperation(city, CityOperationTypes.BUILD, tParameters);
    UI.PlaySound("Confirm_Production");
end

-- ===========================================================================
function PurchaseUnit(city, unitEntry)
	local tParameters = {};
	tParameters[CityCommandTypes.PARAM_UNIT_TYPE] = unitEntry.Hash;
	tParameters[CityCommandTypes.PARAM_MILITARY_FORMATION_TYPE] = MilitaryFormationTypes.STANDARD_MILITARY_FORMATION;
	if (unitEntry.Yield == "YIELD_GOLD") then
		tParameters[CityCommandTypes.PARAM_YIELD_TYPE] = GameInfo.Yields["YIELD_GOLD"].Index;
		UI.PlaySound("Purchase_With_Gold");
	else
		tParameters[CityCommandTypes.PARAM_YIELD_TYPE] = GameInfo.Yields["YIELD_FAITH"].Index;	
		UI.PlaySound("Purchase_With_Faith");
	end
	CityManager.RequestCommand(city, CityCommandTypes.PURCHASE, tParameters);
end

-- ===========================================================================
function PurchaseUnitCorps(city, unitEntry)
	local tParameters = {};
	tParameters[CityCommandTypes.PARAM_UNIT_TYPE] = unitEntry.Hash;
	tParameters[CityCommandTypes.PARAM_MILITARY_FORMATION_TYPE] = MilitaryFormationTypes.CORPS_MILITARY_FORMATION;
	if (unitEntry.Yield == "YIELD_GOLD") then
		tParameters[CityCommandTypes.PARAM_YIELD_TYPE] = GameInfo.Yields["YIELD_GOLD"].Index;
		UI.PlaySound("Purchase_With_Gold");
	else
		tParameters[CityCommandTypes.PARAM_YIELD_TYPE] = GameInfo.Yields["YIELD_FAITH"].Index;	
		UI.PlaySound("Purchase_With_Faith");
	end
	CityManager.RequestCommand(city, CityCommandTypes.PURCHASE, tParameters);
end

-- ===========================================================================
function PurchaseUnitArmy(city, unitEntry)
	local tParameters = {};
	tParameters[CityCommandTypes.PARAM_UNIT_TYPE] = unitEntry.Hash;
	tParameters[CityCommandTypes.PARAM_MILITARY_FORMATION_TYPE] = MilitaryFormationTypes.ARMY_MILITARY_FORMATION;
	if (unitEntry.Yield == "YIELD_GOLD") then
		tParameters[CityCommandTypes.PARAM_YIELD_TYPE] = GameInfo.Yields["YIELD_GOLD"].Index;
		UI.PlaySound("Purchase_With_Gold");
	else
		tParameters[CityCommandTypes.PARAM_YIELD_TYPE] = GameInfo.Yields["YIELD_FAITH"].Index;	
		UI.PlaySound("Purchase_With_Faith");
	end
	CityManager.RequestCommand(city, CityCommandTypes.PURCHASE, tParameters);
end

-- ===========================================================================
function PurchaseBuilding(city, buildingEntry)
	local tParameters = {};
	tParameters[CityCommandTypes.PARAM_BUILDING_TYPE] = buildingEntry.Hash;
	if (buildingEntry.Yield == "YIELD_GOLD") then
		tParameters[CityCommandTypes.PARAM_YIELD_TYPE] = GameInfo.Yields["YIELD_GOLD"].Index;
		UI.PlaySound("Purchase_With_Gold");
	else
		tParameters[CityCommandTypes.PARAM_YIELD_TYPE] = GameInfo.Yields["YIELD_FAITH"].Index;	
		UI.PlaySound("Purchase_With_Faith");
	end
	CityManager.RequestCommand(city, CityCommandTypes.PURCHASE, tParameters);
end

-- ===========================================================================
function PurchaseDistrict(city, districtEntry)
	local district			:table		= GameInfo.Districts[districtEntry.Type];
	local bNeedsPlacement	:boolean	= district.RequiresPlacement;
	local pBuildQueue		:table		= city:GetBuildQueue();

	if (pBuildQueue:HasBeenPlaced(districtEntry.Hash)) then
		bNeedsPlacement = false;
	end

	-- Almost all districts need to be placed, but just in case let's check anyway
	if (bNeedsPlacement ) then			
		-- If so, set the placement mode
		if(districtEntry.Yield == "YIELD_GOLD") then
			local tParameters = {}; 
			tParameters[CityOperationTypes.PARAM_DISTRICT_TYPE] = districtEntry.Hash;
			tParameters[CityCommandTypes.PARAM_YIELD_TYPE] = GameInfo.Yields["YIELD_GOLD"].Index;
			UI.SetInterfaceMode(InterfaceModeTypes.DISTRICT_PLACEMENT, tParameters);
		else
			local tParameters = {}; 
			tParameters[CityOperationTypes.PARAM_DISTRICT_TYPE] = districtEntry.Hash;
			tParameters[CityCommandTypes.PARAM_YIELD_TYPE] = GameInfo.Yields["YIELD_FAITH"].Index;
			UI.SetInterfaceMode(InterfaceModeTypes.DISTRICT_PLACEMENT, tParameters);
		end
	else
		if(districtEntry.Yield == "YIELD_GOLD") then
			-- If not, add it to the queue.
			local tParameters = {}; 
			tParameters[CityOperationTypes.PARAM_DISTRICT_TYPE] = districtEntry.Hash;
			tParameters[CityCommandTypes.PARAM_YIELD_TYPE] = GameInfo.Yields["YIELD_GOLD"].Index;  
			CityManager.RequestCommand(city, CityCommandTypes.PURCHASE, tParameters);
			UI.PlaySound("Purchase_With_Gold");
		else
			-- If not, add it to the queue.
			local tParameters = {}; 
			tParameters[CityOperationTypes.PARAM_DISTRICT_TYPE] = districtEntry.Hash;
			tParameters[CityCommandTypes.PARAM_YIELD_TYPE] = GameInfo.Yields["YIELD_FAITH"].Index;  
			CityManager.RequestCommand(city, CityCommandTypes.PURCHASE, tParameters);
			UI.PlaySound("Purchase_With_Faith");
		end
	end
end

-- ===========================================================================
--	GAME Event
--	City was selected.
-- ===========================================================================
function OnCitySelectionChanged( owner:number, cityID:number, i, j, k, isSelected:boolean, isEditable:boolean)
	local localPlayerId:number = Game.GetLocalPlayer();
	if owner == localPlayerId and isSelected then
		-- Already open then populate with newly selected city's data...
		if (ContextPtr:IsHidden() == false) and Controls.PauseDismissWindow:IsStopped() and Controls.AlphaIn:IsStopped() then
			Refresh();
		end
	end
end

-- ===========================================================================
--	GAME Event
--	eOldMode, mode the engine was formally in
--	eNewMode, new mode the engine has just changed to
-- ===========================================================================
function OnInterfaceModeChanged( eOldMode:number, eNewMode:number )	
	
	-- If this is raised while the city panel is up; selecting to purchase a
	-- plot or manage citizens will close it.
	if eNewMode == InterfaceModeTypes.CITY_MANAGEMENT or eNewMode == InterfaceModeTypes.VIEW_MODAL_LENS then
		if not ContextPtr:IsHidden() then
			Close();
		end
	end
end

-- ===========================================================================
--	GAME Event
--	Unit was selected (impossible for a production panel to be up; close it 
-- ===========================================================================
function OnUnitSelectionChanged( playerID : number, unitID : number, hexI : number, hexJ : number, hexK : number, bSelected : boolean, bEditable : boolean )
	local localPlayer = Game.GetLocalPlayer();
	if playerID == localPlayer then
		-- If a unit is selected and this is showing; hide it.
		local pSelectedUnit:table = UI.GetHeadSelectedUnit();
		if pSelectedUnit ~= nil and not ContextPtr:IsHidden() then 
			Close();
		end
	end
end

-- ===========================================================================
--	Actual closing function, may have been called via click, keyboard input,
--	or an external system call.
-- ===========================================================================
function Close()
	if (Controls.SlideIn:IsStopped()) then			-- Need to check to make sure that we have not already begun the transition before attempting to close the panel.
		m_srActive = false;							-- ScreenReaderAccess
		m_srPlacementKey = nil;						-- ScreenReaderAccess
		m_srAnnouncePending = false;				-- ScreenReaderAccess
		m_srData = nil;								-- ScreenReaderAccess
		UI.PlaySound("Production_Panel_Closed");
		Controls.SlideIn:Reverse();	
		Controls.AlphaIn:Reverse();
		Controls.PauseDismissWindow:Play();
		LuaEvents.ProductionPanel_CloseManager();
		LuaEvents.ProductionPanel_Close();
	end
end

-- ===========================================================================
--	Close via click
function OnClose()
	Close();
end

-- ===========================================================================
--	Open the panel
-- ===========================================================================
function Open()
	-- Update the selected city before anything else happens so everything updates properly
	m_pCity = UI.GetHeadSelectedCity();
	if m_pCity == nil then
		UI.DataError("Attempted to open the production panel without a city selected.");
		return;
	end

	if ContextPtr:IsHidden() then					-- The ContextPtr is only hidden as a callback to the finished SlideIn animation, so this check should be sufficient to ensure that we are not animating.
		-- Sets up proper selection AND the associated lens so it's not stuck "on".
		UI.PlaySound("Production_Panel_Open");
		m_srActive = true;						-- ScreenReaderAccess
		m_srAnnouncePending = true;				-- ScreenReaderAccess
		m_srData = nil;							-- ScreenReaderAccess
		m_srPending = nil;						-- ScreenReaderAccess
		-- ScreenReaderAccess: an open city overview (CityPanelOverview) would swallow the first Escape (its own input handler
		-- closes the overview silently), so the production panel would seem to ignore it. Close the overview first.
		LuaEvents.CityPanel_ShowOverviewPanel( false );
		LuaEvents.ProductionPanel_Open();
		UI.SetInterfaceMode(InterfaceModeTypes.SELECTION);
		Refresh();
		ContextPtr:SetHide(false);

		-- Size the panel to the maximum Y value of the expanded content	
		Controls.AlphaIn:SetToBeginning();
		Controls.SlideIn:SetToBeginning();
		Controls.AlphaIn:Play();
		Controls.SlideIn:Play();
	end
end

-- ===========================================================================
function OnHide()	
	ContextPtr:SetHide(true);
	Controls.PauseDismissWindow:SetToBeginning();
end

-- ===========================================================================
function UpdateQueueTabText( queueSize:number )
	Controls.QueueTab:SetText("[ICON_ProductionQueue] " .. Locale.Lookup("LOC_PRODUCTION_PANEL_QUEUE_WITH_COUNT", queueSize));
end

-- ===========================================================================
--	Initialize, Refresh, Populate, View
--	Update the layout based on the view model
-- ===========================================================================
function View(data)
	m_srData = data;		-- ScreenReaderAccess
	local pSelectedCity	= UI.GetHeadSelectedCity();

	-- Get the hashes for the top three recommended items
	-- Convert to a BuildItemHash indexed table for easier look up
	m_kRecommendedItems = {};
	for _,kItem in ipairs(pSelectedCity:GetCityAI():GetBuildRecommendations()) do
		m_kRecommendedItems[kItem.BuildItemHash] = kItem.BuildItemScore;
	end

	-- TODO there is a ton of duplicated code between producing, buying with gold, and buying with faith
	-- there is also a ton of duplicated code between districts, buildings, units, wonders, etc
	-- I think this could be a prime candidate for a refactor if there is time, currently, care must
	-- be taken to copy any changes in several places to keep it functioning consistently
	
	PopulateList(data, LISTMODE.PRODUCTION, m_listIM);
	Controls.ProductionListScroll:SetScrollValue(GetScrollPosition(LISTMODE.PRODUCTION));
	PopulateList(data, LISTMODE.PURCHASE_GOLD, m_purchaseListIM);
	Controls.PurchaseListScroll:SetScrollValue(GetScrollPosition(LISTMODE.PURCHASE_GOLD));
	PopulateList(data, LISTMODE.PURCHASE_FAITH, m_purchaseFaithListIM);
	Controls.PurchaseFaithListScroll:SetScrollValue(GetScrollPosition(LISTMODE.PURCHASE_FAITH));
	PopulateList(data, LISTMODE.PROD_QUEUE, m_queueListIM);
	Controls.QueueListScroll:SetScrollValue(GetScrollPosition(LISTMODE.PROD_QUEUE));

	if m_isTutorialRunning or m_tutorialTestMode then
		Controls.QueueContainer:SetHide(true);
		Controls.ScrollToButtonContainer:SetHide(true);
	end

	RefreshQueue(data.Owner, data.City:GetID())
	
	Controls.PurchaseList:CalculateSize();
	if( Controls.PurchaseList:GetSizeY() == 0 ) then
		Controls.NoGoldContent:SetHide(false);
	else
		Controls.NoGoldContent:SetHide(true);
	end

	Controls.PurchaseFaithList:CalculateSize();
	if( Controls.PurchaseFaithList:GetSizeY() == 0 ) then
		Controls.NoFaithContent:SetHide(false);
	else
		Controls.NoFaithContent:SetHide(true);
	end
end

-- ===========================================================================
function ResetInstanceVisibility(productionItem: table)
	if (productionItem.ArmyCorpsDrawer ~= nil) then
		productionItem.ArmyCorpsDrawer:SetHide(true);
		productionItem.CorpsArmyArrow:SetSelected(true);
		productionItem.CorpsRecommendedIcon:SetHide(true);
		productionItem.CorpsButtonContainer:SetHide(true);
		productionItem.CorpsDisabled:SetHide(true);
		productionItem.ArmyRecommendedIcon:SetHide(true);
		productionItem.ArmyButtonContainer:SetHide(true);
		productionItem.ArmyDisabled:SetHide(true);
		productionItem.CorpsArmyDropdownArea:SetHide(true);
	end
	if (productionItem.BuildingDrawer ~= nil) then
		productionItem.BuildingDrawer:SetHide(true);
		productionItem.CompletedArea:SetHide(true);
	end
	productionItem.RecommendedIcon:SetHide(true);
	productionItem.Disabled:SetHide(true);
end

-- ===========================================================================
function ResizeProductionScrollList()
	local contentOffset:number = Controls.TabContainer:GetSizeY() + Controls.TabContainer:GetOffsetY();
	Controls.WindowContent:SetOffsetY(contentOffset);

	local contentSize:number = Controls.ProductionPanel:GetSizeY() - contentOffset;
	Controls.WindowContent:SetSizeY(contentSize);

	local scrollSize:number = contentSize - Controls.TopStackContainer:GetSizeY();
	Controls.ProductionListScroll:SetSizeY(scrollSize);
	Controls.QueueListScroll:SetSizeY(scrollSize);
	Controls.PurchaseListScroll:SetSizeY(scrollSize);
	Controls.PurchaseFaithListScroll:SetSizeY(scrollSize);
end

-- ===========================================================================
function OnTopStackContainerSizeChanged()
	ResizeProductionScrollList();
end

-- ===========================================================================
function OnTabContainerSizeChanged()
	ResizeProductionScrollList();
end

-- ===========================================================================
function PopulateGenericItemData( kInstance:table, kItem:table )
	ResetInstanceVisibility(kInstance);

	-- Recommended check
	if m_kRecommendedItems[kItem.Hash] ~= nil then
		kInstance.RecommendedIcon:SetHide(false);
	end
	
	-- Item Name
	local sName:string = Locale.Lookup(kItem.Name);
	if (kItem.Repair) then
		sName = sName .. "[NEWLINE]" .. TXT_PRODUCTION_ITEM_REPAIR;
	end
		
	kInstance.LabelText:SetText(sName);

	-- Tooltips
	kInstance.Button:SetToolTipString(kItem.ToolTip);
	kInstance.Disabled:SetToolTipString(kItem.ToolTip);

	-- Icon
	kInstance.Icon:SetIcon(ICON_PREFIX..kItem.Type);

	-- Is item disabled?
	if (kItem.Disabled) then 
		if(m_showDisabled) then
			kInstance.Disabled:SetHide(false);
			kInstance.Button:SetColor(COLOR_LOW_OPACITY);
		else
			kInstance.Button:SetHide(true);
		end
	else
		kInstance.Button:SetHide(false);
		kInstance.Disabled:SetHide(true);
		kInstance.Button:SetColor(UI.GetColorValue("COLOR_WHITE"));
	end
	kInstance.Button:SetDisabled(kItem.Disabled);

	-- Begin ScreenReaderAccess change
	kInstance.Button:RegisterCallback( Mouse.eMouseEnter,	function() onMouseOverProductionItem(kItem.ToolTip, kItem.Disabled); end);
	-- End ScreenReaderAccess change
end

-- ===========================================================================
function PopulateGenericBuildData( kInstance:table, kItem:table )
	PopulateGenericItemData(kInstance, kItem);

	-- Progress
	if kItem.Progress > 0 then
		local iItemProgress:number = kItem.Progress/kItem.Cost;
		if iItemProgress < 1 then
			kInstance.ProductionProgress:SetPercent(iItemProgress);
			kInstance.ProductionProgressArea:SetHide(false);
		else
			kInstance.ProductionProgressArea:SetHide(true);
		end
	else
		kInstance.ProductionProgressArea:SetHide(true);
	end
end

-- ===========================================================================
function PopulateGenericPurchaseData( kInstance:table, kItem:table )
	PopulateGenericItemData(kInstance, kItem);

	kInstance.ProductionProgressArea:SetHide(true);
end

-- ===========================================================================
function PopulateCurrentProduction(data:table)
	m_hasProductionToShow = RefreshCurrentProduction( Controls, data.Owner, data.City:GetID() );
end

-- ===========================================================================
function PopulateWonders(data:table, listMode:number, listIM:table)
	local wonderList = listIM:GetInstance();
	
	local sHeaderText:string = Locale.ToUpper("LOC_HUD_CITY_WONDERS");
	wonderList.Header:SetText(sHeaderText);
	wonderList.HeaderOn:SetText(sHeaderText);
	
	if ( wonderList.wonderListIM ~= nil ) then
		wonderList.wonderListIM:ResetInstances()
	else
		wonderList.wonderListIM = InstanceManager:new( "BuildingListInstance", "Root", wonderList.List);
	end
		
	for i, item in ipairs(data.BuildingItems) do
		if(item.IsWonder) then
			local wonderListing = wonderList.wonderListIM:GetInstance();

			PopulateGenericBuildData(wonderListing, item);

			local turnsStrTT:string = "";
			local turnsStr:string = "";
			local numberOfTurns = item.TurnsLeft;
			if numberOfTurns == -1 then
				numberOfTurns = "999+";
				turnsStrTT = TXT_HUD_CITY_WILL_NOT_COMPLETE;
			else
				turnsStrTT = numberOfTurns .. Locale.Lookup("LOC_HUD_CITY_TURNS_TO_COMPLETE", item.TurnsLeft);
			end
			turnsStr = numberOfTurns .. "[ICON_Turn]";
			wonderListing.CostText:SetText(turnsStr);
			wonderListing.CostText:SetToolTipString(turnsStrTT);

            wonderListing.Button:RegisterCallback( Mouse.eMouseEnter,	function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
			wonderListing.Button:RegisterCallback( Mouse.eLClick, function()
				BuildBuilding(data.City, item);
			end);

			if not m_isTutorialRunning then
				wonderListing.Button:RegisterCallback( Mouse.eRClick, function()
					RightClickProductionItem(item.Type);
				end);
			else
				wonderListing.Button:SetTag(UITutorialManager:GetHash(item.Type));
			end	
		end
	end
		
	if (wonderList.wonderListIM.m_iAllocatedInstances <= 0) then
		wonderList.Top:SetHide(true);
	else		
        wonderList.Header:RegisterCallback( Mouse.eMouseEnter,	function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
		wonderList.Header:RegisterCallback( Mouse.eLClick, function()
			OnExpand(wonderList);					
			end);
        wonderList.HeaderOn:RegisterCallback( Mouse.eMouseEnter,	function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
		wonderList.HeaderOn:RegisterCallback( Mouse.eLClick, function()
			OnCollapse(wonderList);					
			end);
	end

	wonderList.Top:RegisterSizeChanged(function() OnWonderListSizeChanged(listIM, wonderList.Top:GetSizeY()); end);
	OnWonderListSizeChanged(listIM, wonderList.Top:GetSizeY());

	OnExpand(wonderList);
end

-- ===========================================================================
function PopulateProjects(data:table, listMode:number, listIM:table)
	local projectList = listIM:GetInstance();

	local sHeaderText:string = Locale.ToUpper("LOC_HUD_PROJECTS");
	projectList.Header:SetText(sHeaderText);
	projectList.HeaderOn:SetText(sHeaderText);

	if ( projectList.projectListIM ~= nil ) then
		projectList.projectListIM:ResetInstances();
	else
		projectList.projectListIM = InstanceManager:new( "ProjectListInstance", "Root", projectList.List);
	end

	for i, item in ipairs(data.ProjectItems) do
		if item.IsCurrentProduction == false or (listMode == LISTMODE.PROD_QUEUE and item.IsRepeatable) then
			local projectListing = projectList.projectListIM:GetInstance();

			PopulateGenericBuildData(projectListing, item);

			local numberOfTurns = item.TurnsLeft;
			if numberOfTurns == -1 then
				numberOfTurns = "999+";
			end;

			local turnsStr = numberOfTurns .. "[ICON_Turn]";
			projectListing.CostText:SetText(turnsStr);

			projectListing.Button:RegisterCallback( Mouse.eLClick, function()
				AdvanceProject(data.City, item);
				CloseAfterNewProduction();
			end);

			if not m_isTutorialRunning then
				projectListing.Button:RegisterCallback( Mouse.eRClick, function()
					RightClickProductionItem(item.Type);
				end);
			else
				projectListing.Button:SetTag(UITutorialManager:GetHash(item.Type));
			end
		end
	end
		
	if (projectList.projectListIM.m_iAllocatedInstances <= 0) then
		projectList.Top:SetHide(true);
	else
		projectList.Header:RegisterCallback( Mouse.eLClick, function()
			OnExpand(projectList);					
			end);
		projectList.HeaderOn:RegisterCallback( Mouse.eLClick, function()
			OnCollapse(projectList);					
			end);
	end

	OnExpand(projectList);
end

-- ===========================================================================
function PopulateDistrictsWithNestedBuildings(data:table, listMode:number, listIM:table)
	local districtList = listIM:GetInstance();
	
	local sHeaderText:string = Locale.ToUpper("LOC_HUD_DISTRICTS_BUILDINGS");
	districtList.Header:SetText(sHeaderText);
	districtList.HeaderOn:SetText(sHeaderText);

	if ( districtList.districtListIM ~= nil ) then
		districtList.districtListIM:ResetInstances();
	else
		districtList.districtListIM = InstanceManager:new( "DistrictListInstance", "Root", districtList.List);	
	end

	-- In the interest of performance, we're keeping the instances that we created and resetting the data.
	-- This requires a little bit of footwork to remember the instances that have been modified and to manually reset them.
	for _,type in ipairs(m_TypeNames) do
		local sBuildingIM:string = BUILDING_IM_PREFIX..type;
		if ( districtList[sBuildingIM] ~= nil) then		--Reset the states for the building instance managers 
			districtList[sBuildingIM]:ResetInstances();
		end
		local sBuildingDrawer:string = BUILDING_DRAWER_PREFIX..type;
		if ( districtList[sBuildingDrawer] ~= nil) then	--Reset the states of the drawers
			districtList[sBuildingDrawer]:SetHide(true);
		end
	end

	for i, item in ipairs(data.DistrictItems) do
		local districtListing = districtList.districtListIM:GetInstance();

		PopulateGenericBuildData(districtListing, item);

		local turnsStrTT:string = "";
		local turnsStr:string = "";

		if(item.HasBeenBuilt and GameInfo.Districts[item.Type].OnePerCity == true and not item.Repair and not item.Contaminated and item.Progress == 0 and item.IsComplete == true) then
			turnsStrTT = TXT_HUD_CITY_DISTRICT_BUILT_TT;
			turnsStr = "[ICON_Checkmark]";
		elseif item.ContaminatedTurns > 0 then
			turnsStrTT = Locale.Lookup("LOC_TOOLTIP_PLOT_CONTAMINATED_TEXT", item.ContaminatedTurns);
			turnsStr = item.TurnsLeft .. "[ICON_Turn]";
		else
			local numberOfTurns = item.TurnsLeft;
			if numberOfTurns == -1 then
				numberOfTurns = "999+";
				turnsStrTT = TXT_HUD_CITY_WILL_NOT_COMPLETE;
			else
				turnsStrTT = numberOfTurns .. Locale.Lookup("LOC_HUD_CITY_TURNS_TO_COMPLETE", item.TurnsLeft);
			end
			turnsStr = numberOfTurns .. "[ICON_Turn]";
		end
			
		districtListing.CostText:SetToolTipString(turnsStrTT);
		districtListing.CostText:SetText(turnsStr);

		local districtType = item.Type;
		-- Check to see if this is a unique district that will be substituted for another kind of district
		if(GameInfo.DistrictReplaces[item.Type] ~= nil) then
			districtType = 	GameInfo.DistrictReplaces[item.Type].ReplacesDistrictType;
		end
		local uniqueBuildingIMName = BUILDING_IM_PREFIX..districtType;
		local uniqueBuildingAreaName = BUILDING_DRAWER_PREFIX..districtType;

		table.insert(m_TypeNames, districtType);

		if districtList[uniqueBuildingIMName] == nil then
			districtList[uniqueBuildingIMName] = InstanceManager:new( "BuildingListInstance", "Root", districtListing.BuildingStack);
		else
			districtList[uniqueBuildingIMName]:ResetInstances();
			districtList[uniqueBuildingIMName].m_ParentControl = districtListing.BuildingStack;
		end

		districtList[uniqueBuildingAreaName] = districtListing.BuildingDrawer;
		districtListing.CompletedArea:SetHide(true);

		if (item.Disabled) then 
			if(item.HasBeenBuilt and GameInfo.Districts[item.Type].OnePerCity == true and not item.Repair) then
				districtListing.CompletedArea:SetHide(false);
				districtListing.Disabled:SetHide(true);
			end
		end

		districtListing.Button:RegisterCallback( Mouse.eMouseEnter,	function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
		districtListing.Button:RegisterCallback( Mouse.eLClick, function()
			ZoneDistrict(data.City, item);
		end);

		if not m_isTutorialRunning then
			districtListing.Button:RegisterCallback( Mouse.eRClick, function()
				RightClickProductionItem(item.Type);
			end);
		else
			districtListing.Root:SetTag(UITutorialManager:GetHash(item.Type));
		end	
	end

	if (districtList.districtListIM.m_iAllocatedInstances <= 0) then
		districtList.Top:SetHide(true);
	else
		districtList.Header:RegisterCallback( Mouse.eLClick, function()
			OnExpand(districtList);					
			end);
        districtList.Header:RegisterCallback( Mouse.eMouseEnter,	function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
		districtList.HeaderOn:RegisterCallback( Mouse.eLClick, function()
			OnCollapse(districtList);					
			end);
        districtList.HeaderOn:RegisterCallback(	Mouse.eMouseEnter,	function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	end

	-- Populate Nested Buildings -----------------
			
	for i, buildingItem in ipairs(data.BuildingItems) do
		if(not buildingItem.IsWonder) then
			local uniqueDrawerName = BUILDING_DRAWER_PREFIX..buildingItem.PrereqDistrict;
			local uniqueIMName = BUILDING_IM_PREFIX..buildingItem.PrereqDistrict;
			local pDistrictBuildingIM:table = districtList[uniqueIMName];
			if (pDistrictBuildingIM ~= nil) then

				local buildingListing = pDistrictBuildingIM:GetInstance();

				PopulateGenericBuildData(buildingListing, buildingItem);

				buildingListing.Root:SetSizeX(305);
				buildingListing.Button:SetSizeX(305);
				local districtBuildingAreaControl = districtList[uniqueDrawerName];
				districtBuildingAreaControl:SetHide(false);

				local turnsStrTT:string = "";
				local turnsStr:string = "";
				local numberOfTurns = buildingItem.TurnsLeft;
				if numberOfTurns == -1 then
					numberOfTurns = "999+";
					turnsStrTT = TXT_HUD_CITY_WILL_NOT_COMPLETE;
				else
					turnsStrTT = numberOfTurns .. Locale.Lookup("LOC_HUD_CITY_TURNS_TO_COMPLETE", buildingItem.TurnsLeft);
				end
				turnsStr = numberOfTurns .. "[ICON_Turn]";
				buildingListing.CostText:SetToolTipString(turnsStrTT);
				buildingListing.CostText:SetText(turnsStr);

                buildingListing.Button:RegisterCallback( Mouse.eMouseEnter,	function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
				buildingListing.Button:RegisterCallback( Mouse.eLClick, function()
					BuildBuilding(data.City, buildingItem);
				end);

				if not m_isTutorialRunning then
					buildingListing.Button:RegisterCallback( Mouse.eRClick, function()
						RightClickProductionItem(buildingItem.Type);
					end);
				else
					buildingListing.Button:SetTag(UITutorialManager:GetHash(buildingItem.Type));
				end	
			end
		end
	end

	districtList.Top:RegisterSizeChanged( function() OnBuildingListSizeChanged(listIM, districtList.Top:GetSizeY()); end);
	OnBuildingListSizeChanged(listIM, districtList.Top:GetSizeY());

	OnExpand(districtList);
end

-- ===========================================================================
function PopulateDistrictsWithoutNestedBuildings(data:table, listMode:number, listIM:table)
	local districtList = listIM:GetInstance();

	local sHeaderText:string = Locale.ToUpper("LOC_HUD_DISTRICTS");
	districtList.Header:SetText(sHeaderText);
	districtList.HeaderOn:SetText(sHeaderText);

	if ( districtList.districtListIM ~= nil) then
		districtList.districtListIM:ResetInstances();
	else
		districtList.districtListIM = InstanceManager:new( "DistrictListInstance", "Root", districtList.List);
	end

	for i, item in ipairs(data.DistrictPurchases) do
		if ((item.Yield == "YIELD_GOLD" and listMode == LISTMODE.PURCHASE_GOLD) or (item.Yield == "YIELD_FAITH" and listMode == LISTMODE.PURCHASE_FAITH)) then
			local districtListing = districtList.districtListIM:GetInstance();

			PopulateGenericPurchaseData(districtListing, item);

			local costStr;
			if (item.Yield == "YIELD_GOLD") then
				costStr = Locale.Lookup("LOC_PRODUCTION_PURCHASE_GOLD_TEXT", item.Cost);
			else
				costStr = Locale.Lookup("LOC_PRODUCTION_PURCHASE_FAITH_TEXT", item.Cost);
			end
			if (item.CantAfford) then
				costStr = "[COLOR:Red]" .. costStr .. "[ENDCOLOR]";
			end

			districtListing.CostText:SetText(costStr);

			districtListing.Button:RegisterCallback( Mouse.eMouseEnter,	function() UI.PlaySound("Main_Menu_Mouse_Over"); end);

			districtListing.Button:RegisterCallback( Mouse.eLClick, function()
					PurchaseDistrict(data.City, item);
					Close();
				end);

		end
	end

	if (districtList.districtListIM.m_iAllocatedInstances <= 0) then
		districtList.Top:SetHide(true);
	else
		m_maxPurchaseSize = m_maxPurchaseSize + HEADER_Y + SEPARATOR_Y;
        districtList.Header:RegisterCallback( Mouse.eMouseEnter,	function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
		districtList.Header:RegisterCallback( Mouse.eLClick, function()
			OnExpand(districtList);					
			end);
        districtList.HeaderOn:RegisterCallback( Mouse.eMouseEnter,	function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
		districtList.HeaderOn:RegisterCallback( Mouse.eLClick, function()
			OnCollapse(districtList);					
			end);
	end

	OnExpand(districtList);

	-- Populate Buildings ------------------------
	local buildingList = listIM:GetInstance();

	local sHeaderText:string = Locale.ToUpper("LOC_HUD_BUILDINGS");
	buildingList.Header:SetText(sHeaderText);
	buildingList.HeaderOn:SetText(sHeaderText);

	if ( buildingList.buildingListIM ~= nil ) then
		buildingList.buildingListIM:ResetInstances();
	else
		buildingList.buildingListIM = InstanceManager:new( "BuildingListInstance", "Root", buildingList.List);
	end

	for i, item in ipairs(data.BuildingPurchases) do
		if ((item.Yield == "YIELD_GOLD" and listMode == LISTMODE.PURCHASE_GOLD) or (item.Yield == "YIELD_FAITH" and listMode == LISTMODE.PURCHASE_FAITH)) then
			local buildingListing = buildingList.buildingListIM:GetInstance();

			PopulateGenericPurchaseData(buildingListing, item);

			local costStr;
			if (item.Yield == "YIELD_GOLD") then
				costStr = Locale.Lookup("LOC_PRODUCTION_PURCHASE_GOLD_TEXT", item.Cost);
			else
				costStr = Locale.Lookup("LOC_PRODUCTION_PURCHASE_FAITH_TEXT", item.Cost);
			end
			if item.CantAfford then
				costStr = "[COLOR:Red]" .. costStr .. "[ENDCOLOR]";
			end

			buildingListing.CostText:SetText(costStr);

			if not m_isTutorialRunning then
				buildingListing.Button:RegisterCallback( Mouse.eRClick, function()
					RightClickProductionItem(item.Type);
				end);
			end

            buildingListing.Button:RegisterCallback( Mouse.eMouseEnter,	function() UI.PlaySound("Main_Menu_Mouse_Over"); end);

			buildingListing.Button:RegisterCallback( Mouse.eLClick, function()
					PurchaseBuilding(data.City, item);
					Close();
				end);
			end
	end

	if (buildingList.buildingListIM.m_iAllocatedInstances <= 0) then
		buildingList.Top:SetHide(true);
	else
		m_maxPurchaseSize = m_maxPurchaseSize + HEADER_Y + SEPARATOR_Y;
        buildingList.Header:RegisterCallback( Mouse.eMouseEnter,	function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
		buildingList.Header:RegisterCallback( Mouse.eLClick, function()
			OnExpand(buildingList);					
			end);
        buildingList.HeaderOn:RegisterCallback( Mouse.eMouseEnter,	function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
		buildingList.HeaderOn:RegisterCallback( Mouse.eLClick, function()
			OnCollapse(buildingList);					
			end);
	end

	districtList.Top:RegisterSizeChanged( function() OnBuildingListSizeChanged(listIM, districtList.Top:GetSizeY()); end);
	OnBuildingListSizeChanged(listIM, districtList.Top:GetSizeY());

	OnExpand(buildingList);
end

-- ===========================================================================
function GetTurnsToCompleteStrings( turnsToComplete:number )
	local turnsStr:string = "";
	local turnsStrTT:string = "";

	if turnsToComplete == -1 then
		turnsStr = "999+[ICON_Turn]";
		turnsStrTT = TXT_HUD_CITY_WILL_NOT_COMPLETE;
	else
		turnsStr = turnsToComplete .. "[ICON_Turn]";
		turnsStrTT = turnsToComplete .. Locale.Lookup("LOC_HUD_CITY_TURNS_TO_COMPLETE", turnsToComplete);
	end
	
	return turnsStr, turnsStrTT;
end

-- ===========================================================================
function PopulateUnits(data:table, listMode:number, listIM:table)
	local unitList = listIM:GetInstance();
	
	local primaryColor, secondaryColor  = UI.GetPlayerColors( Game.GetLocalPlayer() );
	
	local sHeaderText:string = Locale.ToUpper("LOC_TECH_FILTER_UNITS");
	unitList.Header:SetText(sHeaderText);
	unitList.HeaderOn:SetText(sHeaderText);

	if ( unitList.unitListIM ~= nil ) then
		unitList.unitListIM:ResetInstances();
	else
		unitList.unitListIM = InstanceManager:new( "UnitListInstance", "Root", unitList.List);
	end
	if ( unitList.civilianListIM ~= nil ) then
		unitList.civilianListIM:ResetInstances();
	else
		unitList.civilianListIM = InstanceManager:new( "CivilianListInstance",	"Root", unitList.List);
	end
	
	local unitData;
	if (listMode == LISTMODE.PRODUCTION or listMode == LISTMODE.PROD_QUEUE) then
		unitData = data.UnitItems;
	else
		unitData = data.UnitPurchases;
	end
	for i, item in ipairs(unitData) do
		local unitListing : table;
		if ((item.Yield == "YIELD_GOLD" and listMode == LISTMODE.PURCHASE_GOLD) or (item.Yield == "YIELD_FAITH" and listMode == LISTMODE.PURCHASE_FAITH) or (listMode == LISTMODE.PRODUCTION and item.IsCurrentProduction == false) or listMode == LISTMODE.PROD_QUEUE) then
			if (item.Civilian) then
				unitListing = unitList["civilianListIM"]:GetInstance();
			else
				unitListing = unitList["unitListIM"]:GetInstance();
			end

			local costStr = "";
			local costStrTT = "";
			if (listMode == LISTMODE.PRODUCTION or listMode == LISTMODE.PROD_QUEUE) then
				PopulateGenericBuildData(unitListing, item);
				
				costStr, costStrTT = GetTurnsToCompleteStrings(item.TurnsLeft);
			else
				PopulateGenericPurchaseData(unitListing, item);

				if (item.Yield == "YIELD_GOLD") then
					costStr = Locale.Lookup("LOC_PRODUCTION_PURCHASE_GOLD_TEXT", item.Cost);
				else
					costStr = Locale.Lookup("LOC_PRODUCTION_PURCHASE_FAITH_TEXT", item.Cost);
				end
				if item.CantAfford then
					costStr = "[COLOR:Red]" .. costStr .. "[ENDCOLOR]";
				end
			end

			unitListing.CostText:SetText(costStr);
			if(costStrTT ~= "") then
				unitListing.CostText:SetToolTipString(costStrTT);
			end

			-- Show/hide religion indicator icon
			if unitListing.ReligionIcon then
				local showReligionIcon:boolean = false;

				if item.ReligiousStrength and item.ReligiousStrength > 0 then
					if unitListing.ReligionIcon then
						local religionType = data.City:GetReligion():GetMajorityReligion();
						if religionType > 0 then
							local religion:table = GameInfo.Religions[religionType];
							local religionIcon:string = "ICON_" .. religion.ReligionType;
							local religionColor:number = UI.GetColorValue(religion.Color);
							local religionName:string = Game.GetReligion():GetName(religion.Index);

							unitListing.ReligionIcon:SetIcon(religionIcon);
							unitListing.ReligionIcon:SetColor(religionColor);
							unitListing.ReligionIcon:LocalizeAndSetToolTip( religionName );
							unitListing.ReligionIcon:SetHide(false);
							showReligionIcon = true;
						end
					end
				end

				unitListing.ReligionIcon:SetHide(not showReligionIcon);
			end

			-- Set Icon color and backing
			local textureName = TEXTURE_BASE;
			if item.Type ~= -1 then
				local kUnitDef:table = GameInfo.Units[item.Type];
				if (kUnitDef.Combat ~= 0 or kUnitDef.RangedCombat ~= 0) then		-- Need a simpler what to test if the unit is a combat unit or not.
					if "DOMAIN_SEA" == kUnitDef.Domain then
						textureName = TEXTURE_NAVAL;
					else
						textureName =  TEXTURE_BASE;
					end
				else
					if kUnitDef.MakeTradeRoute then
						textureName = TEXTURE_TRADE;
					elseif "FORMATION_CLASS_SUPPORT" == kUnitDef.FormationClass then
						textureName = TEXTURE_SUPPORT;
					elseif item.ReligiousStrength > 0 then
						textureName = TEXTURE_RELIGION;
					else
						textureName = TEXTURE_CIVILIAN;
					end
				end
			end

			-- Set colors and icons for the flag instance
			unitListing.FlagBase:SetTexture( textureName );
			unitListing.FlagBase:SetColor( primaryColor );
			unitListing.Icon:SetColor( secondaryColor );
		
            unitListing.Button:RegisterCallback( Mouse.eMouseEnter,	function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
			if (listMode == LISTMODE.PRODUCTION or listMode == LISTMODE.PROD_QUEUE) then
				unitListing.Button:RegisterCallback( Mouse.eLClick, function()
					BuildUnit(data.City, item);
					CloseAfterNewProduction();
					end);
			else
				unitListing.Button:RegisterCallback( Mouse.eLClick, function()
					PurchaseUnit(data.City, item);
					Close();
					end);
			end

			if not m_isTutorialRunning then
				unitListing.Button:RegisterCallback( Mouse.eRClick, function()
					RightClickProductionItem(item.Type);
				end);
			else
				unitListing.Button:SetTag(UITutorialManager:GetHash(item.Type));
			end

			-- Controls for training unit corps and armies.
			-- Want a special text string for this!! #NEW TEXT #LOCALIZATION - "You can only directly build corps and armies once you have constructed a military academy."
			-- LOC_UNIT_TRAIN_NEED_MILITARY_ACADEMY
			if item.Corps or item.Army then
				if (item.CorpsDisabled) then
					unitListing.CorpsDisabled:SetHide(false);
				end
				if (item.ArmyDisabled) then
					unitListing.ArmyDisabled:SetHide(false);	
				end
				unitListing.CorpsArmyDropdownArea:SetHide(false);	

				unitListing.CorpsArmyArrow:RegisterCallback( Mouse.eLClick, function() OnCorpsToggle( unitList, unitListing ); end );
				unitListing.CorpsArmyDropdownButton:RegisterCallback( Mouse.eLClick, function() OnCorpsToggle( unitList, unitListing ); end );
			end

			if item.Corps then	
				unitListing.CorpsButtonContainer:SetHide(false);
				-- Production meter progress for corps unit
				if (listMode == LISTMODE.PRODUCTION or listMode == LISTMODE.PROD_QUEUE) then
					if(item.Progress > 0) then
						unitListing.ProductionCorpsProgressArea:SetHide(false);
						local unitProgress = item.Progress/item.CorpsCost;
						if (unitProgress < 1) then
							unitListing.ProductionCorpsProgress:SetPercent(unitProgress);
						else
							unitListing.ProductionCorpsProgressArea:SetHide(true);
						end
					else
						unitListing.ProductionCorpsProgressArea:SetHide(true);
					end

					local turnsStr, turnsStrTT = GetTurnsToCompleteStrings(item.CorpsTurnsLeft);
					unitListing.CorpsCostText:SetText(turnsStr);
					unitListing.CorpsCostText:SetToolTipString(turnsStrTT);
				else
					unitListing.ProductionCorpsProgressArea:SetHide(true);
					if (item.Yield == "YIELD_GOLD") then
						costStr = Locale.Lookup("LOC_PRODUCTION_PURCHASE_GOLD_TEXT", item.CorpsCost);
					else
						costStr = Locale.Lookup("LOC_PRODUCTION_PURCHASE_FAITH_TEXT", item.CorpsCost);
					end
					if (item.CorpsDisabled) then
						if (m_showDisabled) then
							unitListing.CorpsDisabled:SetHide(false);
						end
						costStr = "[COLOR:Red]" .. costStr .. "[ENDCOLOR]";
					end
					unitListing.CorpsCostText:SetText(costStr);
				end
				

				unitListing.CorpsLabelIcon:SetText(item.CorpsName);
				unitListing.CorpsLabelText:SetText(Locale.Lookup(item.Name));
				
				unitListing.CorpsFlagBase:SetTexture( textureName );
				unitListing.CorpsFlagBase:SetColor( primaryColor );
				unitListing.CorpsIcon:SetColor( secondaryColor );
				unitListing.CorpsIcon:SetIcon(ICON_PREFIX..item.Type);
				unitListing.TrainCorpsButton:SetToolTipString(item.CorpsTooltip);
				unitListing.CorpsDisabled:SetToolTipString(item.CorpsTooltip);
				if (listMode == LISTMODE.PRODUCTION or listMode == LISTMODE.PROD_QUEUE) then
					unitListing.TrainCorpsButton:RegisterCallback( Mouse.eLClick, function()
						BuildUnitCorps(data.City, item);
						CloseAfterNewProduction();
					end);
				else
					unitListing.TrainCorpsButton:RegisterCallback( Mouse.eLClick, function()
						PurchaseUnitCorps(data.City, item);
						Close();
					end);
				end
			end		
			if item.Army then
				unitListing.ArmyButtonContainer:SetHide(false);

				if (listMode == LISTMODE.PRODUCTION or listMode == LISTMODE.PROD_QUEUE) then
					if(item.Progress > 0) then
						unitListing.ProductionArmyProgressArea:SetHide(false);
						local unitProgress = item.Progress/item.ArmyCost;
						unitListing.ProductionArmyProgress:SetPercent(unitProgress);
						if (unitProgress < 1) then
							unitListing.ProductionArmyProgress:SetPercent(unitProgress);
						else
							unitListing.ProductionArmyProgressArea:SetHide(true);
						end
					else
						unitListing.ProductionArmyProgressArea:SetHide(true);
					end
					
					local turnsStr, turnsStrTT = GetTurnsToCompleteStrings(item.ArmyTurnsLeft);
					unitListing.ArmyCostText:SetText(turnsStr);
					unitListing.ArmyCostText:SetToolTipString(turnsStrTT);
				else
					unitListing.ProductionArmyProgressArea:SetHide(true);
					if (item.Yield == "YIELD_GOLD") then
						costStr = Locale.Lookup("LOC_PRODUCTION_PURCHASE_GOLD_TEXT", item.ArmyCost);
					else
						costStr = Locale.Lookup("LOC_PRODUCTION_PURCHASE_FAITH_TEXT", item.ArmyCost);
					end
					if (item.ArmyDisabled) then
						if (m_showDisabled) then
							unitListing.ArmyDisabled:SetHide(false);
						end
						costStr = "[COLOR:Red]" .. costStr .. "[ENDCOLOR]";
					end
					unitListing.ArmyCostText:SetText(costStr);
				end
				
				unitListing.ArmyLabelIcon:SetText(item.ArmyName);
				unitListing.ArmyLabelText:SetText(Locale.Lookup(item.Name));
				unitListing.ArmyFlagBase:SetTexture( textureName );
				unitListing.ArmyFlagBase:SetColor( primaryColor );
				unitListing.ArmyIcon:SetColor( secondaryColor );
				unitListing.ArmyIcon:SetIcon(ICON_PREFIX..item.Type);
				unitListing.TrainArmyButton:SetToolTipString(item.ArmyTooltip);
				unitListing.ArmyDisabled:SetToolTipString(item.ArmyTooltip);
				if (listMode == LISTMODE.PRODUCTION or listMode == LISTMODE.PROD_QUEUE) then
					unitListing.TrainArmyButton:RegisterCallback( Mouse.eLClick, function()
						BuildUnitArmy(data.City, item);
						CloseAfterNewProduction();
						end);
				else
					unitListing.TrainArmyButton:RegisterCallback( Mouse.eLClick, function()
						PurchaseUnitArmy(data.City, item);
						Close();
						end);
				end
			end
		end -- end faith/gold check
	end -- end iteration through units

	if (unitList.unitListIM.m_iAllocatedInstances <= 0 and unitList.civilianListIM.m_iAllocatedInstances <= 0) then
		unitList.Top:SetHide(true);
	else
		unitList.Header:RegisterCallback( Mouse.eLClick, function()
			OnExpand(unitList);					
			end);
		unitList.HeaderOn:RegisterCallback( Mouse.eLClick, function()
			OnCollapse(unitList);					
			end);
	end

	unitList.Top:RegisterSizeChanged(function() OnUnitListSizeChanged(listIM, unitList.Top:GetSizeY()); end);
	OnUnitListSizeChanged(listIM, unitList.Top:GetSizeY());

	OnExpand(unitList);
end

-- ===========================================================================
function OnCorpsToggle( unitList:table, unitListing:table )
	local isExpanded = unitListing.CorpsArmyArrow:IsSelected();
	unitListing.CorpsArmyArrow:SetSelected(not isExpanded);
	unitListing.ArmyCorpsDrawer:SetHide(not isExpanded);
	unitList.List:CalculateSize();
	unitList.Top:CalculateSize();
	if(m_CurrentListMode == LISTMODE.PRODUCTION) then
		Controls.ProductionList:CalculateSize();						
		Controls.ProductionListScroll:CalculateSize();
	elseif(m_CurrentListMode == LISTMODE.PURCHASE_GOLD) then
		Controls.PurchaseList:CalculateSize();
		Controls.PurchaseListScroll:CalculateSize();
	elseif(m_CurrentListMode == LISTMODE.PURCHASE_FAITH) then
		Controls.PurchaseFaithList:CalculateSize();
		Controls.PurchaseFaithListScroll:CalculateSize();
	end
end

-- ===========================================================================
function ResetFields(pListIM:table)
	local pParentControl:table = pListIM.m_ParentControl;
	if pParentControl then
		pParentControl[FIELD_LIST_BUILDING_SIZE_Y]	= 0;
		pParentControl[FIELD_LIST_WONDER_SIZE_Y]	= 0;
		pParentControl[FIELD_LIST_UNIT_SIZE_Y]		= 0;
		pParentControl[FIELD_DISTRICT_LIST]			= nil;
		pParentControl[FIELD_BUILDING_LIST]			= nil;
		pParentControl[FIELD_WONDER_LIST]			= nil;
		pParentControl[FIELD_UNIT_LIST]				= nil;
		pParentControl[FIELD_PROJECTS_LIST]			= nil;
	end
end

-- ===========================================================================
function PopulateList(data, listMode, listIM)
	listIM:ResetInstances();

	Controls.PauseCollapseList:Stop();

	ResetFields(listIM);

	if (listMode == LISTMODE.PRODUCTION or listMode == LISTMODE.PROD_QUEUE) then
		PopulateCurrentProduction(data);
		
		ResizeProductionScrollList();

		PopulateDistrictsWithNestedBuildings(data, listMode, listIM);
		PopulateWonders(data, listMode, listIM);
	end

	--If we are purchasing, then buildings don't have to be displayed in a nested way
	if (listMode == LISTMODE.PURCHASE_FAITH or listMode == LISTMODE.PURCHASE_GOLD) then
		PopulateDistrictsWithoutNestedBuildings(data, listMode, listIM);
	end
	
	PopulateUnits(data, listMode, listIM);

	--Projects can only be produced, not purchased
	if (listMode == LISTMODE.PRODUCTION or listMode == LISTMODE.PROD_QUEUE) then 
		PopulateProjects(data, listMode, listIM);
	end
end

-- ===========================================================================
function OnLocalPlayerChanged()
	Refresh();
end

-- ===========================================================================
-- Returns ( allReasons:string )
function ComposeFailureReasonStrings( isDisabled:boolean, results:table )
	if isDisabled and results ~= nil then
		-- Are there any failure reasons?
		local pFailureReasons : table = results[CityCommandResults.FAILURE_REASONS];
		if pFailureReasons ~= nil and table.count( pFailureReasons ) > 0 then
			-- Collect them all!
			local allReasons : string = "";
			for i,v in ipairs(pFailureReasons) do
				allReasons = allReasons .. "[NEWLINE][NEWLINE][COLOR:Red]" .. Locale.Lookup(v) .. "[ENDCOLOR]";
			end
			return allReasons;
		end
	end
	return "";
end
function ComposeProductionCostString( iProductionProgress:number, iProductionCost:number)
	-- Show production progress only if there is progress present
	if iProductionCost ~= 0 then
		local costString		:string = tostring(iProductionCost);
		
		if iProductionProgress > 0 then -- Only show fraction if build progress has been made.
			costString = tostring(iProductionProgress) .. "/" .. costString;
		end
		return TXT_COST .. ": " .. costString .. " [ICON_Production] " .. TXT_PRODUCTION;
	end
	return "";
end


-- Returns ( tooltip:string, subtitle:string )
function ComposeUnitCorpsStrings( unit:table, iProdProgress:number, pBuildQueue )

	local tooltip:string = ToolTipHelper.GetUnitToolTip( unit.Hash, MilitaryFormationTypes.CORPS_MILITARY_FORMATION, pBuildQueue );

	local subtitle	:string = "";
	if unit.Domain == "DOMAIN_SEA" then
		subtitle = "(" .. LOC_HUD_UNIT_PANEL_FLEET_SUFFIX .. ")";
	else
		subtitle = "(" .. TXT_HUD_UNIT_PANEL_CORPS_SUFFIX .. ")";
	end

	return tooltip, subtitle;
end
function ComposeUnitArmyStrings( unit:table, iProdProgress:number, pBuildQueue )

	local tooltip:string = ToolTipHelper.GetUnitToolTip( unit.Hash, MilitaryFormationTypes.ARMY_MILITARY_FORMATION, pBuildQueue );

	local subtitle	:string = "";
	if unit.Domain == "DOMAIN_SEA" then
		subtitle = "(" .. TXT_HUD_UNIT_PANEL_ARMADA_SUFFIX .. ")";
	else
		subtitle = "(" .. TXT_HUD_UNIT_PANEL_ARMY_SUFFIX .. ")";
	end

	return tooltip, subtitle;
end

-- Returns ( isPurchaseable:boolean, kEntry:table )
function ComposeUnitForPurchase( row:table, pCity:table, sYield:string, pYieldSource:table, sCantAffordKey:string )
	local YIELD_TYPE 	:number = GameInfo.Yields[sYield].Index;
	
	-- Should we display this option to the player?
	local tParameters = {};
	tParameters[CityCommandTypes.PARAM_UNIT_TYPE] = row.Hash;
	tParameters[CityCommandTypes.PARAM_YIELD_TYPE] = YIELD_TYPE;
	if CityManager.CanStartCommand( pCity, CityCommandTypes.PURCHASE, true, tParameters, false ) then
		local isCanStart, results			 = CityManager.CanStartCommand( pCity, CityCommandTypes.PURCHASE, false, tParameters, true );
		local isDisabled			:boolean = not isCanStart;
		local allReasons			 :string = ComposeFailureReasonStrings( isDisabled, results );
		local sToolTip 				 :string = ToolTipHelper.GetUnitToolTip( row.Hash, MilitaryFormationTypes.STANDARD_MILITARY_FORMATION, pCity:GetBuildQueue() ) .. allReasons;
		local isCantAfford			:boolean = false;
		--print ( "UnitBuy ", row.UnitType,isCanStart );
		
		-- Collect some constants so we don't need to keep calling out to get them.
		local nCityID				:number = pCity:GetID();
		local pCityGold				 :table = pCity:GetGold();
		local TXT_INSUFFIENT_YIELD	:string = "[NEWLINE][NEWLINE][COLOR:Red]" .. Locale.Lookup( sCantAffordKey ) .. "[ENDCOLOR]";
		
		-- Affordability check
		if not pYieldSource:CanAfford( nCityID, row.Hash ) then
			sToolTip = sToolTip .. TXT_INSUFFIENT_YIELD;
			isDisabled = true;
			isCantAfford = true;
		end
		
		local pBuildQueue			:table  = pCity:GetBuildQueue();
		local nProductionCost		:number = pBuildQueue:GetUnitCost( row.Index );
		local nProductionProgress	:number = pBuildQueue:GetUnitProgress( row.Index );
		
		local kUnit	 :table = {
			Type				= row.UnitType;
			Name				= row.Name;
			ToolTip				= sToolTip;
			Hash				= row.Hash;
			Kind				= row.Kind;
			Civilian			= row.FormationClass == "FORMATION_CLASS_CIVILIAN";
			Disabled			= isDisabled;
			CantAfford			= isCantAfford,
			Yield				= sYield;
			Cost				= pCityGold:GetPurchaseCost( YIELD_TYPE, row.Hash, MilitaryFormationTypes.STANDARD_MILITARY_FORMATION );
			ReligiousStrength	= row.ReligiousStrength;

			CorpsTurnsLeft	= 0;
			ArmyTurnsLeft	= 0;
			Progress		= 0;
		};
		
		-- Should we present options for building Corps or Army versions?
		if results ~= nil then
			kUnit.Corps = results[CityOperationResults.CAN_TRAIN_CORPS];
			kUnit.Army = results[CityOperationResults.CAN_TRAIN_ARMY];
			
			local nProdProgress	:number = pBuildQueue:GetUnitProgress( row.Index );
			if kUnit.Corps then
				kUnit.CorpsCost	= pCityGold:GetPurchaseCost( YIELD_TYPE, row.Hash, MilitaryFormationTypes.CORPS_MILITARY_FORMATION );
				kUnit.CorpsTooltip, kUnit.CorpsName = ComposeUnitCorpsStrings( row, nProdProgress, pBuildQueue );
				kUnit.CorpsDisabled = not pYieldSource:CanAfford( nCityID, row.Hash, MilitaryFormationTypes.CORPS_MILITARY_FORMATION );
				if kUnit.CorpsDisabled then
					kUnit.CorpsTooltip = kUnit.CorpsTooltip .. TXT_INSUFFIENT_YIELD;
				end
				tParameters[CityCommandTypes.PARAM_MILITARY_FORMATION_TYPE] = MilitaryFormationTypes.CORPS_MILITARY_FORMATION;
				local bCanPurchase, kResults = CityManager.CanStartCommand( pCity, CityCommandTypes.PURCHASE, false, tParameters, true );
				kUnit.CorpsDisabled = not bCanPurchase;
				if (not bCanPurchase) then
					local sFailureReasons:string = ComposeFailureReasonStrings( kUnit.CorpsDisabled, kResults );
					kUnit.CorpsTooltip = kUnit.CorpsTooltip .. sFailureReasons;
				end
			end
			
			if kUnit.Army then
				kUnit.ArmyCost	= pCityGold:GetPurchaseCost( YIELD_TYPE, row.Hash, MilitaryFormationTypes.ARMY_MILITARY_FORMATION );
				kUnit.ArmyTooltip, kUnit.ArmyName = ComposeUnitArmyStrings( row, nProdProgress, pBuildQueue );
				kUnit.ArmyDisabled = not pYieldSource:CanAfford( nCityID, row.Hash, MilitaryFormationTypes.ARMY_MILITARY_FORMATION );
				if kUnit.ArmyDisabled then
					kUnit.ArmyTooltip = kUnit.ArmyTooltip .. TXT_INSUFFIENT_YIELD;
				end
				tParameters[CityCommandTypes.PARAM_MILITARY_FORMATION_TYPE] = MilitaryFormationTypes.ARMY_MILITARY_FORMATION;
				local bCanPurchase, kResults = CityManager.CanStartCommand( pCity, CityCommandTypes.PURCHASE, false, tParameters, true );
				kUnit.ArmyDisabled = not bCanPurchase;
				if (not bCanPurchase) then
					local sFailureReasons:string = ComposeFailureReasonStrings( kUnit.ArmyDisabled, kResults );
					kUnit.ArmyTooltip = kUnit.ArmyTooltip .. sFailureReasons;
				end
			end
		end

		return true, kUnit;
	end
	return false, nil;
end
function ComposeBldgForPurchase( pRow:table, pCity:table, sYield:string, pYieldSource:table, sCantAffordKey:string )
	local YIELD_TYPE 	:number = GameInfo.Yields[sYield].Index;
	
	local tParameters = {};
	tParameters[CityCommandTypes.PARAM_BUILDING_TYPE] = pRow.Hash;
	tParameters[CityCommandTypes.PARAM_YIELD_TYPE] = YIELD_TYPE;
	if CityManager.CanStartCommand( pCity, CityCommandTypes.PURCHASE, true, tParameters, false ) then
		local isCanStart, pResults		 = CityManager.CanStartCommand( pCity, CityCommandTypes.PURCHASE, false, tParameters, true );
		local isDisabled		:boolean = not isCanStart;
		local isCantAfford		:boolean = false;

		local sToolTip 				:string = ToolTipHelper.GetBuildingToolTip( pRow.Hash, playerID, pCity );
		local pBuildQueue			:table  = pCity:GetBuildQueue();
		local iProductionCost		:number = pBuildQueue:GetBuildingCost( pRow.Index );
		local iProductionProgress	:number = pBuildQueue:GetBuildingProgress( pRow.Index );
		sToolTip = sToolTip .. "[NEWLINE][NEWLINE]";
		sToolTip = sToolTip .. ComposeProductionCostString( iProductionProgress, iProductionCost );

		local iMaintenanceCost		:number = pRow.Maintenance or 0;
		if (iMaintenanceCost ~= nil and iMaintenanceCost > 0) then
			local yield = GameInfo.Yields["YIELD_GOLD"];
			if(yield) then
				sToolTip = sToolTip .. "[NEWLINE]" .. Locale.Lookup("LOC_TOOLTIP_MAINTENANCE", iMaintenanceCost, yield.IconString, yield.Name);
			end
		end

		sToolTip = sToolTip .. "[NEWLINE]" .. AddBuildingExtraCostTooltip(pRow.Hash);

		local sAllReasons		 :string = ComposeFailureReasonStrings( isDisabled, pResults );
		sToolTip = sToolTip .. sAllReasons;
		
		-- Affordability check
		if not pYieldSource:CanAfford( pCity:GetID(), pRow.Hash ) then
			sToolTip = sToolTip .. "[NEWLINE][NEWLINE][COLOR:Red]" .. Locale.Lookup(sCantAffordKey) .. "[ENDCOLOR]";
			isDisabled = true;
			isCantAfford = true;
		end
		
		local kBuilding :table = {
			Type			= pRow.BuildingType,
			Name			= pRow.Name, 
			ToolTip			= sToolTip, 
			Hash			= pRow.Hash, 
			Kind			= pRow.Kind, 
			Disabled		= isDisabled, 
			CantAfford		= isCantAfford,
			Cost			= pCity:GetGold():GetPurchaseCost( YIELD_TYPE, pRow.Hash ),  
			Yield			= sYield
		};
		return true, kBuilding;
	end
	return false, nil;
end

function ComposeDistrictForPurchase( pRow:table, pCity:table, sYield:string, pYieldSource:table, sCantAffordKey:string )
	local YIELD_TYPE 	:number = GameInfo.Yields[sYield].Index;
	
	local tParameters = {};
	tParameters[CityCommandTypes.PARAM_DISTRICT_TYPE] = pRow.Hash;
	tParameters[CityCommandTypes.PARAM_YIELD_TYPE] = YIELD_TYPE;
	if CityManager.CanStartCommand( pCity, CityCommandTypes.PURCHASE, true, tParameters, false ) then
		local isCanStart, pResults		 = CityManager.CanStartCommand( pCity, CityCommandTypes.PURCHASE, false, tParameters, true );
		local isDisabled		:boolean = not isCanStart;
		local sAllReasons		:string = ComposeFailureReasonStrings( isDisabled, pResults );
		local sToolTip 			:string = ToolTipHelper.GetDistrictToolTip( pRow.Hash ) .. sAllReasons;
		local isCantAfford		:boolean = false;
		
		-- Affordability check
		if not pYieldSource:CanAfford( pCity:GetID(), pRow.Hash ) then
			sToolTip = sToolTip .. "[NEWLINE][NEWLINE][COLOR:Red]" .. Locale.Lookup(sCantAffordKey) .. "[ENDCOLOR]";
			isDisabled = true;
			isCantAfford = true;
		end
		
		local pBuildQueue			:table  = pCity:GetBuildQueue();
		local iProductionCost		:number = pBuildQueue:GetDistrictCost( pRow.Index );
		local iProductionProgress	:number = pBuildQueue:GetDistrictProgress( pRow.Index );
		sToolTip = sToolTip .. "[NEWLINE][NEWLINE]";
		sToolTip = sToolTip .. ComposeProductionCostString( iProductionProgress, iProductionCost );

		local iMaintenanceCost		:number = pRow.Maintenance or 0;
		if (iMaintenanceCost ~= nil and iMaintenanceCost > 0) then
			local yield = GameInfo.Yields["YIELD_GOLD"];
			if(yield) then
				sToolTip = sToolTip .. "[NEWLINE]" .. Locale.Lookup("LOC_TOOLTIP_MAINTENANCE", iMaintenanceCost, yield.IconString, yield.Name);
			end
		end
		
		local kDistrict :table = {
			Type			= pRow.DistrictType,
			Name			= pRow.Name, 
			ToolTip			= sToolTip, 
			Hash			= pRow.Hash, 
			Kind			= pRow.Kind, 
			Disabled		= isDisabled, 
			CantAfford		= isCantAfford,
			Cost			= pCity:GetGold():GetPurchaseCost( YIELD_TYPE, pRow.Hash ),  
			Yield			= sYield
		};
		return true, kDistrict;
	end
	return false, nil;
end

-- ===========================================================================
function Refresh()
	local playerID	:number = Game.GetLocalPlayer();
	local pPlayer	:table = Players[playerID];
	if (pPlayer == nil) then
		return;
	end

	local pSelectedCity:table = UI.GetHeadSelectedCity();
	if pSelectedCity == nil then
		Close();
		return;
	end

	local kData:table = GetData();
	if kData ~= nil then
		View(kData);
	else
		Close();
	end
end

-- ===========================================================================
function GetData()
	local playerID	:number = Game.GetLocalPlayer();
	local pPlayer	:table = Players[playerID];
	if (pPlayer == nil) then
		Close();
		return nil;
	end

	local pSelectedCity:table = UI.GetHeadSelectedCity();
	if pSelectedCity == nil then
		Close();
		return nil;
	end

	local cityGrowth	= pSelectedCity:GetGrowth();
	local cityCulture	= pSelectedCity:GetCulture();
	local buildQueue	= pSelectedCity:GetBuildQueue();
	local playerTreasury= pPlayer:GetTreasury();
	local playerReligion= pPlayer:GetReligion();
	local cityGold		= pSelectedCity:GetGold();
	local cityBuildings = pSelectedCity:GetBuildings();
	local cityDistricts = pSelectedCity:GetDistricts();
	local cityID		= pSelectedCity:GetID();
		
	local new_data = {
		City				= pSelectedCity,
		Population			= pSelectedCity:GetPopulation(),
		Owner				= pSelectedCity:GetOwner(),
		Damage				= pPlayer:GetDistricts():FindID( pSelectedCity:GetDistrictID() ):GetDamage(),
		TurnsUntilGrowth	= cityGrowth:GetTurnsUntilGrowth(),
		CurrentTurnsLeft	= buildQueue:GetTurnsLeft(),
		FoodSurplus			= cityGrowth:GetFoodSurplus(),
		CulturePerTurn		= cityCulture:GetCultureYield(),
		TurnsUntilExpansion = cityCulture:GetTurnsUntilExpansion(),
		DistrictItems		= {},
		BuildingItems		= {},
		UnitItems			= {},
		ProjectItems		= {},
		BuildingPurchases	= {},
		UnitPurchases		= {},
		DistrictPurchases	= {},
	};
		
	m_CurrentProductionHash = buildQueue:GetCurrentProductionTypeHash();
	m_PreviousProductionHash = buildQueue:GetPreviousProductionTypeHash();

	--Must do districts before buildings
	for row in GameInfo.Districts() do
		if row.Hash == m_CurrentProductionHash then
			new_data.CurrentProduction = row.Name;
				
			if(GameInfo.DistrictReplaces[row.DistrictType] ~= nil) then
				new_data.CurrentProductionType = GameInfo.DistrictReplaces[row.DistrictType].ReplacesDistrictType;
			else
				new_data.CurrentProductionType = row.DistrictType;
			end
		end
			
		local isInPanelList 		:boolean = (row.Hash ~= m_CurrentProductionHash or not row.OnePerCity) and not row.InternalOnly;
		local bHasProducedDistrict	:boolean = cityDistricts:HasDistrict( row.Index );
		if isInPanelList and ( buildQueue:CanProduce( row.Hash, true ) or bHasProducedDistrict ) then
			local isCanProduceExclusion, results = buildQueue:CanProduce( row.Hash, false, true );
			local isDisabled			:boolean = not isCanProduceExclusion;
				
			-- If at least one valid plot is found where the district can be built, consider it buildable.
			local plots :table = GetCityRelatedPlotIndexesDistrictsAlternative( pSelectedCity, row.Hash );
			if plots == nil or table.count(plots) == 0 then
				-- No plots available for district. Has player had already started building it?
				local isPlotAllocated :boolean = false;
				local pDistricts 		:table = pSelectedCity:GetDistricts();
				for _, pCityDistrict in pDistricts:Members() do
					if row.Index == pCityDistrict:GetType() then
						isPlotAllocated = true;
						break;
					end
				end
				-- If not, this district can't be built. Guarantee that isDisabled is set.
				if not isPlotAllocated then
					isDisabled = true;
				elseif results ~= nil then
					local pFailureReasons : table = results[CityCommandResults.FAILURE_REASONS];
					if pFailureReasons ~= nil and table.count( pFailureReasons ) > 0 then
						for i,v in ipairs(pFailureReasons) do
							if v == TXT_DISTRICT_REPAIR_LOCATION_FLOODED then
								isDisabled = true;
								break;
							end
						end
					end
				end
			elseif isDisabled and results ~= nil then
				-- TODO this should probably be handled in the exposure, for example:
				-- BuildQueue::CanProduce(nDistrictHash, bExclusionTest, bReturnResults, bAllowPurchasingPlots)
				local pFailureReasons : table = results[CityCommandResults.FAILURE_REASONS];
				if pFailureReasons ~= nil and table.count( pFailureReasons ) > 0 then
					-- There are available plots to purchase, it could still be available
					isDisabled = false;
					for i,v in ipairs(pFailureReasons) do
						-- If its disabled for another reason, keep it disabled
						if v ~= "LOC_DISTRICT_ZONE_NO_SUITABLE_LOCATION" then
							isDisabled = true;
							break;
						end
					end
				end
			end
				
			local allReasons			:string = ComposeFailureReasonStrings( isDisabled, results );
			local sToolTip				:string = ToolTipHelper.GetToolTip(row.DistrictType, Game.GetLocalPlayer()) .. allReasons;
				
			local iProductionCost		:number = buildQueue:GetDistrictCost( row.Index );
			local iProductionProgress	:number = buildQueue:GetDistrictProgress( row.Index );

			sToolTip = sToolTip .. "[NEWLINE][NEWLINE]";
			sToolTip = sToolTip .. ComposeProductionCostString( iProductionProgress, iProductionCost);

			local iMaintenanceCost		:number = row.Maintenance or 0;
			if (iMaintenanceCost ~= nil and iMaintenanceCost > 0) then
				local yield = GameInfo.Yields["YIELD_GOLD"];
				if(yield) then
					sToolTip = sToolTip .. "[NEWLINE]" .. Locale.Lookup("LOC_TOOLTIP_MAINTENANCE", iMaintenanceCost, yield.IconString, yield.Name);
				end
			end

			local bIsContaminated:boolean = cityDistricts:IsContaminated( row.Index );
			local iContaminatedTurns:number = 0;
			if bIsContaminated then
				for _, pDistrict in cityDistricts:Members() do
					local kDistrictDef:table = GameInfo.Districts[pDistrict:GetType()];
					if kDistrictDef.PrimaryKey == row.DistrictType then
						local kFalloutManager = Game.GetFalloutManager();
						local pDistrictPlot:table = Map.GetPlot(pDistrict:GetX(), pDistrict:GetY());
						iContaminatedTurns = kFalloutManager:GetFalloutTurnsRemaining(pDistrictPlot:GetIndex());
					end
				end
			end

			table.insert( new_data.DistrictItems, {
				Type				= row.DistrictType, 
				Name				= row.Name, 
				ToolTip				= sToolTip, 
				Hash				= row.Hash, 
				Kind				= row.Kind, 
				TurnsLeft			= buildQueue:GetTurnsLeft( row.DistrictType ), 
				Disabled			= isDisabled, 
				Repair				= cityDistricts:IsPillaged( row.Index ),
				Contaminated		= bIsContaminated,
				ContaminatedTurns	= iContaminatedTurns,
				Cost				= iProductionCost, 
				Progress			= iProductionProgress,
				HasBeenBuilt		= bHasProducedDistrict,
				IsComplete			= cityDistricts:IsComplete( row.Index )
			});
		end

		-- Can it be purchased with gold?
		local isAllowed, kDistrict = ComposeDistrictForPurchase( row, pSelectedCity, "YIELD_GOLD", playerTreasury, "LOC_BUILDING_INSUFFICIENT_FUNDS" );
		if isAllowed then
			table.insert( new_data.DistrictPurchases, kDistrict );
		end

		-- Can it be purchased with faith?
		local isAllowed, kDistrict = ComposeDistrictForPurchase( row, pSelectedCity, "YIELD_FAITH", playerReligion, "LOC_BUILDING_INSUFFICIENT_FAITH" );
		if isAllowed then
			table.insert( new_data.DistrictPurchases, kDistrict );
		end
	end

	--Must do buildings after districts
	for row in GameInfo.Buildings() do
		if row.Hash == m_CurrentProductionHash then
			new_data.CurrentProduction = row.Name;
			new_data.CurrentProductionType= row.BuildingType;
		end

		local bCanProduce = buildQueue:CanProduce( row.Hash, true );
		local iPrereqDistrict = "";
		if row.PrereqDistrict ~= nil then
			iPrereqDistrict = row.PrereqDistrict;
				
			--Only add buildings if the prereq district is not the current production (this can happen when repairing)
			if new_data.CurrentProductionType == row.PrereqDistrict then
				bCanProduce = false;
			end
		end

		if row.Hash ~= m_CurrentProductionHash and (not row.MustPurchase or cityBuildings:IsPillaged(row.Hash)) and bCanProduce then
			local isCanStart, results			 = buildQueue:CanProduce( row.Hash, false, true );
			local isDisabled			:boolean = not isCanStart;

			-- Did it fail and it is a Wonder?  If so, if it failed because of *just* NO_SUITABLE_LOCATION, we can look for an alternate.
			if (isDisabled and row.IsWonder and results ~= nil and results[CityOperationResults.NO_SUITABLE_LOCATION] ~= nil and results[CityOperationResults.NO_SUITABLE_LOCATION] == true) then
				local pPurchaseablePlots :table = GetCityRelatedPlotIndexesWondersAlternative( pSelectedCity, row.Hash );
				if (pPurchaseablePlots and #pPurchaseablePlots > 0) then
					isDisabled = false;
				end
			end

			local allReasons			 :string = ComposeFailureReasonStrings( isDisabled, results );
			local sToolTip 				 :string = ToolTipHelper.GetBuildingToolTip( row.Hash, playerID, pSelectedCity ) .. allReasons;

			local iProductionCost		:number = buildQueue:GetBuildingCost( row.Index );
			local iProductionProgress	:number = buildQueue:GetBuildingProgress( row.Index );
			sToolTip = sToolTip .. "[NEWLINE][NEWLINE]";
			sToolTip = sToolTip .. ComposeProductionCostString( iProductionProgress, iProductionCost);

			local iMaintenanceCost		:number = row.Maintenance or 0;
			if (iMaintenanceCost ~= nil and iMaintenanceCost > 0) then
				local yield = GameInfo.Yields["YIELD_GOLD"];
				if(yield) then
					sToolTip = sToolTip .. "[NEWLINE]" .. Locale.Lookup("LOC_TOOLTIP_MAINTENANCE", iMaintenanceCost, yield.IconString, yield.Name);
				end
			end

			sToolTip = sToolTip .. "[NEWLINE]" .. AddBuildingExtraCostTooltip(row.Hash);
				
			table.insert( new_data.BuildingItems, {
				Type			= row.BuildingType, 
				Name			= row.Name, 
				ToolTip			= sToolTip, 
				Hash			= row.Hash, 
				Kind			= row.Kind, 
				TurnsLeft		= buildQueue:GetTurnsLeft( row.Hash ), 
				Disabled		= isDisabled, 
				Repair			= cityBuildings:IsPillaged( row.Hash ), 
				Cost			= iProductionCost, 
				Progress		= iProductionProgress, 
				IsWonder		= row.IsWonder,
				PrereqDistrict	= iPrereqDistrict,
				PrereqBuildings	= row.PrereqBuildingCollection
			});
		end
			
		-- Can it be purchased with gold?
		if row.PurchaseYield == "YIELD_GOLD" then
			local isAllowed, kBldg = ComposeBldgForPurchase( row, pSelectedCity, "YIELD_GOLD", playerTreasury, "LOC_BUILDING_INSUFFICIENT_FUNDS" );
			if isAllowed then
				table.insert( new_data.BuildingPurchases, kBldg );
			end
		end
		-- Can it be purchased with faith?
		if row.PurchaseYield == "YIELD_FAITH" or cityGold:IsBuildingFaithPurchaseEnabled( row.Hash ) then
			local isAllowed, kBldg = ComposeBldgForPurchase( row, pSelectedCity, "YIELD_FAITH", playerReligion, "LOC_BUILDING_INSUFFICIENT_FAITH" );
			if isAllowed then
				table.insert( new_data.BuildingPurchases, kBldg );
			end
		end
	end

	-- Sort BuildingItems to ensure Buildings are placed behind any Prereqs for that building
	table.sort(new_data.BuildingItems, 
		function(a, b)
			if a.IsWonder then
				return false;
			end
			if a.Disabled == false and b.Disabled == true then
				return true;
			end
			return false;
		end
	);

	for row in GameInfo.Units() do
		if row.Hash == m_CurrentProductionHash then
			new_data.CurrentProduction = row.Name;
			new_data.CurrentProductionType= row.UnitType;
		end

		local kBuildParameters = {};
		kBuildParameters.UnitType = row.Hash;
		kBuildParameters.MilitaryFormationType = MilitaryFormationTypes.STANDARD_MILITARY_FORMATION;

		-- Can it be built normally?
		if not row.MustPurchase and buildQueue:CanProduce( kBuildParameters, true ) then
			local isCanProduceExclusion, results	 = buildQueue:CanProduce( kBuildParameters, false, true );
			local nProductionCost		:number = buildQueue:GetUnitCost( row.Index );
			local nProductionProgress	:number = buildQueue:GetUnitProgress( row.Index );
			local isDisabled				:boolean = not isCanProduceExclusion;
			local sAllReasons				 :string = ComposeFailureReasonStrings( isDisabled, results );
			local sToolTip					 :string = ToolTipHelper.GetUnitToolTip( row.Hash, MilitaryFormationTypes.STANDARD_MILITARY_FORMATION, buildQueue ) .. sAllReasons;
				
			local kUnit :table = {
				Type				= row.UnitType, 
				Name				= row.Name, 
				ToolTip				= sToolTip, 
				Hash				= row.Hash, 
				Kind				= row.Kind, 
				TurnsLeft			= buildQueue:GetTurnsLeft( row.Hash ), 
				Disabled			= isDisabled, 
				Civilian			= row.FormationClass == "FORMATION_CLASS_CIVILIAN",
				Cost				= nProductionCost, 
				Progress			= nProductionProgress, 
				Corps				= false,
				CorpsCost			= 0,
				CorpsTurnsLeft		= 1,
				CorpsTooltip		= "",
				CorpsName			= "",
				Army				= false,
				ArmyCost			= 0,
				ArmyTurnsLeft		= 1,
				ArmyTooltip			= "",
				ArmyName			= "",
				ReligiousStrength	= row.ReligiousStrength,
				IsCurrentProduction = row.Hash == m_CurrentProductionHash
			};
				
			-- Should we present options for building Corps or Army versions?
			if results ~= nil then
				if results[CityOperationResults.CAN_TRAIN_CORPS] then
					kBuildParameters.MilitaryFormationType = MilitaryFormationTypes.CORPS_MILITARY_FORMATION;
					local bCanProduceCorps, kResults = buildQueue:CanProduce( kBuildParameters, false, true);
					kUnit.Corps			= true;
					kUnit.CorpsDisabled = not bCanProduceCorps;
					kUnit.CorpsCost		= buildQueue:GetUnitCorpsCost( row.Index );
					kUnit.CorpsTurnsLeft	= buildQueue:GetTurnsLeft( row.Hash, MilitaryFormationTypes.CORPS_MILITARY_FORMATION );
					kUnit.CorpsTooltip, kUnit.CorpsName = ComposeUnitCorpsStrings( row, nProductionProgress, buildQueue );
					local sFailureReasons:string = ComposeFailureReasonStrings( kUnit.CorpsDisabled, kResults );
					kUnit.CorpsTooltip = kUnit.CorpsTooltip .. sFailureReasons;
					kUnit.Cost= kUnit.CorpsCost;
				end
				if results[CityOperationResults.CAN_TRAIN_ARMY] then
					kBuildParameters.MilitaryFormationType = MilitaryFormationTypes.ARMY_MILITARY_FORMATION;
					local bCanProduceArmy, kResults = buildQueue:CanProduce( kBuildParameters, false, true );
					kUnit.Army			= true;
					kUnit.ArmyDisabled	= not bCanProduceArmy;
					kUnit.ArmyCost		= buildQueue:GetUnitArmyCost( row.Index );
					kUnit.ArmyTurnsLeft	= buildQueue:GetTurnsLeft( row.Hash, MilitaryFormationTypes.ARMY_MILITARY_FORMATION );
					kUnit.ArmyTooltip, kUnit.ArmyName = ComposeUnitArmyStrings( row, nProductionProgress, buildQueue );		
					local sFailureReasons:string = ComposeFailureReasonStrings( kUnit.ArmyDisabled, kResults );
					kUnit.ArmyTooltip = kUnit.ArmyTooltip .. sFailureReasons;
					kUnit.Cost = kUnit.CorpsCost;
				end
			end
				
			table.insert(new_data.UnitItems, kUnit );
		end
			
		-- Can it be purchased with gold?
		if row.PurchaseYield == "YIELD_GOLD" then
			local isAllowed, kUnit = ComposeUnitForPurchase( row, pSelectedCity, "YIELD_GOLD", playerTreasury, "LOC_BUILDING_INSUFFICIENT_FUNDS" );
			if isAllowed then
				table.insert( new_data.UnitPurchases, kUnit );
			end
		end
		-- Can it be purchased with faith?
		if row.PurchaseYield == "YIELD_FAITH" or cityGold:IsUnitFaithPurchaseEnabled( row.Hash ) then
			local isAllowed, kUnit = ComposeUnitForPurchase( row, pSelectedCity, "YIELD_FAITH", playerReligion, "LOC_BUILDING_INSUFFICIENT_FAITH" );
			if isAllowed then
				table.insert( new_data.UnitPurchases, kUnit );
			end
		end 
	end
	
	if (pBuildQueue == nil) then
		pBuildQueue = pSelectedCity:GetBuildQueue();
	end

	for row in GameInfo.Projects() do
		if row.Hash == m_CurrentProductionHash then
			new_data.CurrentProduction = row.Name;
			new_data.CurrentProductionType= row.ProjectType;
		end

		if buildQueue:CanProduce( row.Hash, true ) then
			local isCanProduceExclusion, results = buildQueue:CanProduce( row.Hash, false, true );
			local isDisabled			:boolean = not isCanProduceExclusion;
				
			local allReasons		:string	= ComposeFailureReasonStrings( isDisabled, results );
			local sToolTip			:string = ToolTipHelper.GetProjectToolTip( row.Hash) .. allReasons;
				
			local iProductionCost		:number = buildQueue:GetProjectCost( row.Index );
			local iProductionProgress	:number = buildQueue:GetProjectProgress( row.Index );
			sToolTip = sToolTip .. "[NEWLINE]" .. ComposeProductionCostString( iProductionProgress, iProductionCost );
				
			table.insert(new_data.ProjectItems, {
				Type				= row.ProjectType,
				Name				= row.Name, 
				ToolTip				= sToolTip, 
				Hash				= row.Hash, 
				Kind				= row.Kind, 
				TurnsLeft			= buildQueue:GetTurnsLeft( row.ProjectType ), 
				Disabled			= isDisabled, 
				Cost				= iProductionCost, 
				Progress			= iProductionProgress,
				IsCurrentProduction = row.Hash == m_CurrentProductionHash,
				IsRepeatable		= row.MaxPlayerInstances ~= 1 and true or false,
			});
		end
	end

	return new_data;
end

-- ===========================================================================
function ShowHideDisabled()
	m_showDisabled = not m_showDisabled;
	Refresh();
end

-- ===========================================================================
-- Handle r-click on any entry: default behavior is to view the pedia for that item
function RightClickProductionItem(sItemType:string)
	LuaEvents.OpenCivilopedia(sItemType);
end

-- ===========================================================================
--	LUA Event
-- ===========================================================================
function OnCityPanelChooseProduction()
	if (ContextPtr:IsHidden()) then
		Refresh();
	else
		if (m_tabs.selectedControl ~= m_productionTab) then
			m_tabs.SelectTab(m_productionTab);
		end
	end
end

-- ===========================================================================
--	LUA Event
-- ===========================================================================
function OnNotificationPanelChooseProduction()
	if ContextPtr:IsHidden() then
		Open();
		if GetQueueSize(m_pCity) > 1 or UserConfiguration.IsAutoProdQueueEnabled() then
			m_tabs.SelectTab(m_queueTab);
		else
			m_tabs.SelectTab(m_productionTab);
		end
		SRA_AnnounceIfPending();	-- ScreenReaderAccess
	end
end

-- ===========================================================================
--	LUA Event
-- ===========================================================================
function OnCityPanelChoosePurchase()
	if (ContextPtr:IsHidden()) then
		Refresh();
		OnTabChangePurchase();
		m_tabs.SelectTab(m_purchaseTab);
	else
		if (m_tabs.selectedControl ~= m_purchaseTab) then
			OnTabChangePurchase();
			m_tabs.SelectTab(m_purchaseTab);	
		end
	end
end

-- ===========================================================================
--	LUA Event
-- ===========================================================================
function OnCityPanelChoosePurchaseFaith()
	if (ContextPtr:IsHidden()) then
		Refresh();
		OnTabChangePurchaseFaith();
		m_tabs.SelectTab(m_faithTab);
	else
		if (m_tabs.selectedControl ~= m_faithTab) then
			OnTabChangePurchaseFaith();
			m_tabs.SelectTab(m_faithTab);	
		end
	end
end

-- ===========================================================================
--	LUA Event
--	Outside source is signaling production should be closed if open.
-- ===========================================================================
function OnProductionClose()
	if not ContextPtr:IsHidden() then
		Close();
	end
end

-- ===========================================================================
--	LUA Event
--	Production opened from city banner (anchored to world view)
-- ===========================================================================
function OnCityBannerManagerProductionToggle()
	if(ContextPtr:IsHidden()) then
		Open();
		if GetQueueSize(m_pCity) > 1 or UserConfiguration.IsAutoProdQueueEnabled() then
			m_tabs.SelectTab(m_queueTab);
		else
			m_tabs.SelectTab(m_productionTab);
		end
		SRA_AnnounceIfPending();	-- ScreenReaderAccess
	else
		Close();
	end
end

-- ===========================================================================
--	LUA Event
--	Production opened from city information panel
-- ===========================================================================
function OnCityPanelProductionOpen()
	Open();
	if GetQueueSize(m_pCity) > 1 or UserConfiguration.IsAutoProdQueueEnabled() then
		m_tabs.SelectTab(m_queueTab);
	else
		m_tabs.SelectTab(m_productionTab);
	end
	SRA_AnnounceIfPending();	-- ScreenReaderAccess
end

-- ===========================================================================
--	LUA Event
--	Production opened from city information panel - Purchase with faith check
-- ===========================================================================
function OnCityPanelPurchaseFaithOpen()
	Open();
	m_tabs.SelectTab(m_faithTab);
	SRA_AnnounceIfPending();	-- ScreenReaderAccess
end

-- ===========================================================================
--	LUA Event
--	Production opened from city information panel - Purchase with gold check
-- ===========================================================================
function OnCityPanelPurchaseGoldOpen()
	Open();
	m_tabs.SelectTab(m_purchaseTab);
	SRA_AnnounceIfPending();	-- ScreenReaderAccess
end
-- ===========================================================================
--	LUA Event
--	Production opened from a placement
-- ===========================================================================
function OnStrategicViewMapPlacementProductionOpen( bWasCancelled:boolean )
	if m_isQueueOpen then
		Open();
		m_tabs.SelectTab(m_queueTab);
	elseif m_isManagerOpen then
		Open();
		m_tabs.SelectTab(m_managerTab);
	elseif bWasCancelled then
		Open();
	end
	local placementKey:string = m_srPlacementKey;		-- ScreenReaderAccess
	local selected:table = UI.GetHeadSelectedCity();
	if selected == nil or selected:GetID() ~= m_srPlacementCity then placementKey = nil; end		-- another city: its list starts afresh
	m_srPlacementKey = nil;
	m_srPlacementCity = nil;
	-- ScreenReaderAccess: the game reopens the panel after a placement only in queue mode (like CloseAfterNewProduction keeps it
	-- open there). The placed item has left the list, so the old focus is stale: announce afresh (a fresh focus, the new current
	-- production in the title) instead of leaving Enter on a vanished item ("Item no longer available").
	if not bWasCancelled and m_srActive and not ContextPtr:IsHidden() then m_srAnnouncePending = true; end
	SRA_AnnounceIfPending( false, bWasCancelled and placementKey or nil, true );		-- a cancelled placement: the focus returns to the item
end

-- ===========================================================================
--	LUA Event
-- ===========================================================================
function OnTutorialProductionOpen()
	Open();
end

-- ===========================================================================
--	LUA Event
-- ===========================================================================
function OnProductionOpenForQueue()
	Open();
	SRA_AnnounceIfPending();	-- ScreenReaderAccess
end

-- ===========================================================================
--	LUA Event
-- ===========================================================================
function OnCityPanelPurchasePlot()
	Close();
end

-- ===========================================================================
--	LUA Event
--	Set cached values back after a hotload.
-- ===========================================================================
function OnGameDebugReturn( context:string, contextTable:table )
	if context ~= RELOAD_CACHE_ID then return; end

	local isHidden:boolean = contextTable["isHidden"]; 
	if not isHidden then
		Refresh();

		local listMode:number = contextTable["listMode"];
		if listMode then
			if listMode == LISTMODE.PRODUCTION then
				m_tabs.SelectTab( m_productionTab );
			elseif listMode == LISTMODE.PURCHASE_GOLD then
				m_tabs.SelectTab( m_purchaseTab );
			elseif listMode == LISTMODE.PURCHASE_FAITH then
				m_tabs.SelectTab( m_faithTab );
			elseif listMode == LISTMODE.PROD_QUEUE then
				m_tabs.SelectTab( m_queueTab );
			end
		end
	end
end

-- ===========================================================================
-- Begin ScreenReaderAccess change: keyboard list of the production items.
-- Items are rebuilt from the panel's data at key time, in the order the panel shows them for the current tab:
-- Production/Queue: repairs, then districts with their buildings, wonders, units, projects; Purchase tabs: districts,
-- buildings, units. Only what can be built (bought) is listed; a toggle item at the end shows the rest (ProductionText_Arrange).
-- Tab cycles the panel's tabs. Corps/armies and queue editing are not covered.
-- ===========================================================================
local m_srList:table = nil;
local m_srHintSaid:boolean = false;		-- "Space for description" is said once per session
local m_srShowUnavailable:boolean = false;		-- the toggle item: unavailable items are listed after it (kept for the session, all tabs)

-- GetData() is expensive and is called on every key; cache it per Refresh (View sets it, Open/Close clear it).
local function SRA_Data()
	if m_srData == nil then m_srData = GetData(); end
	return m_srData;
end

local function SRA_IsPurchaseMode( mode:number )
	return mode == LISTMODE.PURCHASE_GOLD or mode == LISTMODE.PURCHASE_FAITH;
end

local function SRA_Balance( yield:string )
	local pPlayer:table = Players[ Game.GetLocalPlayer() ];
	if pPlayer == nil then return 0; end
	if yield == "YIELD_GOLD" then return math.floor( pPlayer:GetTreasury():GetGoldBalance() ); end
	return math.floor( pPlayer:GetReligion():GetFaithBalance() );
end

-- Red failure lines of a tooltip; skipFunds drops the "not enough gold/faith" lines (spoken separately).
local function SRA_Reasons( kItem:table, skipFunds:boolean )
	local reasons:table = {};
	local funds1:string = CleanTextForSpeech( Locale.Lookup( "LOC_BUILDING_INSUFFICIENT_FUNDS" ) );
	local funds2:string = CleanTextForSpeech( Locale.Lookup( "LOC_BUILDING_INSUFFICIENT_FAITH" ) );
	for reason in string.gmatch( kItem.ToolTip or "", "%[COLOR:Red%](.-)%[ENDCOLOR%]" ) do
		local text:string = CleanTextForSpeech( reason );
		if not ( skipFunds and ( text == funds1 or text == funds2 ) ) then table.insert( reasons, text ); end
	end
	return table.concat( reasons, ", " );
end

-- Space: "Settler: Used to found new cities. <rest of the tooltip>". The game's tooltips bury the description after the stats
-- (or leave it out of the first lines), so it is looked up in the database and spoken first.
local function SRA_Detail( kItem:table )
	local row:table = GameInfo.Units[ kItem.Hash ] or GameInfo.Buildings[ kItem.Hash ] or GameInfo.Districts[ kItem.Hash ] or GameInfo.Projects[ kItem.Hash ];
	local text:string = SRDescriptionFirst( kItem.Name, row ~= nil and row.Description or nil, kItem.ToolTip );
	-- districts: where it fits best (PlacementScan, cached per city and turn; only computed here, when asked)
	local district:table = GameInfo.Districts[ kItem.Hash ];
	local city:table = UI.GetHeadSelectedCity();
	if district ~= nil and city ~= nil and district.OnePerCity and not kItem.HasBeenBuilt then
		local ok:boolean, advice = pcall( function() return DistrictAdvice_BestSpot( DistrictAdvice_Entry( city, kItem.Hash ) ); end );
		if ok and advice ~= nil then text = text .. ". " .. advice; end
	end
	return text;
end

local function SRA_TurnsText( turns:number )
	if turns == nil then return nil; end
	if turns == -1 then return "never completes"; end
	return turns .. ( turns == 1 and " turn" or " turns" );
end

-- Space on a repair item: what is repaired and what it costs, not the whole district text with its adjacency lines.
local function SRA_RepairDetail( kItem:table, kind:string )
	local name:string = Locale.Lookup( kItem.Name );
	local text:string = "Repairs the pillaged " .. name .. ( kind == "district" and " district" or "" ) .. ", restoring what it produces";
	local turns:string = SRA_TurnsText( kItem.TurnsLeft );
	if turns ~= nil then text = text .. ". " .. turns; end
	if kItem.Cost ~= nil and kItem.Cost > 0 then text = text .. ", " .. kItem.Cost .. " production"; end
	return text;
end

local function SRA_Item( kItem:table, kind:string, section:string, owner:string )
	local name:string = Locale.Lookup( kItem.Name );
	if kItem.Repair then name = "Repair " .. name; end		-- a pillaged building or district: the item repairs it
	local parts:table = { name };
	if owner ~= nil then table.insert( parts, "in " .. owner ); end
	local built:boolean = kind == "district" and kItem.HasBeenBuilt and not kItem.Repair and not kItem.Contaminated
		and kItem.Progress == 0 and kItem.IsComplete == true and GameInfo.Districts[kItem.Type].OnePerCity == true;
	local reasons:string = SRA_Reasons( kItem, false );
	local recommended:boolean = m_kRecommendedItems ~= nil and m_kRecommendedItems[kItem.Hash] ~= nil;
	if built then
		table.insert( parts, "already built" );
	elseif kItem.Disabled then
		table.insert( parts, "unavailable" .. ( reasons ~= "" and ( ": " .. reasons ) or "" ) );
	else
		if kind == "district" or kind == "wonder" then table.insert( parts, kind ); end
		local turns:string = SRA_TurnsText( kItem.TurnsLeft );
		if turns ~= nil then table.insert( parts, turns ); end
		local cost:number = kItem.Cost;
		if kind == "unit" then
			-- kItem.Cost is the corps/army cost when those are available; the standard cost is what Enter builds.
			local city:table = UI.GetHeadSelectedCity();
			local row:table = GameInfo.Units[ kItem.Type ];
			if city ~= nil and row ~= nil then cost = city:GetBuildQueue():GetUnitCost( row.Index ); end
		end
		if cost ~= nil and cost > 0 then
			local costText:string = tostring( cost );
			if kItem.Progress ~= nil and kItem.Progress > 0 then costText = kItem.Progress .. " of " .. costText; end
			table.insert( parts, costText .. " production" );
		end
		if recommended then table.insert( parts, "recommended" ); end
	end
	local detailItem:table = kItem;
	return {
		key = kind .. ":" .. tostring( kItem.Hash ),
		kind = kind,
		section = section,
		text = table.concat( parts, ", " ),
		data = kItem,
		choosable = not ( kItem.Disabled or built ),
		built = built,
		reason = built and "Already built" or ( "Can't build " .. name .. ( reasons ~= "" and ( ": " .. reasons ) or "" ) ),
		recommended = recommended,
		repair = kItem.Repair == true,
		detail = function()
			if detailItem.Repair then return SRA_RepairDetail( detailItem, kind ); end
			return SRA_Detail( detailItem );
		end,
	};
end

-- Purchase tabs: "Archer, 120 gold, can afford" / "can't afford, 30 more needed" / "unavailable: reason".
local function SRA_PurchaseItem( kItem:table, kind:string, section:string )
	local name:string = Locale.Lookup( kItem.Name );
	local isGold:boolean = kItem.Yield == "YIELD_GOLD";
	local currency:string = isGold and "gold" or "faith";
	local label:string = kind;
	if kind == "building" and GameInfo.Buildings[ kItem.Type ] ~= nil and GameInfo.Buildings[ kItem.Type ].IsWonder then label = "wonder"; end
	local parts:table = { name };
	if label == "district" or label == "wonder" then table.insert( parts, label ); end
	table.insert( parts, kItem.Cost .. " " .. currency );
	local other:string = SRA_Reasons( kItem, true );
	local missing:number = kItem.Cost - SRA_Balance( kItem.Yield );
	if not kItem.Disabled then
		table.insert( parts, "can afford" );
	elseif kItem.CantAfford then
		table.insert( parts, "can't afford, " .. math.max( missing, 1 ) .. " more needed" .. ( other ~= "" and ( ", " .. other ) or "" ) );
	else
		table.insert( parts, "unavailable" .. ( other ~= "" and ( ": " .. other ) or "" ) );
	end
	local detailItem:table = kItem;
	return {
		key = "buy:" .. kind .. ":" .. tostring( kItem.Hash ),
		kind = kind,
		purchase = true,
		section = section,
		text = table.concat( parts, ", " ),
		data = kItem,
		choosable = not kItem.Disabled,
		cantAfford = kItem.CantAfford == true,
		reason = "Can't buy " .. name .. ( kItem.CantAfford and ( ": not enough " .. currency .. ", " .. math.max( missing, 1 ) .. " more needed" ) or "" )
			.. ( other ~= "" and ( ": " .. other ) or "" ),
		detail = function() return SRA_Detail( detailItem ); end,
	};
end

-- The panel's items in the game's category order, unavailable ones included (SRA_GetItems arranges them).
local function SRA_BuildAllItems()
	local items:table = {};
	local data:table = SRA_Data();
	if data == nil then return items; end
	local mode:number = m_CurrentListMode;

	if SRA_IsPurchaseMode( mode ) then
		local yield:string = ( mode == LISTMODE.PURCHASE_GOLD ) and "YIELD_GOLD" or "YIELD_FAITH";
		local districtsSection:string = Locale.Lookup( "LOC_HUD_DISTRICTS" );
		for _, kDistrict in ipairs( data.DistrictPurchases ) do
			if kDistrict.Yield == yield then table.insert( items, SRA_PurchaseItem( kDistrict, "district", districtsSection ) ); end
		end
		local buildingsSection:string = Locale.Lookup( "LOC_HUD_BUILDINGS" );
		for _, kBuilding in ipairs( data.BuildingPurchases ) do
			if kBuilding.Yield == yield then table.insert( items, SRA_PurchaseItem( kBuilding, "building", buildingsSection ) ); end
		end
		local unitsSection:string = Locale.Lookup( "LOC_TECH_FILTER_UNITS" );
		for _, kUnit in ipairs( data.UnitPurchases ) do
			if kUnit.Yield == yield then table.insert( items, SRA_PurchaseItem( kUnit, "unit", unitsSection ) ); end
		end
		return items;
	end

	local districtsSection:string = Locale.Lookup( "LOC_HUD_DISTRICTS_BUILDINGS" );
	local builtDistricts:table = {};		-- "City Center, already built" rows go after everything that can be built in this section
	for _, kDistrict in ipairs( data.DistrictItems ) do
		local districtName:string = Locale.Lookup( kDistrict.Name );
		local districtItem:table = SRA_Item( kDistrict, "district", districtsSection, nil );
		if districtItem.built then table.insert( builtDistricts, districtItem ); else table.insert( items, districtItem ); end
		local districtType:string = kDistrict.Type;
		if GameInfo.DistrictReplaces[ districtType ] ~= nil then districtType = GameInfo.DistrictReplaces[ districtType ].ReplacesDistrictType; end
		for _, kBuilding in ipairs( data.BuildingItems ) do
			if not kBuilding.IsWonder and kBuilding.PrereqDistrict == districtType then
				table.insert( items, SRA_Item( kBuilding, "building", districtsSection, districtName ) );
			end
		end
	end
	for _, districtItem in ipairs( builtDistricts ) do table.insert( items, districtItem ); end
	local wondersSection:string = Locale.Lookup( "LOC_HUD_CITY_WONDERS" );
	for _, kBuilding in ipairs( data.BuildingItems ) do
		if kBuilding.IsWonder then table.insert( items, SRA_Item( kBuilding, "wonder", wondersSection, nil ) ); end
	end
	-- Same conditions as PopulateUnits / PopulateProjects: the Queue tab also lists the unit and repeatable
	-- project that are currently in production.
	local queueMode:boolean = ( mode == LISTMODE.PROD_QUEUE );
	local unitsSection:string = Locale.Lookup( "LOC_TECH_FILTER_UNITS" );
	for _, kUnit in ipairs( data.UnitItems ) do
		if queueMode or not kUnit.IsCurrentProduction then table.insert( items, SRA_Item( kUnit, "unit", unitsSection, nil ) ); end
	end
	local projectsSection:string = Locale.Lookup( "LOC_HUD_PROJECTS" );
	for _, kProject in ipairs( data.ProjectItems ) do
		if not kProject.IsCurrentProduction or ( queueMode and kProject.IsRepeatable ) then
			table.insert( items, SRA_Item( kProject, "project", projectsSection, nil ) );
		end
	end
	return items;
end

-- Repairs on top, then what can be built (bought), then the toggle for the rest (ProductionText_Arrange).
local function SRA_GetItems()
	return ProductionText_Arrange( SRA_BuildAllItems(), m_srShowUnavailable, SRA_IsPurchaseMode( m_CurrentListMode ) );
end

-- Outcome of the last Enter. The game applies requests a moment later, so the announcement is made from the
-- events that report the change (and at once when the state already changed); nothing is announced if nothing happened.
local function SRA_ResolvePending( fromEvent:boolean )
	local pending:table = m_srPending;
	if pending == nil then return; end
	local city:table = UI.GetHeadSelectedCity();
	if pending.kind == "produce" then
		if city == nil then return; end
		local queue:table = city:GetBuildQueue();
		local changed:boolean = fromEvent or queue:GetCurrentProductionTypeHash() ~= pending.hash0 or queue:GetSize() ~= pending.size0;
		if not changed then return; end
		m_srPending = nil;
		local text:string = ( pending.queueMode and "Queued " or "Producing " ) .. pending.name;
		if pending.repair then text = ( pending.queueMode and "Queued repair of " or "Repairing " ) .. pending.name; end
		if pending.turns ~= nil and not pending.queueMode then text = text .. ", " .. pending.turns; end
		if not pending.repair then text = ProductionText_Replaces( text, pending.replaces, pending.name ); end
		if not m_srActive then text = text .. ". Production closed"; end		-- the panel closed itself (units, projects)
		OutputMessageToScreenReader( text );
	elseif pending.kind == "buy" then
		local balance:number = SRA_Balance( pending.yield );
		if balance >= pending.before then return; end
		m_srPending = nil;
		OutputMessageToScreenReader( "Bought " .. pending.name .. ", " .. balance .. ( pending.yield == "YIELD_GOLD" and " gold" or " faith" ) .. " left" .. ( m_srActive and "" or ". Production closed" ) );
	end
end

-- Name of a unit at war with us standing on the tile of the district (or the building's district) a repair item would repair, else nil.
local function SRA_EnemyOnRepairTile( city:table, kItem:table, kind:string )
	local result:string = nil;
	pcall( function()
		local districtRow:table = nil;
		if kind == "district" then districtRow = GameInfo.Districts[ kItem.Type ];
		else
			local b:table = GameInfo.Buildings[ kItem.Hash ];
			if b ~= nil and b.PrereqDistrict ~= nil then districtRow = GameInfo.Districts[ b.PrereqDistrict ]; end
		end
		if districtRow == nil then return; end
		local district:table = city:GetDistricts():GetDistrict( districtRow.Index );
		if district == nil then return; end
		local me:number = Game.GetLocalPlayer();
		for _, unit in ipairs( Units.GetUnitsInPlot( Map.GetPlot( district:GetX(), district:GetY() ) ) ) do
			if unit:GetOwner() ~= me and Players[me]:GetDiplomacy():IsAtWarWith( unit:GetOwner() ) then
				result = "an enemy " .. Locale.Lookup( GameInfo.Units[ unit:GetUnitType() ].Name );
				return;
			end
		end
	end );
	return result;
end

local function SRA_OnActivate( item:table )
	if item.toggle then
		-- the list is rebuilt at the next key; the focus stays on the toggle (same key)
		m_srShowUnavailable = not m_srShowUnavailable;
		OutputMessageToScreenReader( ProductionText_ToggleSaid( item.count, m_srShowUnavailable ) );
		return;
	end
	local city:table = UI.GetHeadSelectedCity();
	if city == nil then return; end
	local kItem:table = item.data;
	local name:string = Locale.Lookup( kItem.Name );
	m_srPending = nil;

	if item.purchase then
		local before:number = SRA_Balance( kItem.Yield );
		if item.kind == "district" then PurchaseDistrict( city, kItem );
		elseif item.kind == "building" then PurchaseBuilding( city, kItem );
		else PurchaseUnit( city, kItem ); end
		local mode:number = UI.GetInterfaceMode();
		if mode == InterfaceModeTypes.DISTRICT_PLACEMENT or mode == InterfaceModeTypes.BUILDING_PLACEMENT then
			-- The game switched to placement mode: the hub's placement browser (InGameAccess) takes over and speaks.
			Close();
			return;
		end
		Close();
		m_srPending = { kind = "buy", name = name, yield = kItem.Yield, before = before };
		SRA_ResolvePending( false );
		return;
	end

	local queueMode:boolean = m_isQueueOpen or m_isManagerOpen;
	-- A selected queue item makes the game's build functions only deselect it (CheckQueueItemSelected).
	if m_kSelectedQueueItem.Index ~= -1 or m_SelectedManagerIndex ~= -1 then
		if item.kind == "district" then ZoneDistrict( city, kItem );
		elseif item.kind == "wonder" or item.kind == "building" then BuildBuilding( city, kItem );
		elseif item.kind == "unit" then BuildUnit( city, kItem );
		else AdvanceProject( city, kItem ); end
		OutputMessageToScreenReader( "Queue selection cleared, choose again" );
		return;
	end

	local queue:table = city:GetBuildQueue();
	m_srPending = {
		kind = "produce", name = name, queueMode = queueMode, repair = ( kItem.Repair == true ), turns = SRA_TurnsText( kItem.TurnsLeft ),
		hash0 = queue:GetCurrentProductionTypeHash(), size0 = queue:GetSize(),
	};
	if not queueMode and m_srPending.hash0 ~= nil and m_srPending.hash0 ~= 0 and m_srPending.hash0 ~= kItem.Hash then
		local oldRow:table = GameInfo.Buildings[m_srPending.hash0] or GameInfo.Districts[m_srPending.hash0] or GameInfo.Units[m_srPending.hash0] or GameInfo.Projects[m_srPending.hash0];
		if oldRow ~= nil then m_srPending.replaces = Locale.Lookup( oldRow.Name ); end
	end
	-- A repair needs no placement: if the game refuses it (e.g. an enemy unit on the district), say why instead of closing silently.
	if kItem.Repair and ( item.kind == "district" or item.kind == "building" ) then
		-- The engine accepts the order (CanProduce is true) but drops it silently while an enemy unit stands on the district:
		-- check that tile ourselves.
		local enemyName:string = SRA_EnemyOnRepairTile( city, kItem, item.kind );
		if enemyName ~= nil then
			m_srPending = nil;
			OutputMessageToScreenReader( "Cannot repair " .. name .. ": " .. enemyName .. " stands on the district" );
			return;
		end
		local ok:boolean, canProduce, results = pcall( function() return queue:CanProduce( kItem.Hash, false, true ); end );
		if ok and canProduce == false then
			local why:table = {};
			local fr:table = results ~= nil and results[CityCommandResults.FAILURE_REASONS] or nil;
			if fr ~= nil then for _, v in ipairs( fr ) do table.insert( why, CleanTextForSpeech( Locale.Lookup( v ) ) ); end end
			m_srPending = nil;
			OutputMessageToScreenReader( "Cannot repair " .. name .. ( #why > 0 and ( ": " .. table.concat( why, ", " ) ) or "" ) );
			return;
		end
	end
	if item.kind == "district" or item.kind == "wonder" then
		if item.kind == "district" then ZoneDistrict( city, kItem ); else BuildBuilding( city, kItem ); end
		local mode:number = UI.GetInterfaceMode();
		if mode == InterfaceModeTypes.DISTRICT_PLACEMENT or mode == InterfaceModeTypes.BUILDING_PLACEMENT then
			-- set after the call: the game closes the panel while entering placement, and Close clears the key
			m_srPlacementKey = ProductionText_Identity( item.key );
			m_srPlacementCity = city:GetID();
			-- The game switched to placement mode and closed the panel: the hub's placement browser (InGameAccess)
			-- takes over, speaks, and reports the production once the tile is chosen.
			m_srPending = nil;
			return;
		end
		-- No placement needed (already placed): it went into the queue.
	elseif item.kind == "unit" then
		BuildUnit( city, kItem );
		CloseAfterNewProduction();
	elseif item.kind == "building" then
		BuildBuilding( city, kItem );
	elseif item.kind == "project" then
		AdvanceProject( city, kItem );
		CloseAfterNewProduction();
	end
	SRA_ResolvePending( false );
end

-- Escape: what the game's KeyHandler does (deselect the queue item / cancel the manager selection, else close).
local function SRA_OnClose()
	if m_kSelectedQueueItem.Index ~= -1 then
		DeselectItem();
		OutputMessageToScreenReader( "Queue selection cleared" );
	elseif m_SelectedManagerIndex ~= -1 then
		LuaEvents.ProductionPanel_CancelManagerSelection();
		OutputMessageToScreenReader( "Queue selection cleared" );
	else
		local willClose:boolean = Controls.SlideIn:IsStopped();
		if willClose then LuaEvents.SRA_ProductionEscape(); end		-- ScreenReaderAccess: the hub returns to the city report this was opened from
		Close();
		if willClose then OutputMessageToScreenReader( "Production closed" ); end
	end
end

local function SRA_Announce( keepGuard:boolean, keepKey:string, queueTitle:boolean )
	local city:table = UI.GetHeadSelectedCity();
	if city == nil then return; end
	local mode:number = m_CurrentListMode;
	local title:string = Locale.Lookup( city:GetName() );
	if mode == LISTMODE.PURCHASE_GOLD then
		title = title .. ", purchase with gold, " .. SRA_Balance( "YIELD_GOLD" ) .. " gold";
	elseif mode == LISTMODE.PURCHASE_FAITH then
		title = title .. ", purchase with faith, " .. SRA_Balance( "YIELD_FAITH" ) .. " faith";
	else
		title = title .. ", choose production";
		local queue:table = city:GetBuildQueue();
		local hash:number = queue ~= nil and queue:GetCurrentProductionTypeHash() or 0;
		if hash ~= nil and hash ~= 0 then
			local row:table = GameInfo.Buildings[hash] or GameInfo.Districts[hash] or GameInfo.Units[hash] or GameInfo.Projects[hash];
			if row ~= nil then title = title .. ", " .. ProductionText_Current( Locale.Lookup( row.Name ), SRA_TurnsText( queue:GetTurnsLeft() ) ); end
		end
		if mode == LISTMODE.PROD_QUEUE then title = title .. ", queue"; end
	end
	if not m_srHintSaid then m_srHintSaid = true; title = title .. ", " .. SRKey( "Space" ) .. " for description"; end
	-- Start on the advisor's recommended item when it can be built and needs no placement (a unit, building or project: a blind
	-- Enter-Enter then builds what the title announces); a recommended wonder or district is only named in the title (a second
	-- Enter would start its placement by accident). Otherwise on the first item that can be built (the top of the list).
	local firstChoosable = nil;
	local currentKey = nil;
	local carriedKey = nil;
	local currentHash:number = 0;
	do
		local q:table = city:GetBuildQueue();
		if q ~= nil then currentHash = q:GetCurrentProductionTypeHash() or 0; end
	end
	local recommendedKey = nil;
	local recommendedName = nil;
	for _, item in ipairs( SRA_GetItems() ) do
		if item.choosable then
			if firstChoosable == nil then firstChoosable = item.key; end
			if currentKey == nil and currentHash ~= 0 and not item.purchase and item.data ~= nil and item.data.Hash == currentHash then currentKey = item.key; end
			if carriedKey == nil and keepKey ~= nil and ProductionText_Identity( item.key ) == keepKey then carriedKey = item.key; end
			if item.recommended and recommendedName == nil and item.data ~= nil and item.data.Name ~= nil then
				recommendedName = Locale.Lookup( item.data.Name );
				recommendedKey = item.key;		-- also a district or wonder: the title names it, so focus must land on it (the open guard covers a double Enter)
			end
		end
	end
	if recommendedName ~= nil and mode ~= LISTMODE.PURCHASE_GOLD and mode ~= LISTMODE.PURCHASE_FAITH then
		title = title .. ", Recommended: " .. recommendedName;
	end
	m_srList.Reset();
	local firstIsRepair = false;
	for _, item in ipairs( SRA_GetItems() ) do
		if item.choosable then firstIsRepair = item.data ~= nil and item.data.Repair == true; break; end
	end
	-- a repair at the top stays focused: it is urgent
	if recommendedKey ~= nil and not firstIsRepair and mode ~= LISTMODE.PURCHASE_GOLD and mode ~= LISTMODE.PURCHASE_FAITH then firstChoosable = recommendedKey; end
	-- the item focused before a Tab stays focused when the new tab lists it; else the production in progress (so a quick Enter
	-- cannot replace it by accident); a repair at the top and the recommendation come first otherwise
	if currentKey ~= nil and not firstIsRepair and mode ~= LISTMODE.PURCHASE_GOLD and mode ~= LISTMODE.PURCHASE_FAITH then firstChoosable = currentKey; end
	if carriedKey ~= nil then firstChoosable = carriedKey; end
	m_srList.Open( title, firstChoosable, false, keepGuard, queueTitle );
end

-- Tab / Control+Tab: next / previous tab of the panel (Production, Queue, Purchase gold, Purchase faith, wraps), like clicking it.
local function SRA_SwitchTab( delta:number )
	local tabs:table = { { mode = LISTMODE.PRODUCTION, tab = m_productionTab } };
	if m_queueTab == Controls.QueueTab and not m_isTutorialRunning and not m_tutorialTestMode then
		table.insert( tabs, { mode = LISTMODE.PROD_QUEUE, tab = m_queueTab } );
	end
	if GameCapabilities.HasCapability( "CAPABILITY_GOLD" ) then table.insert( tabs, { mode = LISTMODE.PURCHASE_GOLD, tab = m_purchaseTab } ); end
	if GameCapabilities.HasCapability( "CAPABILITY_FAITH" ) then table.insert( tabs, { mode = LISTMODE.PURCHASE_FAITH, tab = m_faithTab } ); end
	local current:number = 1;
	for i, entry in ipairs( tabs ) do
		if entry.mode == m_CurrentListMode then current = i; end
	end
	local nextEntry:table = tabs[ ( current - 1 + delta ) % #tabs + 1 ];
	m_srPending = nil;
	local keepKey:string = ProductionText_Identity( m_srList.GetFocusKey() );
	m_tabs.SelectTab( nextEntry.tab );
	SRA_Announce( true, keepKey );
	m_srList.DisarmGuard();		-- Tab is deliberate: an Enter right after it chooses (the guard only covers a double Enter on the real open)
end
local function SRA_NextTab() SRA_SwitchTab( 1 ); end
local function SRA_PrevTab() SRA_SwitchTab( -1 ); end

-- Called by the handlers that open the panel, once they have selected the tab (a SetUpdate callback never ran here).
function SRA_AnnounceIfPending( keepGuard:boolean, keepKey:string, queueTitle:boolean )
	if not m_srAnnouncePending then return; end
	m_srAnnouncePending = false;
	local ok:boolean, err = xpcall( function() SRA_Announce( keepGuard, keepKey, queueTitle ); end, KeyNavErrorHandler );
	if not ok then print( "ProductionPanel announce error: " .. tostring(err) ); end
end

-- Events that report the outcome of Enter (see SRA_ResolvePending).
function SRA_OnProductionChanged()
	if m_srPending ~= nil and m_srPending.kind == "produce" then
		local ok:boolean, err = xpcall( function() SRA_ResolvePending( true ); end, KeyNavErrorHandler );
		if not ok then print( "ProductionPanel pending error: " .. tostring(err) ); end
	end
end
function SRA_OnBalanceChanged()
	if m_srPending ~= nil and m_srPending.kind == "buy" then
		local ok:boolean, err = xpcall( function() SRA_ResolvePending( true ); end, KeyNavErrorHandler );
		if not ok then print( "ProductionPanel pending error: " .. tostring(err) ); end
	end
end
-- V (diplomacy list, a hub action) while the chooser is open: close the chooser first so its list and the hub's list do not fight over the keys.
local m_srDiploAction:number = Input.GetActionId("KeyNavDiplomacy");
function SRA_OnInputAction( actionId:number )
	if actionId == m_srDiploAction and not ContextPtr:IsHidden() and m_srActive then Close(); end
end
function SRA_OnOpenDiplomacy()
	if not ContextPtr:IsHidden() then Close(); end
end
-- End ScreenReaderAccess change

-- ===========================================================================
--	Keyboard INPUT Handler
-- ===========================================================================
function KeyHandler( key:number )
	if (key == Keys.VK_ESCAPE) then 
		if m_kSelectedQueueItem.Index ~= -1 then
			DeselectItem();
		elseif m_SelectedManagerIndex ~= -1 then
			LuaEvents.ProductionPanel_CancelManagerSelection();
		else
			Close(); 
		end
		return true; 
	end
	return false;
end

-- ===========================================================================
--	UI Event
-- ===========================================================================
function OnInputHandler( pInputStruct:table )
	if m_srList ~= nil and m_srList.HandleInput( pInputStruct ) then return true; end		-- ScreenReaderAccess
	local uiMsg = pInputStruct:GetMessageType();
	if uiMsg == KeyEvents.KeyUp then 
		return KeyHandler( pInputStruct:GetKey() ); 
	end;
	return false;
end

-- ===========================================================================
--	UI Event
-- ===========================================================================
function OnInit( isReload:boolean )
	if isReload then		
		LuaEvents.GameDebug_GetValues( RELOAD_CACHE_ID );		
	end
end

-- ===========================================================================
--	UI Event
-- ===========================================================================
function OnShutdown()
	SRUnlistenAll();		-- ScreenReaderAccess: every listener was added with SRListen (stale ones kept firing after a hot reload)

	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID,  "isHidden",		ContextPtr:IsHidden() );
	LuaEvents.GameDebug_AddValue(RELOAD_CACHE_ID,  "listMode",		m_CurrentListMode );	
end

-- ===========================================================================
-- ===========================================================================
function CreateCorrectTabs()
	local MAX_TAB_LABEL_WIDTH = 273;
	local productionLabelX = Controls.ProductionTab:GetTextControl():GetSizeX();
	local purchaseLabelX = Controls.PurchaseTab:GetTextControl():GetSizeX();
	local purchaseFaithLabelX = Controls.PurchaseFaithTab:GetTextControl():GetSizeX();
	local tabAnimControl;
	local tabArrowControl;
	local tabSizeX;
	local tabSizeY;

    Controls.ProductionTab:RegisterCallback( Mouse.eMouseEnter,	function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
    Controls.PurchaseTab:RegisterCallback( Mouse.eMouseEnter,	function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
    Controls.PurchaseFaithTab:RegisterCallback( Mouse.eMouseEnter,	function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
    Controls.MiniProductionTab:RegisterCallback( Mouse.eMouseEnter,	function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
    Controls.MiniPurchaseTab:RegisterCallback( Mouse.eMouseEnter,	function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
    Controls.MiniPurchaseFaithTab:RegisterCallback( Mouse.eMouseEnter,	function() UI.PlaySound("Main_Menu_Mouse_Over"); end);

	Controls.MiniProductionTab:SetHide(true);
	Controls.MiniPurchaseTab:SetHide(true);
	Controls.MiniPurchaseFaithTab:SetHide(true);
	Controls.ProductionTab:SetHide(true);
	Controls.PurchaseTab:SetHide(true);
	Controls.PurchaseFaithTab:SetHide(true);
	Controls.QueueTab:SetHide(true);
	Controls.ManagerTab:SetHide(true);
	Controls.MiniTabAnim:SetHide(true);
	Controls.MiniTabArrow:SetHide(true);
	Controls.TabAnim:SetHide(true);
	Controls.TabArrow:SetHide(true);

	local labelWidth = productionLabelX + purchaseLabelX;
	if GameCapabilities.HasCapability("CAPABILITY_FAITH") then 
		labelWidth = labelWidth + purchaseFaithLabelX;
	end
	local isQueueTabSet:boolean = false;
	if(labelWidth > MAX_TAB_LABEL_WIDTH) then
		tabSizeX = 44;
		tabSizeY = 44;
		Controls.MiniProductionTab:SetHide(false);
		Controls.MiniPurchaseTab:SetHide(false);
		Controls.MiniPurchaseFaithTab:SetHide(false);
		Controls.MiniTabAnim:SetHide(false);
		Controls.MiniTabArrow:SetHide(false);
		m_productionTab = Controls.MiniProductionTab;
		m_purchaseTab	= Controls.MiniPurchaseTab;
		m_faithTab		= Controls.MiniPurchaseFaithTab;
		tabAnimControl	= Controls.MiniTabAnim;
		tabArrowControl = Controls.MiniTabArrow;
	else
		isQueueTabSet = true;
		tabSizeX = 42;
		tabSizeY = 34;
		Controls.ProductionTab:SetHide(false);
		Controls.PurchaseTab:SetHide(false);
		Controls.PurchaseFaithTab:SetHide(false);
		if not m_isTutorialRunning and not m_tutorialTestMode then
			Controls.QueueTab:SetHide(false);
			Controls.ManagerTab:SetHide(false);
		end
		Controls.TabAnim:SetHide(false);
		Controls.TabArrow:SetHide(false);
		m_productionTab = Controls.ProductionTab;
		m_purchaseTab	= Controls.PurchaseTab;
		m_faithTab		= Controls.PurchaseFaithTab;
		m_queueTab		= Controls.QueueTab;
		m_managerTab	= Controls.ManagerTab;
		tabAnimControl	= Controls.TabAnim;
		tabArrowControl = Controls.TabArrow;
	end

	m_tabs = CreateTabs( Controls.TabRow, tabSizeX, tabSizeY, UI.GetColorValueFromHexLiteral(0xFF331D05) );
	m_tabs.AddTab( m_productionTab,	OnTabChangeProduction );
	if GameCapabilities.HasCapability("CAPABILITY_GOLD") then
		m_tabs.AddTab( m_purchaseTab,	OnTabChangePurchase );
	else
		Controls.PurchaseTab:SetHide(true);
		Controls.MiniPurchaseTab:SetHide(true);
	end
	if GameCapabilities.HasCapability("CAPABILITY_FAITH") then 
		m_tabs.AddTab( m_faithTab,	OnTabChangePurchaseFaith );
	else
		Controls.MiniPurchaseFaithTab:SetHide(true);
		Controls.PurchaseFaithTab:SetHide(true);
	end
	if isQueueTabSet and (not m_isTutorialRunning) and (not m_tutorialTestMode) then
		m_tabs.AddTab( m_queueTab,		OnTabChangeQueue );
		m_tabs.AddTab( m_managerTab,	OnTabChangeManager );
	end

	m_tabs.CenterAlignTabs(0, 350, 32);
	m_tabs.SelectTab( m_productionTab );
	m_tabs.AddAnimDeco(tabAnimControl, tabArrowControl);
end

---------------------------------------------------
function SetScrollPosition(modeIndex:number, scrollAmount:number)
	if m_PlayerScrollPositions[Game.GetLocalPlayer()] == nil then
		m_PlayerScrollPositions[Game.GetLocalPlayer()] = {};
	end

	local scrollPosTable:table = m_PlayerScrollPositions[Game.GetLocalPlayer()];

	scrollPosTable[modeIndex] = scrollAmount;
end

---------------------------------------------------
function GetScrollPosition(modeIndex:number)
	local scrollPosTable:table = m_PlayerScrollPositions[Game.GetLocalPlayer()];
	if scrollPosTable ~= nil then
		return scrollPosTable[modeIndex];
	end

	return 0;
end

-- ===========================================================================
function OnProductionListScrolled(scrollPanel:table, scrollAmount:number)
	if not ContextPtr:IsHidden() then
		SetScrollPosition(LISTMODE.PRODUCTION, scrollAmount);
	end
end

-- ===========================================================================
function OnPurchaseListScrolled(scrollPanel:table, scrollAmount:number)
	if not ContextPtr:IsHidden() then
		SetScrollPosition(LISTMODE.PURCHASE_GOLD, scrollAmount);
	end
end

-- ===========================================================================
function OnPurchaseFaithListScrolled(scrollPanel:table, scrollAmount:number)
	if not ContextPtr:IsHidden() then
		SetScrollPosition(LISTMODE.PURCHASE_FAITH, scrollAmount);
	end
end

-- ===========================================================================
function OnQueueListScrolled(scrollPanel:table, scrollAmount:number)
	if not ContextPtr:IsHidden() then
		SetScrollPosition(LISTMODE.PROD_QUEUE, scrollAmount);
	end
end

-- ===========================================================================
function OpenManager()
	m_isManagerOpen = true;
	LuaEvents.ProductionPanel_OpenManager();
end

-- ===========================================================================
function CloseManager()
	m_isManagerOpen = false;
	LuaEvents.ProductionPanel_CloseManager();
end

-- ===========================================================================
function CloseAfterNewProduction()
	if not m_isQueueOpen and not m_isManagerOpen then
		Close();
	end
end

-- ===========================================================================
function OpenQueue()
	m_isQueueOpen = true;
	Controls.QueueContainer:SetHide(false);
end

-- ===========================================================================
function RefreshView()
	local data = GetData();
	if data ~= nil then
		View(data);
	end
end

-- ===========================================================================
function CloseQueue()
	m_isQueueOpen = false;
	Controls.QueueContainer:SetHide(true);
end

-- ===========================================================================
function RefreshQueue(playerID, cityID)
	if m_isTutorialRunning or m_tutorialTestMode then
		return;
	end

	DeselectItem();

	local pCity:table = CityManager.GetCity(playerID, cityID);
	local pBuildQueue:table = pCity:GetBuildQueue();

	-- Subtract one so we don't count the current production as queued
	local offsetQueueSize:number = pBuildQueue:GetSize() - 1;
	UpdateQueueTabText(offsetQueueSize >= 0 and offsetQueueSize or 0);

	m_QueueInstanceIM:ResetInstances();

	-- Display queues items after the first which is shown as the current production
	for i = 1, MAX_QUEUE_SIZE do
		local entry:table = pBuildQueue:GetAt(i);
		local queueInstance:table = CreateQueueInstance( m_QueueInstanceIM, Controls.QueueStack, playerID, cityID, i, entry );
		queueInstance.Top:RegisterCallback( Mouse.eLClick, function() OnItemClicked( queueInstance, queueInstance.Top ); end );
		queueInstance.Top:RegisterCallback( Mouse.eRClick, function() UI.PlaySound("Play_UI_Click"); RemoveQueueItem(i); end );
		queueInstance.Top:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end );
		queueInstance.Num:SetText( tostring(i+1) );		-- Start at 2
	end

	UpdateDisabledButtons();
end

-- ===========================================================================
function DeselectItem()
	if m_kSelectedQueueItem.Parent ~= nil then
		local kParentControl:table = m_kSelectedQueueItem.Parent;
		if kParentControl.ProductionIcon ~= nil then
			kParentControl.ProductionIcon:SetAlpha(1.0);
		end
	end

	m_kSelectedQueueItem.Parent = nil;
	m_kSelectedQueueItem.Button = nil;
	m_kSelectedQueueItem.Index = -1;

	DisableMouseIcon();
	HighlightButtons(false);
end

-- ===========================================================================
function SelectItem( kParentControl:table, kButtonControl:table )
	if kParentControl ~= nil and kParentControl[FIELD_QUEUE_INDEX] then
		if kParentControl.ProductionIcon ~= nil then
			kParentControl.ProductionIcon:SetAlpha(SELECTED_ICON_ALPHA);
		end

		m_kSelectedQueueItem.Parent = kParentControl;
		m_kSelectedQueueItem.Button = kButtonControl;
		m_kSelectedQueueItem.Index = kParentControl[FIELD_QUEUE_INDEX];

		EnableMouseIcon(kParentControl[FIELD_ICON_TEXTURE]);
		HighlightButtons(true);
	end
end

-- ===========================================================================
function OnTrashClicked()
	if m_kSelectedQueueItem.Index ~= -1 then
		RemoveQueueItem(m_kSelectedQueueItem.Index);
	end
end

-- ===========================================================================
function UpdateDisabledButtons()
	for i=1, m_QueueInstanceIM.m_iCount, 1 do
		local instance:table = m_QueueInstanceIM:GetAllocatedInstance(i);
		if instance then 
			instance.Top:SetSelected(false);
			instance.Top:SetDisabled( instance[FIELD_QUEUE_INDEX] == -1 );
		end
	end
end

-- ===========================================================================
function OnItemClicked( kParentControl:table, kButtonControl:table )
	if m_kSelectedQueueItem.Index == -1 then
		SelectItem(kParentControl, kButtonControl);
	elseif m_kSelectedQueueItem.Index ~= kParentControl[FIELD_QUEUE_INDEX] then
		SwapQueueItem(m_kSelectedQueueItem.Index, kParentControl[FIELD_QUEUE_INDEX]);
	else
		DeselectItem();
	end
end

-- ===========================================================================
function HighlightButtons( bShouldHighlight:boolean )

	Controls.CurrentProductionButton:SetSelected(bShouldHighlight);

	for i=1, m_QueueInstanceIM.m_iCount, 1 do
		local instance:table = m_QueueInstanceIM:GetAllocatedInstance(i);
		if instance then
			if instance[FIELD_QUEUE_INDEX] ~= -1 then
				instance.Top:SetSelected(bShouldHighlight);
			end
		end
	end

	Controls.TrashButton:SetSelected(bShouldHighlight);
	Controls.TrashButton:SetDisabled(not bShouldHighlight);
end

-- ===========================================================================
function OnBuildingListSizeChanged(listIM:table, sizeY:number)
	local kListParent:table = listIM.m_ParentControl;
	if kListParent then
		kListParent[FIELD_LIST_BUILDING_SIZE_Y] = sizeY;
	end
end

-- ===========================================================================
function OnWonderListSizeChanged(listIM:table, sizeY:number)
	local kListParent:table = listIM.m_ParentControl;
	if kListParent then
		kListParent[FIELD_LIST_WONDER_SIZE_Y] = sizeY;
	end
end

-- ===========================================================================
function OnUnitListSizeChanged(listIM:table, sizeY:number)
	local kListParent:table = listIM.m_ParentControl;
	if kListParent then
		kListParent[FIELD_LIST_UNIT_SIZE_Y] = sizeY;
	end
end

-- ===========================================================================
function OnBuildingsButtonClicked()
	-- Building/District list is always at the top
	if m_CurrentListMode == LISTMODE.PRODUCTION then
		Controls.ProductionListScroll:SetScrollValue(0.0);
	elseif m_CurrentListMode == LISTMODE.PROD_QUEUE then
		Controls.QueueListScroll:SetScrollValue(0.0);
	elseif m_CurrentListMode == LISTMODE.PURCHASE_GOLD then
		Controls.PurchaseListScroll:SetScrollValue(0.0);
	elseif m_CurrentListMode == LISTMODE.PURCHASE_FAITH then
		Controls.PurchaseFaithListScroll:SetScrollValue(0.0);
	end
end

-- ===========================================================================
function OnWondersButtonClicked()
	if m_CurrentListMode == LISTMODE.PRODUCTION then
		ScrollToWonderList(Controls.ProductionList, Controls.ProductionListScroll);
	elseif m_CurrentListMode == LISTMODE.PROD_QUEUE then
		ScrollToWonderList(Controls.QueueList, Controls.QueueListScroll);
	end
end

-- ===========================================================================
function ScrollToWonderList(kListStack:table, kListScroll:table)
	local desiredScrollValue:number = kListStack[FIELD_LIST_BUILDING_SIZE_Y] / (kListStack:GetSizeY() - kListScroll:GetSizeY());
	kListScroll:SetScrollValue(desiredScrollValue);
end

-- ===========================================================================
function OnUnitsButtonClicked()
	if m_CurrentListMode == LISTMODE.PRODUCTION then
		ScrollToUnitList(Controls.ProductionList, Controls.ProductionListScroll);
	elseif m_CurrentListMode == LISTMODE.PROD_QUEUE then
		ScrollToUnitList(Controls.QueueList, Controls.QueueListScroll);
	elseif m_CurrentListMode == LISTMODE.PURCHASE_GOLD then
		ScrollToUnitList(Controls.PurchaseList, Controls.PurchaseListScroll);
	elseif m_CurrentListMode == LISTMODE.PURCHASE_FAITH then
		ScrollToUnitList(Controls.PurchaseFaithList, Controls.PurchaseFaithListScroll);
	end
end

-- ===========================================================================
function ScrollToUnitList(kListStack:table, kListScroll:table)
	local desiredScrollValue:number = (kListStack[FIELD_LIST_BUILDING_SIZE_Y] + kListStack[FIELD_LIST_WONDER_SIZE_Y]) / (kListStack:GetSizeY() - kListScroll:GetSizeY());
	kListScroll:SetScrollValue(desiredScrollValue);
end

-- ===========================================================================
function OnProjectsButtonClicked()
	if m_CurrentListMode == LISTMODE.PRODUCTION then
		ScrollToProjectList(Controls.ProductionList, Controls.ProductionListScroll);
	elseif m_CurrentListMode == LISTMODE.PROD_QUEUE then
		ScrollToProjectList(Controls.QueueList, Controls.QueueListScroll);
	end
end

-- ===========================================================================
function ScrollToProjectList(kListStack:table, kListScroll:table)
	local desiredScrollValue:number = (kListStack[FIELD_LIST_BUILDING_SIZE_Y] + kListStack[FIELD_LIST_WONDER_SIZE_Y] + kListStack[FIELD_LIST_UNIT_SIZE_Y]) / (kListStack:GetSizeY() - kListScroll:GetSizeY());
	kListScroll:SetScrollValue(desiredScrollValue);
end

-- ===========================================================================
function OnMoveItemLeftButtonClicked()
	if m_selectedQueueInstance ~= nil then
		local selectedItemIndex:number = m_selectedQueueInstance[FIELD_QUEUE_INDEX];
		SwapQueueItem(selectedItemIndex, selectedItemIndex - 1);
	end
end

-- ===========================================================================
function GetBuildInsertMode( tParameters:table )
	if m_isQueueOpen or m_isManagerOpen then
		if IsBuildQueueFull(city) then
			-- Replace last itme if queue is full
			tParameters[CityOperationTypes.PARAM_INSERT_MODE] = CityOperationTypes.VALUE_REPLACE_AT;
			tParameters[CityOperationTypes.PARAM_QUEUE_DESTINATION_LOCATION] = MAX_QUEUE_SIZE;
		else
			-- Append to end of queue
			tParameters[CityOperationTypes.PARAM_INSERT_MODE] = CityOperationTypes.VALUE_APPEND;
		end
	else
		tParameters[CityOperationTypes.PARAM_INSERT_MODE] = CityOperationTypes.VALUE_REPLACE_AT;
		tParameters[CityOperationTypes.PARAM_QUEUE_DESTINATION_LOCATION] = 0;
	end
end

-- ===========================================================================
function OnCityProductionQueueChanged(playerID, cityID, changeType, queueIndex)
	if playerID ~= Game.GetLocalPlayer() then
		return;
	end

	Refresh();
	SRA_OnProductionChanged();		-- ScreenReaderAccess

	-- Make sure we show the current production if we're in queue mode and adding the very first production to the city
	if m_isQueueOpen then
		Controls.CurrentProductionContainer:SetHide(not m_hasProductionToShow);
		Controls.NoProductionContainer:SetHide(m_hasProductionToShow);
	end
end

-- ===========================================================================
function IsBuildQueueFull()
	local pSelectedCity	= UI.GetHeadSelectedCity();
	if pSelectedCity then
		local pBuildQueue = pSelectedCity:GetBuildQueue();
		if pBuildQueue ~= nil then
			local iQueueSize:number = pBuildQueue:GetSize();
			if iQueueSize - 1 >= MAX_QUEUE_SIZE then
				return true;
			end
		end
	end

	return false;
end

-- ===========================================================================
function OnManagerSelectedIndexChanged( newIndex:number )
	m_SelectedManagerIndex = newIndex;
end

-- ===========================================================================
function Initialize()
	-- Cache tutorial status
	m_isTutorialRunning = IsTutorialRunning();

	Controls.PauseCollapseList:Stop();
	Controls.PauseDismissWindow:Stop();	
	CreateCorrectTabs();

	Controls.ProductionListScroll:RegisterScrollCallback(OnProductionListScrolled);
	Controls.PurchaseListScroll:RegisterScrollCallback(OnPurchaseListScrolled);
	Controls.PurchaseFaithListScroll:RegisterScrollCallback(OnPurchaseFaithListScrolled);
	Controls.QueueListScroll:RegisterScrollCallback(OnQueueListScrolled);

	Controls.CloseButton:RegisterCallback(Mouse.eLClick, OnClose);
	Controls.CloseButton:RegisterCallback( Mouse.eMouseEnter, function() UI.PlaySound("Main_Menu_Mouse_Over"); end);
	Controls.PauseCollapseList:RegisterEndCallback( OnCollapseTheList );
	Controls.PauseDismissWindow:RegisterEndCallback( OnHide );
	Controls.TopStackContainer:RegisterSizeChanged( OnTopStackContainerSizeChanged );
	Controls.TabContainer:RegisterSizeChanged( OnTabContainerSizeChanged );
	Controls.BuildingsButton:RegisterCallback( Mouse.eLClick, OnBuildingsButtonClicked );
	Controls.WondersButton:RegisterCallback( Mouse.eLClick, OnWondersButtonClicked );
	Controls.UnitsButton:RegisterCallback( Mouse.eLClick, OnUnitsButtonClicked );
	Controls.ProjectsButton:RegisterCallback( Mouse.eLClick, OnProjectsButtonClicked );
	Controls.CurrentProductionButton:RegisterCallback( Mouse.eLClick, function() OnItemClicked( Controls, Controls.CurrentProductionButton ); end);
	Controls.CurrentProductionButton:RegisterCallback( Mouse.eRClick, function() RemoveQueueItem(0); end );
	Controls.TrashButton:RegisterCallback( Mouse.eLClick, OnTrashClicked );

	UpdateQueueTabText(0);
	Controls.ManagerTab:SetText("[ICON_ProductionQueue] " .. Locale.Lookup("LOC_PRODUCTION_PANEL_MULTI_QUEUE"))

	ContextPtr:SetInitHandler( OnInit  );
	m_srList = KeyNavList_Create{		-- ScreenReaderAccess
		build = SRA_GetItems,
		isActive = function() return m_srActive and not ContextPtr:IsHidden() and m_CurrentListMode ~= -1; end,
		onActivate = SRA_OnActivate,
		onClose = SRA_OnClose,
		sectionCounts = true,		-- "Warrior, in Units, 12 items" when Down enters a group; "Units, 12: Warrior, ..." when PageUp / PageDown enter a group (like the J list)
		enterGuard = 0.6,		-- a quick second Enter after Next Action must not pick the recommended item
		extraKeys = { [Keys.VK_TAB] = SRA_NextTab },
		ctrlKeys = { [Keys.VK_TAB] = SRA_PrevTab },
	};
	ContextPtr:SetInputHandler( OnInputHandler, true );
	ContextPtr:SetShutdown( OnShutdown );

	SRListen( Events.CityProductionQueueChanged, OnCityProductionQueueChanged );
	SRListen( Events.TreasuryChanged, SRA_OnBalanceChanged );		-- ScreenReaderAccess
	SRListen( Events.FaithChanged, SRA_OnBalanceChanged );		-- ScreenReaderAccess
	SRListen( Events.CitySelectionChanged, OnCitySelectionChanged );
	SRListen( Events.InterfaceModeChanged, OnInterfaceModeChanged );
	SRListen( Events.UnitSelectionChanged, OnUnitSelectionChanged );
	SRListen( Events.LocalPlayerChanged, OnLocalPlayerChanged );
	SRListen( Events.InputActionTriggered, SRA_OnInputAction );		-- ScreenReaderAccess
	SRListen( LuaEvents.DiplomacyRibbon_OpenDiplomacyActionView, SRA_OnOpenDiplomacy );		-- ScreenReaderAccess		
	
	SRListen( LuaEvents.CityBannerManager_ProductionToggle, OnCityBannerManagerProductionToggle );
	SRListen( LuaEvents.CityPanel_ChooseProduction, OnCityPanelChooseProduction );
	SRListen( LuaEvents.CityPanel_ChoosePurchase, OnCityPanelChoosePurchase );
	SRListen( LuaEvents.CityPanel_ProductionClose, OnProductionClose );
	SRListen( LuaEvents.CityPanel_ProductionOpen, OnCityPanelProductionOpen );
	SRListen( LuaEvents.CityPanel_PurchaseGoldOpen, OnCityPanelPurchaseGoldOpen );
	SRListen( LuaEvents.CityPanel_PurchaseFaithOpen, OnCityPanelPurchaseFaithOpen );
	SRListen( LuaEvents.CityPanel_ProductionOpenForQueue, OnProductionOpenForQueue );	
	SRListen( LuaEvents.CityPanel_PurchasePlot, OnCityPanelPurchasePlot );
	SRListen( LuaEvents.GameDebug_Return, OnGameDebugReturn );
	SRListen( LuaEvents.NotificationPanel_ChooseProduction, OnNotificationPanelChooseProduction );
	SRListen( LuaEvents.StrageticView_MapPlacement_ProductionOpen, OnStrategicViewMapPlacementProductionOpen );
	SRListen( LuaEvents.Tutorial_ProductionOpen, OnTutorialProductionOpen );
	SRListen( LuaEvents.ProductionManager_SelectedIndexChanged, OnManagerSelectedIndexChanged );
end
Initialize();

