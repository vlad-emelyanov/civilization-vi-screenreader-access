-- ===========================================================================
--	HubMenus: unit actions menu (Tab) and diplomacy list (V).
--	Part of the InGameAccess hub (see docs/ingame-plan.md, Architecture): included by
--	UI/Additions/InGameAccess.lua. State and functions other hub modules use are fields of HubMenus.
-- ===========================================================================
HubMenus = {};

local m_unitActions			:table = {};		-- plain list of the selected unit's actions, sent by UnitPanel (SRA_UnitActions)
local m_menuItems			:table = {};		-- items of the unit actions menu, fetched when it opens

-- ===========================================================================
--	UNIT ACTIONS MENU (Tab): the actions of the game's own unit panel (Panels/UnitPanel.lua)
-- ===========================================================================
HubMenus.OPERATION_RESULTS = {
	UNITOPERATION_FORTIFY = "Fortified", UNITOPERATION_HEAL = "Fortified until healed", UNITOPERATION_SLEEP = "Sleeping",
	UNITOPERATION_ALERT = "On alert", UNITOPERATION_SKIP_TURN = "Turn skipped", UNITOPERATION_AUTOMATE_EXPLORE = "Exploring automatically",
	UNITOPERATION_REST_REPAIR = "Resting", UNITCOMMAND_WAKE = "Awake", UNITCOMMAND_CANCEL = "Orders cancelled",
};
-- Actions that announce their outcome in another way (events below, popups, target modes).
local RESULT_SILENT = {
	UNITOPERATION_FOUND_CITY = true, UNITOPERATION_BUILD_IMPROVEMENT = true, UNITCOMMAND_UPGRADE = true, PROMOTION = true,
	UNITOPERATION_MOVE_TO = true, UNITCOMMAND_PROMOTE = true,
};

function HubMenus.OnUnitActionsReceived( unitId:number, list:table )
	m_unitActions = list or {};
end

-- Asks UnitPanel for the selected unit's actions (it answers at once with SRA_UnitActions). refresh: let the panel
-- refresh its state first; only done when the menu opens and when an action is run, not on every key.
function HubMenus.FetchMenuItems( refresh:boolean )
	local items:table = {};
	if UI.GetHeadSelectedUnit() == nil then return items; end
	m_unitActions = {};
	LuaEvents.SRA_RequestUnitActions( refresh );
	for _, action in ipairs( m_unitActions ) do
		local text:string = action.name;
		if action.hotkey ~= nil and action.hotkey ~= "" then text = text .. ", key " .. action.hotkey; end
		if action.disabled then
			text = text .. ", unavailable" .. ( action.reason ~= "" and ( ": " .. action.reason ) or "" );
		end
		table.insert( items, {
			key = tostring( action.tag ) .. "|" .. action.name, text = text, detail = action.detail,
			choosable = not action.disabled, reason = ( action.reason ~= "" ) and action.reason or "Not available",
			action = action } );
	end
	return items;
end

local function BuildMenuItems()
	return m_menuItems;
end

local m_menu:table;

local function RunMenuItem( item:table )
	local unit:table = UI.GetHeadSelectedUnit();
	if unit == nil then return; end
	-- the state may have changed since the menu was opened: look the action up again, with a refresh
	local fresh:table = nil;
	for _, candidate in ipairs( HubMenus.FetchMenuItems( true ) ) do
		if candidate.key == item.key then fresh = candidate; end
	end
	if fresh == nil or fresh.choosable == false then
		HubCore.CloseMode( false, false );
		HubCore.SayResult( ( fresh ~= nil ) and fresh.reason or "No longer available" );
		return;
	end
	item = fresh;
	HubCore.CloseMode( false, false );
	local modeBefore:number = UI.GetInterfaceMode();
	LuaEvents.SRA_RunUnitAction( item.action.id, unit:GetID() );
	-- Fortify, sleep ... speak their result from the game's UnitOperationStarted event (so the hotkeys are covered too);
	-- target modes, found city, building and the like announce themselves. Anything else: say what was chosen.
	if UI.GetInterfaceMode() == modeBefore and not RESULT_SILENT[ item.action.typeName ]
			and HubMenus.OPERATION_RESULTS[ item.action.typeName ] == nil then
		HubCore.SayResult( item.action.name );
	end
