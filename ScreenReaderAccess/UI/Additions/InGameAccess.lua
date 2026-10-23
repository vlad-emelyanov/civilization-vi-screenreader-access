-- ===========================================================================
--	InGameAccess: screen reader hub for the in-game UI (see docs/ingame-plan.md).
--	A context without visuals, added to InGame (UI/Additions/InGameAccess.xml). It owns
--	  - the map cursor (Shift+Arrows) and its plot announcements,
--	  - the in-game hotkeys (I plot details, J cursor to selection, N what is next, Tab unit actions),
--	  - the unit actions menu and the target modes (move to, attack ...), which take over Up/Down/Enter/Escape and
--	    Shift+Arrows through this context's input handler (see the bottom of the file),
--	  - the regions: top panel (Control+Y), notifications (Control+N) and the city report (Control+I), with arrivals announced,
--	  - event announcements: unit/city selected, new turn, end of turn, unit results, enemies spotted.
--	Input order (verified, see docs/ingame-plan.md): this context's input handler runs before WorldInput and
--	ActionPanel; a key it consumes (KeyDown and KeyUp) also never becomes an input action.
-- ===========================================================================

Hub = {};		-- shared state and functions of the hub (the modules below add their own tables)

include( "ScreenReader" );
include( "KeyboardNavigation" );
include( "PlotDescription" );
include( "KeyNavList" );
include( "Civ6Common" );		-- MoveUnitToPlot (war declaration check + the right move/attack operation)
include( "SettleScan" );		-- settler: can settle here, best spots
include( "PlacementScan" );		-- city: where a district or wonder can go
include( "TopPanelData" );		-- top panel values as sentences (Control+Y, Control+G)
-- City report (Control+I): CityReportGather includes the game's CitySupport (GetCityData), which is heavy and may fail in
-- a ruleset: a failure here only loses the report, never the rest of the hub.
Hub.m_cityReportLoaded = pcall( function()
	include( "CityReportData" );
	include( "CityReportGather" );
end );
if not Hub.m_cityReportLoaded then print( "InGameAccess: the city report files did not load" ); end

-- ===========================================================================
--	MEMBERS
-- ===========================================================================

local m_actions				:table = {};		-- actionId -> handler
local m_enterLabel			:string = "";		-- what the action panel said Enter would do
local m_spottedTurn			:number = -1;		-- turn m_spottedCount counts
local m_spottedCount		:number = 0;

-- ===========================================================================
--	RESULTS of the player's orders and what happens around the player's units
-- ===========================================================================
local function OnUnitOperationStarted( ownerID:number, unitID:number, operationID:number )
	if ownerID ~= Game.GetLocalPlayer() or not HubCore.m_ready then return; end
	local row:table = GameInfo.UnitOperations[ operationID ];
	if row == nil then return; end
	local text:string = HubMenus.OPERATION_RESULTS[ row.OperationType ];
	if text ~= nil then HubCore.SayResult( text ); end
end

-- Automate Exploration starts no operation event (UnitOperationStarted); the game only adds the operation.
local function OnUnitOperationAdded( ownerID:number, unitID:number, hOperation:number, operationIndex:number )
	if ownerID ~= Game.GetLocalPlayer() or not HubCore.m_ready then return; end
	local row:table = GameInfo.UnitOperations[ operationIndex ];
	if row ~= nil and row.OperationType == "UNITOPERATION_HEAL" then
		-- Fortify Until Healed only adds the operation (no UnitOperationStarted, like Automate Exploration)
		if UI.GetElapsedTime() - HubCore.m_lastKeyTime <= 2.0 then HubCore.SayResult( HubMenus.OPERATION_RESULTS.UNITOPERATION_HEAL ); end
		return;
	end
	if row == nil or row.OperationType ~= "UNITOPERATION_AUTOMATE_EXPLORE" then return; end
	-- The game also re-adds the operation of units that are already exploring (every turn, after a load): only the
	-- order the player just gave is told. (The old "it has not moved" check after 1 s was dropped: unreliable.)
	if UI.GetElapsedTime() - HubCore.m_lastKeyTime > 2.0 then return; end
	HubCore.SayResult( HubMenus.OPERATION_RESULTS.UNITOPERATION_AUTOMATE_EXPLORE );
end

