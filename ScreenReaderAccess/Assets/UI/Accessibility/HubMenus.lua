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
-- "Repairing Iron Mine, done next turn" (name "" = the tile is not known)
function HubMenus.RepairText( name:string )
	if name == nil or name == "" then return "Repairing, done next turn"; end
	return "Repairing " .. name .. ", done next turn";
end

-- Repair is spoken by the UnitOperationStarted event and by the menu's fallback timer; whichever comes first claims it.
-- (Per unit; a claim holds for 2 s, so the next Repair order is spoken again.)
HubMenus.m_repairSpoken = {};
function HubMenus.ClaimRepairSpeech( unitId:number, now:number )
	local last = HubMenus.m_repairSpoken[ unitId ];
	if last ~= nil and now - last < 2.0 then return false; end
	HubMenus.m_repairSpoken[ unitId ] = now;
	return true;
end

-- The result of Repair: what the builder's tile holds (a pillaged improvement, else a pillaged district). The value in
-- OPERATION_RESULTS may be a function( unitId ) returning the text (HubEvents.OnUnitOperationStarted calls it).
function HubMenus.RepairResult( unitId:number )
	local name:string = "";
	pcall( function()
		local unit:table = Players[ Game.GetLocalPlayer() ]:GetUnits():FindID( unitId );
		if unit == nil then return; end
		local plot:table = Map.GetPlot( unit:GetX(), unit:GetY() );
		if plot == nil then return; end
		local improvement = plot:GetImprovementType();
		local district = plot:GetDistrictType();
		if improvement ~= nil and improvement >= 0 and plot:IsImprovementPillaged() then
			name = Locale.Lookup( GameInfo.Improvements[ improvement ].Name );
		elseif district ~= nil and district >= 0 and plot:IsDistrictPillaged() then
			name = Locale.Lookup( GameInfo.Districts[ district ].Name );
		elseif improvement ~= nil and improvement >= 0 then
			name = Locale.Lookup( GameInfo.Improvements[ improvement ].Name );
		end
	end );
	return HubMenus.RepairText( name );
end
-- the event path: nil (silent) when the fallback already spoke
function HubMenus.RepairEventResult( unitId:number )
	if not HubMenus.ClaimRepairSpeech( unitId, UI.GetElapsedTime() ) then return nil; end
	return HubMenus.RepairResult( unitId );
end
HubMenus.OPERATION_RESULTS.UNITOPERATION_REPAIR = HubMenus.RepairEventResult;

-- "Rebasing to Lugdunum": the name of the city or district at the rebase / deploy target (the hub cursor sits on it while
-- the order is given). Pure helper: plotInfo = { city = name, district = name }.
function HubMenus.TargetPhrase( verb:string, plotInfo:table )
	local name:string = plotInfo ~= nil and ( plotInfo.city or plotInfo.district ) or nil;
	if name == nil or name == "" then return verb; end
	return verb .. " to " .. name;
end

local function CursorTargetResult( verb:string )
	local info:table = {};
	pcall( function()
		local plot:table = nil;
		local last = HubTargets ~= nil and HubTargets.m_lastDirectTarget or nil;
		if last ~= nil and last.plot ~= nil and last.time ~= nil and UI.GetElapsedTime() - last.time <= 3.0 then
			plot = Map.GetPlotByIndex( last.plot );
		end
		if plot == nil then
			local cx:number, cy:number = HubCursor.GetCursor();
			plot = Map.GetPlot( cx, cy );
		end
		if plot == nil then return; end
		local x:number, y:number = plot:GetX(), plot:GetY();
		local city:table = Cities.GetPlotPurchaseCity( plot );
		if city ~= nil and city:GetX() == x and city:GetY() == y then info.city = Locale.Lookup( city:GetName() ); return; end
		local districtType = plot:GetDistrictType();
		if districtType ~= nil and districtType >= 0 and GameInfo.Districts[ districtType ] ~= nil then
			info.district = Locale.Lookup( GameInfo.Districts[ districtType ].Name );
		end
	end );
	return HubMenus.TargetPhrase( verb, info );
end
HubMenus.OPERATION_RESULTS.UNITOPERATION_REBASE = function() return CursorTargetResult( "Rebasing" ); end;
HubMenus.OPERATION_RESULTS.UNITOPERATION_DEPLOY = function() return CursorTargetResult( "Deploying" ); end;

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
	local keyCount:table = {};
	for _, action in ipairs( m_unitActions ) do
		local text:string = action.name;
		if action.hotkey ~= nil and action.hotkey ~= "" then text = text .. ", key " .. action.hotkey; end
		if action.disabled then
			text = text .. ", unavailable" .. ( action.reason ~= "" and ( ": " .. action.reason ) or "" );
		end
		-- the n-th item with the same tag and name gets "#n" (two items with one key made the focus land on the first)
		local baseKey:string = tostring( action.tag ) .. "|" .. action.name;
		keyCount[ baseKey ] = ( keyCount[ baseKey ] or 0 ) + 1;
		table.insert( items, {
			key = ( keyCount[ baseKey ] > 1 ) and ( baseKey .. "#" .. keyCount[ baseKey ] ) or baseKey, text = text, detail = action.detail,
			choosable = not action.disabled, reason = ( action.reason ~= "" ) and action.reason or "Not available",
			action = action } );
	end
	return items;