end

function HubMenus.ToggleUnitMenu()
	if not HubCore.IsLocalPlayerActive() then return; end
	if HubCore.IsModeOpen( "menu" ) then
		HubCore.CloseMode( true, false );
		return;
	end
	local unit:table = UI.GetHeadSelectedUnit();
	if unit == nil then
		local city:table = UI.GetHeadSelectedCity();
		if city ~= nil and city:GetOwner() == Game.GetLocalPlayer() then
			-- A city has no action menu; Tab opens its production panel (Tab inside it switches Production / Purchase).
			HubCore.CloseMode( false, true );
			LuaEvents.CityPanel_ProductionOpen();
		elseif city ~= nil then
			OutputMessageToScreenReader( "Not your city" );
		else
			OutputMessageToScreenReader( "No unit selected" );
		end
		return;
	end
	if unit:GetOwner() ~= Game.GetLocalPlayer() then
		OutputMessageToScreenReader( "Not your unit" );
		return;
	end
	if not HubTargets.CanOpenMode() then return; end
	m_menuItems = HubMenus.FetchMenuItems( true );
	if #m_menuItems == 0 then
		OutputMessageToScreenReader( Locale.Lookup( unit:GetName() ) .. " has no actions" );
		return;
	end
	HubCore.OpenMode( "menu", m_menu, Locale.Lookup( unit:GetName() ) .. " actions" );
end

m_menu = KeyNavList_Create{
	build		= BuildMenuItems,
	isActive	= function() return HubCore.IsModeOpen( "menu" ); end,
	onActivate	= RunMenuItem,
	onClose		= function() HubCore.CloseMode( true, false ); end,
};

-- ===========================================================================
--	DIPLOMACY (V): the civilizations met so far; Enter opens the game's diplomacy screen with that leader
-- ===========================================================================
local m_civMenu:table;

local function BuildCivItems()
	local items:table = {};
	local localPlayer:number = Game.GetLocalPlayer();
	if not HubCore.IsLocalPlayerActive() then return items; end
	local diplomacy:table = Players[ localPlayer ]:GetDiplomacy();
	for _, other in ipairs( PlayerManager.GetAliveMajors() ) do
		local id:number = other:GetID();
		if id ~= localPlayer and diplomacy:HasMet( id ) then
			local config:table = PlayerConfigurations[ id ];
			local state:string = diplomacy:IsAtWarWith( id ) and "at war" or "at peace";
			table.insert( items, {
				key = "civ:" .. id, civ = id,
				text = Locale.Lookup( config:GetLeaderName() ) .. ", " .. PlotDescription_GetCivName( id ) .. ", " .. state,
			} );
		end
	end
	return items;
end

m_civMenu = KeyNavList_Create{
	build		= BuildCivItems,
	isActive	= function() return HubCore.IsModeOpen( "civ" ); end,
	onActivate	= function( item )
		HubCore.CloseMode( false, false );
		LuaEvents.DiplomacyRibbon_OpenDiplomacyActionView( item.civ );
	end,
	onClose		= function() HubCore.CloseMode( true, false ); end,
};

function HubMenus.ToggleCivMenu()
	if not HubCore.IsLocalPlayerActive() then return; end
	if HubCore.IsModeOpen( "civ" ) then HubCore.CloseMode( true, false ); return; end
	if not HubTargets.CanOpenMode() then return; end
	if #BuildCivItems() == 0 then
		OutputMessageToScreenReader( "You have not met any other civilization" );
		return;
	end
	HubCore.OpenMode( "civ", m_civMenu, "Diplomacy, met civilizations" );
end