local function OnUnitCommandStarted( ownerID:number, unitID:number, commandID:number )
	if ownerID ~= Game.GetLocalPlayer() or not HubCore.m_ready then return; end
	local row:table = GameInfo.UnitCommands[ commandID ];
	if row == nil then return; end
	local text:string = HubMenus.OPERATION_RESULTS[ row.CommandType ];
	if text ~= nil then HubCore.SayResult( text ); end
end

-- The trade choosers hide their contexts (and so stop their update loops) when they close; they ask the hub to tell the
-- outcome a moment later. kind "route": a trade route was requested (unit, origin city owner and id, destination name);
-- kind "move": a trader was moved to another city (unit, plot it left, city name).
local function OnTradeResult( kind:string, unitID:number, a, b, c, d )
	local owner:number = Game.GetLocalPlayer();
	if kind == "route" then
		HubCore.After( 1.0, function()
			local origin:table = CityManager.GetCity( a, b );
			local started:boolean = false;
			if origin ~= nil then
				for _, route in ipairs( origin:GetTrade():GetOutgoingRoutes() ) do
					if route.TraderUnitID == unitID then started = true; end
				end
			end
			if started then
				HubCore.SayResult( "Trade route to " .. c .. " started" );
			else
				HubCore.SayResult( "Trade route to " .. c .. " requested, but the trader has no route yet" );
			end
		end );
	elseif kind == "move" then
		HubCore.After( 0.5, function()
			local unit:table = Players[ owner ]:GetUnits():FindID( unitID );
			if unit ~= nil and ( unit:GetX() ~= a or unit:GetY() ~= b ) then
				HubCore.SayResult( "Trader moved to " .. c );
			else
				HubCore.SayResult( "Trader not moved" );
			end
		end );
	end
end

local function MovesText( unit:table )
	return HubCore.FormatNumber( unit:GetMovesRemaining() ) .. " of " .. HubCore.FormatNumber( unit:GetMaxMoves() ) .. " moves";
end