end

-- What an action says once it ran. A great person's "Activate Mary Leakey: <effect>" becomes "Mary Leakey activated: <effect>",
-- a general's "Retire Timur: <effect>" "Timur retired: <effect>"; any other action name is spoken as it is.
function HubMenus.ActionResultText( name:string )
	return SRActionResultText( name );
end

local function BuildMenuItems()
	return m_menuItems;
end

local m_menu:table;

-- "Remove Improvement destroys the Mine on this tile. Enter again to confirm"
function HubMenus.ConfirmText( unit:table, typeName:string )
	local impName:string = "improvement";
	local resName:string = "resource";
	pcall( function()
		local plot = Map.GetPlot( unit:GetX(), unit:GetY() );
		local imp = GameInfo.Improvements[ plot:GetImprovementType() ];
		if imp ~= nil then impName = Locale.Lookup( imp.Name ); end
		local res = GameInfo.Resources[ plot:GetResourceType() ];
		if res ~= nil then resName = Locale.Lookup( res.Name ); end
	end );
	local text:string;
	if string.find( typeName, "HARVEST", 1, true ) ~= nil then
		text = "Harvest destroys the " .. resName .. " on this tile for a one-time yield";
	elseif string.find( typeName, "PILLAGE", 1, true ) ~= nil then
		text = "Pillage damages the " .. impName .. " on this tile";
	else
		text = "Remove Improvement destroys the " .. impName .. " on this tile";
	end
	return text .. ". Enter again to confirm";
end

local function RunMenuItem( item:table )
	local unit:table = UI.GetHeadSelectedUnit();
	if unit == nil then return; end
	if item.browse ~= nil then
		HubCore.CloseMode( false, false );
		item.browse.open();
		return;
	end
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
	-- Destructive builder actions (Remove Improvement, Harvest, Pillage) ask first: the menu stays open on the item, a second
	-- Enter on it (same unit, plot and action) within 5 s runs it.
	if item.action.destructive == true then
		local now:number = UI.GetElapsedTime();
		local id:string = unit:GetID() .. "|" .. unit:GetX() .. "," .. unit:GetY() .. "|" .. tostring( item.action.typeName );
		if HubMenus.m_confirm ~= nil and HubMenus.m_confirm.id == id and now - HubMenus.m_confirm.time <= 5.0 then
			HubMenus.m_confirm = nil;
		else
			HubMenus.m_confirm = { id = id, time = now };
			HubCore.SayResult( HubMenus.ConfirmText( unit, item.action.typeName ) );
			return;
		end
	end
	HubCore.CloseMode( false, false );
	local modeBefore:number = UI.GetInterfaceMode();
	LuaEvents.SRA_RunUnitAction( item.action.id, unit:GetID() );
	-- Fortify, sleep ... speak their result from the game's UnitOperationStarted event (so the hotkeys are covered too);
	-- target modes, found city, building and the like announce themselves. Anything else: say what was chosen.
	if item.action.typeName == "UNITOPERATION_REPAIR" then
		-- UnitOperationStarted normally speaks it (HubEvents); if nothing was said shortly after, say it here
		local unitId:number = unit:GetID();
		HubCore.After( 0.6, function()
			if HubMenus.ClaimRepairSpeech( unitId, UI.GetElapsedTime() ) then HubCore.SayResult( HubMenus.RepairResult( unitId ) ); end
		end );
	end
	if UI.GetInterfaceMode() == modeBefore and not RESULT_SILENT[ item.action.typeName ]
			and HubMenus.OPERATION_RESULTS[ item.action.typeName ] == nil then
		HubCore.SayResult( HubMenus.ActionResultText( item.action.name ) );
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
	local browser:table = ( HubSettle ~= nil ) and HubSettle.BrowserFor( unit ) or nil;
	if browser ~= nil then
		-- the mod's own browser (X on the map): first entry, so the controller reaches it too
		table.insert( m_menuItems, 1, { key = "browse|" .. browser.text, text = browser.text, detail = "Opens the same browser as the X key", browse = browser } );
	end
	if #m_menuItems == 0 then
		OutputMessageToScreenReader( PlotDescription_FormationName( unit, Locale.Lookup( unit:GetName() ) ) .. " has no actions" );
		return;
	end
	HubCore.OpenMode( "menu", m_menu, PlotDescription_FormationName( unit, Locale.Lookup( unit:GetName() ) ) .. " actions" );
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