-- A move ordered with Enter in the move-to mode: arrived, still on the way, or stopped short.
local function OnUnitMoveComplete( playerID:number, unitID:number, x:number, y:number )
	if playerID ~= Game.GetLocalPlayer() then return; end
	local record:table = HubCore.m_movers[ unitID ];
	if record == nil then return; end
	local unit:table = Players[ playerID ]:GetUnits():FindID( unitID );
	if unit == nil then
		HubCore.m_movers[ unitID ] = nil;
		return;
	end
	local plot:table = Map.GetPlot( x, y );
	if plot ~= nil and plot:GetIndex() == record.dest then
		HubCore.m_movers[ unitID ] = nil;
		local text:string = "Arrived, " .. MovesText( unit );
		if HubCore.IsSettler( unit ) then
			local ok:boolean, extra = SettleScan_CanFound( unit, plot );
			if not ok then
				text = text .. ", " .. SettleScan_CannotText( extra );
			elseif extra ~= true then
				text = text .. ", B to found the city";
			else
				text = text .. ", can settle, B to found next turn";
			end
		end
		HubCore.SayResult( text );
		return;
	end
	local queued = UnitManager.GetQueuedDestination( unit );
	if queued == nil then
		HubCore.m_movers[ unitID ] = nil;
		local destPlot:table = Map.GetPlotByIndex( record.dest );
		local text:string = "Stopped";
		if destPlot ~= nil and plot ~= nil then
			text = text .. ", " .. HubCore.Plural( Map.GetPlotDistance( x, y, destPlot:GetX(), destPlot:GetY() ), "tile", "tiles" ) .. " from the destination";
		end
		HubCore.SayResult( text );
		return;
	end
	-- still on the way: only said right after the order (not again every turn of a long move)
	if UI.GetElapsedTime() - ( record.issued or -100 ) > 3 then return; end
	local path:table = UnitManager.GetMoveToPathEx( unit, queued );
	local text:string = "Moving";
	if path ~= nil and path.turns ~= nil and #path.turns > 0 then
		text = text .. ", " .. HubCore.Plural( path.turns[ #path.turns ], "turn", "turns" ) .. " left";
	end
	HubCore.SayResult( text );
end

-- Who fights whom: the game announces a fight (CombatVisBegin) just before the damage events of both sides.
local m_combat:table = nil;

-- Spoken name of one side of a fight (unit or city).
function Hub.CombatSide( data:table )
	if data == nil or data.playerID == nil or data.playerID < 0 or Players[ data.playerID ] == nil then return nil; end
	local player:table = Players[ data.playerID ];
	local side:table = { player = data.playerID, id = data.componentID };
	if data.componentType == ComponentType.UNIT then
		local unit:table = player:GetUnits():FindID( data.componentID );
		if unit == nil then return nil; end
		side.name = PlotDescription_GetUnitName( unit );
		side.short = Locale.Lookup( unit:GetName() );
		side.x, side.y = unit:GetX(), unit:GetY();
		-- never name a unit the player cannot see (or an unmet civ behind it)
		if data.playerID ~= Game.GetLocalPlayer() and not ( HubCore.IsPlotVisibleToLocal( Map.GetPlot( side.x, side.y ) ) and PlotDescription_IsUnitVisible( unit ) ) then
			side.name, side.short, side.unseen = "An unseen unit", "The unseen unit", true;
		end
	else
		local city:table = nil;
		if data.componentType == ComponentType.DISTRICT then
			local district:table = player:GetDistricts():FindID( data.componentID );
			if district == nil then return nil; end
			city = district:GetCity();
			if city == nil then return nil; end
			side.x, side.y = district:GetX(), district:GetY();
		elseif data.componentType == ComponentType.CITY then
			city = player:GetCities():FindID( data.componentID );
			if city == nil then return nil; end
			side.x, side.y = city:GetX(), city:GetY();
		else
			return nil;
		end
		side.name = Locale.Lookup( city:GetName() );
		side.short = side.name;
	end
	if data.playerID == Game.GetLocalPlayer() and not side.unseen then side.name = "Your " .. side.name; end
	return side;
end

function Hub.OnCombatVisBegin( data:table )
	m_combat = nil;
	if not HubCore.m_ready or data == nil then return; end
	local attacker:table, defender:table = Hub.CombatSide( data[ CombatVisType.ATTACKER ] ), Hub.CombatSide( data[ CombatVisType.DEFENDER ] );
	if attacker == nil or defender == nil then return; end
	m_combat = { attacker = attacker, defender = defender, time = UI.GetElapsedTime(), told = false };
end

-- "3 tiles north-east of Rome": where a plot is, seen from the nearest own city (else the selected unit).
function Hub.PlaceFromOwn( x:number, y:number )
	local localPlayer:number = Game.GetLocalPlayer();
	local bestDistance:number, bestName:string, bestPlot:table = 99, nil, nil;
	for _, city in Players[ localPlayer ]:GetCities():Members() do
		local distance:number = Map.GetPlotDistance( x, y, city:GetX(), city:GetY() );
		if distance < bestDistance then
			bestDistance, bestName, bestPlot = distance, Locale.Lookup( city:GetName() ), Map.GetPlot( city:GetX(), city:GetY() );
		end
	end
	if bestName == nil then
		local selected:table = UI.GetHeadSelectedUnit();
		if selected ~= nil and selected:GetOwner() == localPlayer then
			bestName, bestPlot = "your " .. Locale.Lookup( selected:GetName() ), Map.GetPlot( selected:GetX(), selected:GetY() );
		end
	end
	if bestName == nil then return nil; end
	local relative:string = PlotDescription_GetRelative( bestPlot, Map.GetPlot( x, y ) );
	if relative == nil then return "at " .. bestName; end
	return relative .. " of " .. bestName;
end

function Hub.OnUnitDamageChanged( playerID:number, unitID:number, newDamage:number, oldDamage:number )
	if not HubCore.m_ready or newDamage <= oldDamage then return; end
	local player:table = Players[ playerID ];
	if player == nil then return; end
	local unit:table = player:GetUnits():FindID( unitID );
	if unit == nil then return; end
	if not HubCore.IsPlotVisibleToLocal( Map.GetPlot( unit:GetX(), unit:GetY() ) ) or not PlotDescription_IsUnitVisible( unit ) then return; end
	HubCore.RememberUnit( unit );
	-- only fights that concern the player: their own units, or anything close to their units and cities
	if playerID ~= Game.GetLocalPlayer() and not HubCore.IsNearLocal( unit:GetX(), unit:GetY(), 3 ) then return; end
	local name:string = PlotDescription_GetUnitName( unit );
	if playerID == Game.GetLocalPlayer() then name = "Your " .. name; end
	local maxDamage:number = unit:GetMaxDamage();
	if newDamage >= maxDamage then return; end		-- H.OnUnitKilledInCombat tells it
	local text:string = name .. " takes " .. ( newDamage - oldDamage ) .. " damage, " .. ( maxDamage - newDamage ) .. " of " .. maxDamage .. " left";
	-- the first damage line of a fight says who attacked whom (and where, when it is not our fight)
	local fight:table = m_combat;
	if fight ~= nil and not fight.told and UI.GetElapsedTime() - fight.time < 10
			and ( ( fight.attacker.player == playerID and fight.attacker.id == unitID ) or ( fight.defender.player == playerID and fight.defender.id == unitID ) ) then
		fight.told = true;
		local localPlayer:number = Game.GetLocalPlayer();
		local ours:boolean = fight.attacker.player == localPlayer or fight.defender.player == localPlayer;
		local victim:table = ( fight.defender.player == playerID and fight.defender.id == unitID ) and fight.defender or fight.attacker;
		local who:string = ( victim.player == localPlayer ) and victim.name or victim.short;
		local place:string = nil;
		if not ours then place = Hub.PlaceFromOwn( fight.defender.x, fight.defender.y ); end
		text = fight.attacker.name .. " attacks " .. fight.defender.name .. ( place ~= nil and ( ", " .. place ) or "" ) .. ": "
			.. who .. " takes " .. ( newDamage - oldDamage ) .. " damage, " .. ( maxDamage - newDamage ) .. " of " .. maxDamage .. " left";
	end
	OutputMessageToScreenReader( text, true );
	LuaEvents.SRA_CombatSpoken();		-- StatusMessagePanel drops its duplicate of this fight
end

-- (killed player, killed unit, killer player, killer unit): told when the local player is on either side.
function Hub.OnUnitKilledInCombat( killedPlayer:number, killedId:number, killerPlayer:number, killerId:number )
	if not HubCore.m_ready then return; end
	local localPlayer:number = Game.GetLocalPlayer();
	if killedPlayer ~= localPlayer and killerPlayer ~= localPlayer then return; end
	local function NameOf( playerID:number, unitID:number )
		local player:table = Players[ playerID ];
		local unit:table = ( player ~= nil ) and player:GetUnits():FindID( unitID ) or nil;
		if unit ~= nil then return PlotDescription_GetUnitName( unit ); end
		-- the unit is gone by now: the name remembered while it was alive
		return HubCore.m_unitNames[ playerID .. ":" .. unitID ];
	end
	local killed:string = NameOf( killedPlayer, killedId ) or "unit";
	local killer:string = NameOf( killerPlayer, killerId );
	local text:string;
	if killedPlayer == localPlayer then
		text = "Your " .. killed .. " was killed";
	else
		text = killed .. " killed";
	end
	if killer ~= nil then
		if killerPlayer == localPlayer then killer = "your " .. killer; end
		text = text .. " by " .. killer;
	end
	OutputMessageToScreenReader( text, true );
	LuaEvents.SRA_CombatSpoken();		-- StatusMessagePanel drops its duplicate of this fight
end

function Hub.OnCityAddedToMap( ownerID:number, cityID:number, x:number, y:number )
	if ownerID ~= Game.GetLocalPlayer() or not HubCore.m_ready then return; end
	local city:table = Players[ ownerID ]:GetCities():FindID( cityID );
	local name:string = ( city ~= nil ) and Locale.Lookup( city:GetName() ) or "City";
	HubCore.SayResult( name .. " founded" );
end

-- A builder finished an improvement on its own plot.
function Hub.OnImprovementAddedToMap( x:number, y:number, improvementType:number, owner:number )
	if owner ~= Game.GetLocalPlayer() or not HubCore.m_ready then return; end
	local unit:table = UI.GetHeadSelectedUnit();
	if unit == nil or unit:GetX() ~= x or unit:GetY() ~= y then return; end
	local row:table = GameInfo.Improvements[ improvementType ];
	if row == nil then return; end
	local name:string = Locale.Lookup( row.Name );
	local unitID:number = unit:GetID();
	HubCore.After( 0.4, function()	-- the charges are counted down a moment later
		local builder:table = Players[ owner ]:GetUnits():FindID( unitID );
		local text:string = name .. " built";
		if builder ~= nil then
			text = text .. ", " .. HubCore.Plural( builder:GetBuildCharges(), "charge", "charges" ) .. " left";
		else
			text = text .. ", the builder is used up";
		end
		HubCore.SayResult( text );
	end );
end

-- "Barbarian Warrior spotted, 2 tiles north of Rome": hostile soldiers that come into view near our cities and units.
function Hub.OnUnitVisibilityChanged( playerID:number, unitID:number, visibility:number )
	local localPlayer:number = Game.GetLocalPlayer();
	if not HubCore.m_ready or playerID == localPlayer or visibility ~= RevealedState.VISIBLE or not HubCore.IsHostile( playerID ) then return; end
	local unit:table = Players[ playerID ]:GetUnits():FindID( unitID );
	if unit == nil or ( unit:GetCombat() <= 0 and unit:GetRangedCombat() <= 0 ) then return; end
	if not PlotDescription_IsUnitVisible( unit ) then return; end
	HubCore.RememberUnit( unit );
	local turn:number = Game.GetCurrentGameTurn();
	local key:string = playerID .. ":" .. unitID;
	if HubCore.m_spotted[ key ] ~= nil and turn - HubCore.m_spotted[ key ] < 10 then return; end
	if m_spottedTurn ~= turn then m_spottedTurn = turn; m_spottedCount = 0; end
	if m_spottedCount >= 4 then return; end
	local x:number, y:number = unit:GetX(), unit:GetY();
	local bestDistance:number, bestName:string, bestPlot:table = 99, nil, nil;
	for _, city in Players[ localPlayer ]:GetCities():Members() do
		local distance:number = Map.GetPlotDistance( x, y, city:GetX(), city:GetY() );
		if distance < bestDistance then
			bestDistance, bestName, bestPlot = distance, Locale.Lookup( city:GetName() ), Map.GetPlot( city:GetX(), city:GetY() );
		end
	end
	for _, mine in Players[ localPlayer ]:GetUnits():Members() do
		local distance:number = Map.GetPlotDistance( x, y, mine:GetX(), mine:GetY() );
		if distance < bestDistance then
			bestDistance, bestName, bestPlot = distance, "your " .. Locale.Lookup( mine:GetName() ), Map.GetPlot( mine:GetX(), mine:GetY() );
		end
	end
	if bestName == nil or bestDistance > 4 then return; end
	HubCore.m_spotted[ key ] = turn;
	m_spottedCount = m_spottedCount + 1;
	local relative:string = PlotDescription_GetRelative( bestPlot, Map.GetPlot( x, y ) );
	local text:string = PlotDescription_GetUnitName( unit ) .. " spotted";
	if relative ~= nil then text = text .. ", " .. relative .. " of " .. bestName; else text = text .. " at " .. bestName; end
	HubRegions.m_lastSpotSpeech = UI.GetElapsedTime();
	OutputMessageToScreenReader( text, true );
end

-- ===========================================================================
--	ENTER (Next Action) must always say something
-- ===========================================================================
function Hub.IsGovernorLabel()
	local label:table = ContextPtr:LookUpControl( "/InGame/HUD/ActionPanel/EndTurnText" );
	local text:string = ( label ~= nil ) and label:GetText() or "";
	for _, key in ipairs( { "LOC_ACTION_PANEL_GOVERNOR_APPOINTMENT", "LOC_ACTION_PANEL_GOVERNOR_OPPORTUNITY", "LOC_ACTION_PANEL_GOVERNOR_PROMOTION", "LOC_ACTION_PANEL_GOVERNOR_IDLE" } ) do
		if text == Locale.Lookup( key ) then print( "InGameAccess: Enter held back, end-turn label '" .. text .. "' right after an attack" ); return true; end
	end
	return false;
end

function Hub.IsUnitOrdersLabel( text:string )
	return text == Locale.Lookup( "LOC_ACTION_PANEL_NEEDS_ORDERS" ) or text == Locale.Lookup( "LOC_ACTION_PANEL_STACKED_UNIT" )
		or text == Locale.Lookup( "LOC_ACTION_PANEL_UNIT_MOVES_REMAINING" );
end

function Hub.ArmEnterWatch()
	local label:table = ContextPtr:LookUpControl( "/InGame/HUD/ActionPanel/EndTurnText" );
	m_enterLabel = ( label ~= nil ) and label:GetText() or "";
	HubCore.m_enterWatch = 0.8;
end

-- Enter was pressed, nothing announced a new selection, turn end or mode: the game re-selected the same unit
-- (or none could be selected). Say what is going on.
function Hub.EnterFallback()
	if not Hub.IsUnitOrdersLabel( m_enterLabel ) then return; end
	local unit:table = UI.GetHeadSelectedUnit();
	if unit ~= nil then
		local text:string = HubAnnounce.UnitText( unit ) .. ", needs orders. Tab for its actions";
		-- a unit the game lets neither skip nor sleep (UnitPanel adds a disabled Skip Turn entry with the reason)
		local okHint:boolean, hint = pcall( function()
			for _, item in ipairs( HubMenus.FetchMenuItems( false ) ) do
				if item.action.typeName == "UNITOPERATION_SKIP_TURN" and item.action.disabled then return item.action.reason; end
			end
			return nil;
		end );
		if okHint and hint ~= nil and hint ~= "" then text = text .. ". Cannot skip: " .. hint; end
		HubCore.SayResult( text );
	else
		HubCore.SayResult( HubCore.Capitalize( CleanTextForSpeech( m_enterLabel ) ) );
	end
end

-- ===========================================================================
--	INPUT HANDLER: runs before WorldInput and ActionPanel (see docs/ingame-plan.md, Input order)
-- ===========================================================================
function Hub.HandleInput( input:table )
	if not HubCore.IsLocalPlayerActive() then return false; end
	local msg:number = input:GetMessageType();
	if msg ~= KeyEvents.KeyDown and msg ~= KeyEvents.KeyUp then return false; end
	HubCore.m_lastKeyTime = UI.GetElapsedTime();
	if HubCore.m_mode ~= nil then return HubCore.m_mode.list.HandleInput( input ); end
	if input:IsShiftDown() or input:IsControlDown() or input:IsAltDown() then return false; end
	local key:number = input:GetKey();
	if HubTargets.GetTargetMode() ~= nil then
		-- Enter and Escape belong to the mode; both KeyDown and KeyUp are consumed, so ActionPanel never sees Enter
		if UI.GetHeadSelectedUnit() == nil and UI.GetHeadSelectedCity() == nil then
			HubTargets.ResetStaleMode();		-- nothing left to act: the keys go to the game again
			return false;
		end
		if key == Keys.VK_RETURN or key == Keys.VK_ESCAPE then
			-- consumed even when the handler fails, so that Enter never falls through to Next Action mid-mode
			if msg == KeyEvents.KeyUp then
				local ok:boolean, err = xpcall( function() if key == Keys.VK_RETURN then HubTargets.ConfirmTarget(); else HubTargets.CancelTarget(); end end, KeyNavErrorHandler );
				if not ok then
					print( "InGameAccess target mode error: " .. tostring( err ) );
					OutputMessageToScreenReader( "Something went wrong, Escape to cancel" );
				end
			end
			return true;
		end
		return false;
	end
	-- Just after an attack the end-turn label can flash a governor blocker; Enter would open the Governors screen
	if key == Keys.VK_RETURN and UI.GetElapsedTime() - HubTargets.attackTime < 5 and Hub.IsGovernorLabel() then
		if msg == KeyEvents.KeyUp then HubCore.SayResult( "The attack is still resolving, press Enter again in a moment" ); end
		return true;
	end
	if key == Keys.VK_RETURN and msg == KeyEvents.KeyUp and not HubCore.IsGamePopupOpen() then Hub.ArmEnterWatch(); end		-- an open screen (City-States, governors) takes Enter itself
	return false;
end

function Hub.OnInput( input:table )
	local ok:boolean, consumed = xpcall( function() return Hub.HandleInput( input ); end, KeyNavErrorHandler );
	if not ok then
		print( "InGameAccess input error: " .. tostring( consumed ) );
		return false;
	end
	return consumed == true;
end

function Hub.OnUpdate( deltaTime:number )
	HubCursor.UpdateMouse( deltaTime );
	if HubCore.m_arrivalTimer >= 0 then
		HubCore.m_arrivalTimer = HubCore.m_arrivalTimer - deltaTime;
		if HubCore.m_arrivalTimer < 0 then
			HubCore.m_arrivalTimer = -1;
			local ok:boolean, err = xpcall( HubRegions.FlushArrivals, KeyNavErrorHandler );
			if not ok then print( "InGameAccess FlushArrivals error: " .. tostring(err) ); end
		end
	end
	local i:number = 1;
	while i <= #HubCore.m_delayed do
		local entry:table = HubCore.m_delayed[i];
		entry.time = entry.time - deltaTime;
		if entry.time <= 0 then
			table.remove( HubCore.m_delayed, i );
			local ok:boolean, err = xpcall( entry.fn, KeyNavErrorHandler );
			if not ok then print( "InGameAccess delayed call error: " .. tostring( err ) ); end
		else
			i = i + 1;
		end
	end
	if HubCore.m_enterWatch >= 0 then
		HubCore.m_enterWatch = HubCore.m_enterWatch - deltaTime;
		if HubCore.m_enterWatch < 0 then
			HubCore.m_enterWatch = -1;
			Hub.EnterFallback();
		end
	end
end

-- ===========================================================================
--	INPUT ACTIONS
-- ===========================================================================
function Hub.OnInputActionTriggered( actionId:number )
	local handler = m_actions[ actionId ];
	if handler ~= nil then handler(); end
end

function Hub.RegisterAction( name:string, handler )
	local id:number = Input.GetActionId( name );
	if id == nil then
		print( "InGameAccess: unknown input action " .. name );
		return;
	end
	m_actions[ id ] = HubCore.Safe( name, handler );
end

-- Hub modules (Accessibility/Hub*.lua), see docs/ingame-plan.md
include( "HubCore" );
include( "HubCursor" );
include( "HubTargets" );
include( "HubAnnounce" );
include( "HubSettle" );
include( "HubPlacement" );
include( "HubMenus" );
include( "HubRegions" );
include( "HubCityReport" );

-- ===========================================================================
function Initialize()
	-- Contexts added with AddUserInterfaces start hidden, and a hidden context gets no input actions or updates.
	ContextPtr:SetHide( false );

	-- A hot reload (civctl deploy) happens in the middle of a game: LoadScreenClose will not come again, so the hub would
	-- stay "not ready" (no event announcements) with a fresh state. Start it as it would be after the load, without
	-- repeating the turn announcement.
	if ContextPtr:IsHotLoad() and HubCore.IsLocalPlayerActive() then
		HubCore.m_ready = true;
		HubCore.m_cursorPlayer = Game.GetLocalPlayer();
		HubCore.m_lastAnnouncedTurn = Game.GetLocalPlayer() .. ":" .. Game.GetCurrentGameTurn();
		for _, unit in Players[ Game.GetLocalPlayer() ]:GetUnits():Members() do HubCore.RememberUnit( unit ); end
	end

	Hub.RegisterAction( "KeyNavMoveCellLeft",		function() HubCursor.MoveCursor( -1, 0 ); end );
	Hub.RegisterAction( "KeyNavMoveCellRight",		function() HubCursor.MoveCursor( 1, 0 ); end );
	Hub.RegisterAction( "KeyNavMoveCellUp",			function() HubCursor.MoveCursor( 0, 1 ); end );
	Hub.RegisterAction( "KeyNavMoveCellDown",		function() HubCursor.MoveCursor( 0, -1 ); end );
	Hub.RegisterAction( "KeyNavPlotDetails",		HubCursor.SpeakPlotDetails );
	Hub.RegisterAction( "KeyNavCursorToSelection",	HubCursor.CursorToSelection );
	Hub.RegisterAction( "KeyNavWhatsNext",			HubAnnounce.SpeakWhatsNext );
	Hub.RegisterAction( "KeyNavUnitActions",		HubMenus.ToggleUnitMenu );
	Hub.RegisterAction( "KeyNavSelectAtCursor",		HubCursor.SelectAtCursor );
	Hub.RegisterAction( "KeyNavCycleAllUnits",		HubCursor.CycleAllUnits );
	Hub.RegisterAction( "KeyNavScanUnits",			HubSettle.ScanKey );
	Hub.RegisterAction( "KeyNavDiplomacy",			HubMenus.ToggleCivMenu );
	Hub.RegisterAction( "KeyNavTopPanel",			HubRegions.ToggleTopPanel );
	Hub.RegisterAction( "KeyNavNotifications",		HubRegions.ToggleNotifications );
	Hub.RegisterAction( "KeyNavYields",				HubRegions.SpeakYields );
	Hub.RegisterAction( "KeyNavCityReport",			HubCityReport.ToggleCityReport );
	Hub.RegisterAction( "KeyNavReports",			HubTargets.ToggleReports );
	Hub.RegisterAction( "RangedAttack",			HubTargets.CityAttackKey );		-- R and W with a city selected: UnitPanel is hidden and silent
	Hub.RegisterAction( "Attack",					HubTargets.CityAttackKey );
	HubCore.Listen( Events.InputActionTriggered, Hub.OnInputActionTriggered );

	HubCore.Listen( Events.UnitSelectionChanged, HubCore.Safe( "UnitSelectionChanged", HubAnnounce.OnUnitSelectionChanged ) );
	HubCore.Listen( Events.CitySelectionChanged, HubCore.Safe( "CitySelectionChanged", HubAnnounce.OnCitySelectionChanged ) );
	HubCore.Listen( Events.LocalPlayerTurnBegin, HubCore.Safe( "LocalPlayerTurnBegin", HubAnnounce.AnnounceTurn ) );
	HubCore.Listen( Events.LoadScreenClose, HubCore.Safe( "LoadScreenClose", HubAnnounce.OnLoadScreenClose ) );
	HubCore.Listen( Events.LocalPlayerTurnEnd, HubCore.Safe( "LocalPlayerTurnEnd", HubAnnounce.OnLocalPlayerTurnEnd ) );

	HubCore.AddEvent( "InterfaceModeChanged",		HubTargets.OnInterfaceModeChanged );
	HubCore.AddEvent( "UnitOperationStarted",		OnUnitOperationStarted );
	HubCore.AddEvent( "UnitOperationAdded",			OnUnitOperationAdded );
	HubCore.AddEvent( "UnitCommandStarted",			OnUnitCommandStarted );
	HubCore.AddEvent( "UnitMoveComplete",			OnUnitMoveComplete );
	HubCore.AddEvent( "CombatVisBegin",				Hub.OnCombatVisBegin );
	HubCore.AddEvent( "UnitDamageChanged",			Hub.OnUnitDamageChanged );
	HubCore.AddEvent( "CityAddedToMap",				Hub.OnCityAddedToMap );
	HubCore.AddEvent( "ImprovementAddedToMap",		Hub.OnImprovementAddedToMap );
	HubCore.AddEvent( "UnitVisibilityChanged",		Hub.OnUnitVisibilityChanged );
	-- "Promoted: X" is spoken by the UnitPromotionPopup override (the only keyboard way to promote)
	HubCore.AddEvent( "UnitUpgraded",				function( player:number, unitID:number, unitType:number )
		local row:table = GameInfo.Units[ unitType ];
		if player == Game.GetLocalPlayer() and HubCore.m_ready and row ~= nil then HubCore.SayResult( "Upgraded to " .. Locale.Lookup( row.Name ) ); end
	end );
	HubCore.AddEvent( "UnitKilledInCombat",			Hub.OnUnitKilledInCombat );
	HubCore.Listen( LuaEvents.SRA_UnitActions, HubMenus.OnUnitActionsReceived );
	HubCore.Listen( LuaEvents.SRA_Notifications, HubRegions.OnNotificationsReceived );
	HubCore.Listen( LuaEvents.SRA_NotificationAdded, HubCore.Safe( "NotificationAdded", HubRegions.OnNotificationAdded ) );
	HubCore.Listen( LuaEvents.SRA_NotificationActivated, HubCore.Safe( "NotificationActivated", HubRegions.OnNotificationActivated ) );
	HubCore.Listen( LuaEvents.SRA_AttackKey, HubCore.Safe( "AttackKey", HubTargets.AttackKey ) );
	HubCore.Listen( LuaEvents.SRA_TradeResult, HubCore.Safe( "TradeResult", OnTradeResult ) );		-- trade choosers: outcome of the route / move
	HubCore.Listen( LuaEvents.SRA_CursorTo, HubCore.Safe( "CursorTo", function( x:number, y:number ) HubCursor.SetCursor( x, y, false, false, true ); end ) );		-- City-States screen: Show on map
	HubCore.AddEvent( "UnitRemovedFromMap",			function() HubCore.After( 0.3, HubTargets.ResetStaleMode ); end );
	HubCore.AddEvent( "UnitAddedToMap",				function( playerID:number, unitID:number )
		local player:table = Players[ playerID ];
		if player ~= nil then HubCore.RememberUnit( player:GetUnits():FindID( unitID ) ); end
	end );

	ContextPtr:SetInputHandler( Hub.OnInput, true );
	ContextPtr:SetUpdate( HubCore.Safe( "Update", Hub.OnUpdate ) );
	ContextPtr:SetShutdown( HubCore.OnShutdown );
end
Initialize();