-- The numbers of the game's diplomacy ribbon for one player, with the ribbon's hide rules (DiplomacyRibbon.lua ~180)
local function StandingValues( playerId:number )
	local vals:table = {};
	local player:table = Players[ playerId ];
	local yields:boolean = GameCapabilities.HasCapability( "CAPABILITY_DISPLAY_TOP_PANEL_YIELDS" );
	if Game.IsVictoryEnabled( "VICTORY_SCORE" ) and GameCapabilities.HasCapability( "CAPABILITY_DISPLAY_SCORE" ) then
		vals.score = player:GetScore();
	end
	if Game.IsVictoryEnabled( "VICTORY_CONQUEST" ) and yields then
		vals.military = player:GetStats():GetMilitaryStrengthWithoutTreasury();
	end
	if yields and GameCapabilities.HasCapability( "CAPABILITY_SCIENCE" ) then vals.science = player:GetTechs():GetScienceYield(); end
	if yields and GameCapabilities.HasCapability( "CAPABILITY_CULTURE" ) then vals.culture = player:GetCulture():GetCultureYield(); end
	if yields and GameCapabilities.HasCapability( "CAPABILITY_GOLD" ) then vals.gold = math.floor( player:GetTreasury():GetGoldBalance() ); end
	if yields and GameCapabilities.HasCapability( "CAPABILITY_RELIGION" ) then vals.faith = player:GetReligion():GetFaithBalance(); end
	return vals;
end

-- Known civs (you first, then the met majors), for the V list and the Control+R standing line
local function BuildStandingEntries()
	local entries:table = {};
	local localPlayer:number = Game.GetLocalPlayer();
	if not HubCore.IsLocalPlayerActive() then return entries; end
	local diplomacy:table = Players[ localPlayer ]:GetDiplomacy();
	table.insert( entries, { id = localPlayer, isYou = true, name = PlotDescription_GetCivName( localPlayer ), vals = StandingValues( localPlayer ) } );
	for _, other in ipairs( PlayerManager.GetAliveMajors() ) do
		local id:number = other:GetID();
		if id ~= localPlayer and diplomacy:HasMet( id ) then
			table.insert( entries, { id = id, isYou = false, name = PlotDescription_GetCivName( id ), vals = StandingValues( id ) } );
		end
	end
	return entries;
end

local function BuildCivItems()
	local items:table = {};
	local localPlayer:number = Game.GetLocalPlayer();
	local diplomacy:table = Players[ localPlayer ] ~= nil and Players[ localPlayer ]:GetDiplomacy() or nil;
	local you:table = nil;
	for _, entry in ipairs( BuildStandingEntries() ) do
		local head:string;
		if entry.isYou then
			head = "You, " .. entry.name;
		else
			local config:table = PlayerConfigurations[ entry.id ];
			local state:string = "at peace";
			if diplomacy:IsAtWarWith( entry.id ) then
				state = "at war";
			else
				-- the diplomacy screen's own relationship name (Neutral, Declared Friend, Allied, Denounced ...)
				local ai:table = Players[ entry.id ] ~= nil and Players[ entry.id ]:GetDiplomaticAI() or nil;
				local row:table = ( ai ~= nil ) and GameInfo.DiplomaticStates[ ai:GetDiplomaticStateIndex( localPlayer ) ] or nil;
				if row ~= nil and row.Name ~= nil then state = Locale.Lookup( row.Name ); end
			end
			head = Locale.Lookup( config:GetLeaderName() ) .. ", " .. entry.name .. ", " .. state;
		end
		local item:table = { key = "civ:" .. entry.id, civ = entry.id, isYou = entry.isYou, text = StandingText_ListItem( entry, head ) };
		if entry.isYou then you = item; else table.insert( items, item ); end
	end
	-- you come last (Up from the first civ wraps to it), so the first item stays the first civ met
	if you ~= nil then table.insert( items, you ); end
	return items;
end

-- Control+R: where the player stands among the known civs
function HubMenus.SpeakStanding()
	if not HubCore.IsLocalPlayerActive() then return; end
	local entries:table = BuildStandingEntries();
	OutputMessageToScreenReader( StandingText_Line( entries, 1 ) );
end

m_civMenu = KeyNavList_Create{
	build		= BuildCivItems,
	isActive	= function() return HubCore.IsModeOpen( "civ" ); end,
	onActivate	= function( item )
		if item.isYou then
			HubCore.SayResult( "That is you" );
			return;
		end
		HubCore.CloseMode( false, false );
		LuaEvents.DiplomacyRibbon_OpenDiplomacyActionView( item.civ );
	end,
	onClose		= function() HubCore.CloseMode( true, false ); end,
};

-- Always opens (the controller ring, HubPad); the keyboard toggle below closes an open list instead.
function HubMenus.OpenCivMenu()
	if not HubCore.IsLocalPlayerActive() then return; end
	if not HubTargets.CanOpenMode() then return; end
	if #BuildCivItems() <= 1 then
		OutputMessageToScreenReader( "You have not met any other civilization" );
		return;
	end
	HubCore.OpenMode( "civ", m_civMenu, "Diplomacy, met civilizations" );
end

function HubMenus.ToggleCivMenu()
	if not HubCore.IsLocalPlayerActive() then return; end
	if HubCore.IsModeOpen( "civ" ) then HubCore.CloseMode( true, false ); return; end
	HubMenus.OpenCivMenu();
end
